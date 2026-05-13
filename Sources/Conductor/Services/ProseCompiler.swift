import Foundation

/// What compilation produced: an ordered verb pipeline, the atoms the
/// compiler extracted to seed the event log, and whether the LLM had to be
/// consulted. `usedLLM` drives the corpus test's "≥70% L4-free" assertion
/// — it's how the project measures how often the deterministic layers
/// carry the load.
struct CompileResult: Sendable {
    let verbs: [Verb]
    let atoms: [AtomRecorded]
    let usedLLM: Bool
}

/// Compiles prose into a pipeline, consulting the LLM last.
///
/// The four layers run in strict fallback order, each only invoked when the
/// previous left gaps:
///
///   1. `Layer1DataDetector` — NSDataDetector extracts URLs, numbers, dates
///      as `AtomRecorded` events (origin `.compile()`).
///   2. `Layer2Tagger` — NLTagger produces the verb list by lemma match,
///      and emits additional atoms for parameter aliases and "about X"
///      topic phrases.
///   3. `Layer3Embedding` — only if Layer 2 matched zero verbs; NLEmbedding
///      cosine similarity matches verb-shaped words to canonical cases.
///   4. `Layer4IntentSession` — only if Layers 2+3 still produced zero
///      verbs; a FoundationModels call whose output is a `@Generable`
///      `PipelineIntent`. This is the only layer that invokes the LLM.
///
/// After classification, `NeedsClosure.inflate` walks the verb list and
/// prepends any producers whose output the later verbs depend on — e.g.
/// `[.summarize]` becomes `[.read, .summarize]`, so a user who only said
/// "summarize https://example.com" still gets a working pipeline.
enum ProseCompiler {
    static func compile(prose: String, llm: any LLMSession) async throws -> CompileResult {
        let l1 = Layer1DataDetector.extract(from: prose)
        let l2 = Layer2Tagger.extract(from: prose)

        var verbs = l2.verbs
        var usedLLM = false

        // Layer 3: for each verb-tagged word that didn't resolve, try embedding.
        // (Simple v2 version: if L2 found zero verbs, run L3 over raw verb-like words.)
        if verbs.isEmpty {
            let fallback = verbLikeWords(in: prose).compactMap { Layer3Embedding.fuzzyMatch(lemma: $0) }
            verbs = dedupeStable(fallback)
        }

        // Layer 4: last resort.
        if verbs.isEmpty {
            verbs = try await Layer4IntentSession.classify(prose: prose, llm: llm)
            usedLLM = true
        }

        // Needs closure: prepend any upstream verbs required by the detected verbs.
        verbs = NeedsClosure.inflate(verbs: verbs, existingLog: [])

        return CompileResult(verbs: verbs, atoms: l1 + l2.atoms, usedLLM: usedLLM)
    }

    private static func verbLikeWords(in prose: String) -> [String] {
        prose.split(whereSeparator: { !$0.isLetter }).map { String($0).lowercased() }
    }

    private static func dedupeStable(_ verbs: [Verb]) -> [Verb] {
        var seen: Set<Verb> = []
        var out: [Verb] = []
        for v in verbs where !seen.contains(v) { seen.insert(v); out.append(v) }
        return out
    }
}
