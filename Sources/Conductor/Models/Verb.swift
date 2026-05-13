import Foundation
import FoundationModels

// MARK: - Verb parsing
//
// Verbs are how Conductor turns prose into a pipeline. The compiler resolves
// each candidate verb word through four layers, consulting the LLM last:
//
//   1. `Layer2Tagger` lemmatises the prose with `NLTagger` and matches the
//      canonical lemma of each word against `VerbDefinition.lemmas`
//      (e.g. "summarise" → "summarize" → `.summarize`). Parameter atoms
//      (URLs, numbers, dates) are extracted in parallel by Layer 1
//      (`NSDataDetector`) and assigned to the nearest verb by word position.
//   2. `Layer3Embedder` falls back to `NLEmbedding` cosine similarity when no
//      lemma matched (e.g. "brief" → `.summarize`). Still deterministic and
//      on-device.
//   3. `IntentSession` (Layer 4) invokes the Foundation Model *only* for
//      verb words the first three layers couldn't classify. The model emits
//      a `@Generable` `Verb` case — never prose, never URLs.
//
// A `Verb` is the enum case that names the operation. A `VerbDefinition`
// (one per case, looked up via `VerbCatalog`) is the static spec: lemmas the
// compiler matches against, parameters it must resolve, events it needs from
// the log, and the `execute` closure the Runtime calls.

/// The set of operations Conductor can run. `@Generable` so Layer 4 can
/// return a case directly from the LLM without string parsing.
@Generable
enum Verb: String, CaseIterable, Sendable {
    /// Fetch a URL and emit its text body as a `ReadCompleted` event.
    case read
    /// Produce a typed summary (prose + claims + sentiment) from upstream
    /// `ReadCompleted` or per-paper `SearchResults`. Invokes the LLM.
    case summarize
    /// Dispatch to a `SearchBackend` (PubMed / arXiv / web) and emit a
    /// `SearchResults` event containing `[Paper]`.
    case search
    /// Ask the LLM to extract propositional claims from an upstream
    /// `SummaryProduced.summary`. Emits a `ClaimsExtracted` event.
    case extractClaims
}

/// A named input a verb needs resolved before it can run.
///
/// - `role`: canonical key used by `AtomRecorded` and `ResolvedInputs`
///   (e.g. `"url"`, `"search.terms"`, `"search.target"`).
/// - `kind`: the atom type the resolver and `AskView` expect.
/// - `aliases`: alternate surface words → role mapping, consulted by the
///   Layer 2 alias pass (e.g. `"link"` → `"url"`).
/// - `required`: if `true`, the Runtime asks the user when no atom and no
///   default are available, and emits `StepFailed` if the user declines.
/// - `defaultValue`: used when the log has no matching atom and the user
///   hasn't been asked.
struct VerbParameter: Sendable {
    let role: String
    let kind: AtomKind
    let aliases: [String: String]
    let required: Bool
    let defaultValue: AtomValue?
}

/// Declares events a verb consumes from the event log.
///
/// `eventTypeNames` are compared against `String(describing: type(of:))` of
/// each logged event (e.g. `"ReadCompleted"`, `"SearchResults"`). Drives two
/// pieces of machinery:
///   1. `NeedsClosure` — inflates producer verbs into the pipeline when a
///      required need is unsatisfied by earlier verbs.
///   2. `Runtime.collectionFanOutCount` — when a need references a
///      `SearchResults` with >1 papers, the step runs once per paper.
struct UpstreamEventNeed: Sendable {
    let eventTypeNames: [String]
    let required: Bool
}

/// What the Runtime hands a verb at execute time.
///
/// - `atoms`: role → value map, populated from the event log, defaults, or
///   user asks.
/// - `upstream`: logged events matching the verb's declared needs, in log
///   order. A verb reads whichever upstream events it knows how to consume
///   (see `SummarizeVerb`, which handles both `ReadCompleted` and
///   per-iteration `SearchResults`).
struct ResolvedInputs: Sendable {
    let atoms: [String: AtomValue]
    let upstream: [any Event]
}

/// Static spec for one `Verb`. Each case in the `Verb` enum has exactly one
/// `VerbDefinition`, registered in `VerbCatalog`.
///
/// - `verb`: which case this definition implements.
/// - `lemmas`: canonical verb words Layer 2 matches against.
/// - `parameters`: inputs the Runtime must resolve before `execute` runs.
/// - `needs`: upstream events the verb consumes, driving needs-closure
///   inflation and for-each fan-out.
/// - `execute`: the actual work. Pure function of its inputs — no hidden
///   state, no session handoff between calls. Returns the events the
///   Runtime should append to the log, including any `StepFailed` the verb
///   produces for recoverable failures.
protocol VerbDefinition: Sendable {
    static var verb: Verb { get }
    static var lemmas: [String] { get }
    static var parameters: [VerbParameter] { get }
    static var needs: [UpstreamEventNeed] { get }

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event]
}

extension VerbDefinition {
    var verb: Verb { Self.verb }
}
