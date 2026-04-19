import Foundation

struct CompileResult: Sendable {
    let verbs: [Verb]
    let atoms: [AtomRecorded]
    let usedLLM: Bool
}

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
