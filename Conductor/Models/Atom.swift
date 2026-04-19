import Foundation

// Atoms are the typed inputs a verb consumes. A verb declares the atoms it
// needs via `VerbParameter`, and the Runtime resolves each one from
// (1) the event log, (2) a declared default, or (3) an interactive user ask
// through `AskView`. The three enums here are paired:
//
//   - `AtomKind` answers "what shape of input does this parameter accept?"
//   - `AtomValue` carries the resolved value.
//   - `AtomSource` records where the value came from, preserving provenance
//     for audit and UI.

/// The type of input a parameter expects. `AskView` branches on this enum
/// to pick the right SwiftUI affordance (TextField, Stepper, DatePicker,
/// multi-line TextEditor, or Picker for `.choice`).
///
/// `.choice(namespace:cases:)` is the mechanism for enum-style parameters
/// (e.g. `search.target` offers `pubMed | arxiv | web`). The namespace keeps
/// values disambiguated when multiple choice parameters coexist.
enum AtomKind: Sendable, Hashable {
    case url
    case number
    case date
    case text
    case choice(namespace: String, cases: [String])
}

/// A resolved atom. Mirrors `AtomKind` one-for-one so the grammar of
/// "accepted shapes" and "actual values" cannot drift apart.
enum AtomValue: Sendable, Hashable {
    case url(URL)
    case number(Double)
    case date(Date)
    case text(String)
    case choice(namespace: String, value: String)
}

/// Where an atom's value came from. Logged into `AtomRecorded.source` so the
/// UI and audit trail can distinguish LLM-inferred values from user input.
///
/// Order of this enum loosely matches the compile/runtime flow:
///   - `.detector` — Layer 1 (NSDataDetector) extracted it from prose.
///   - `.tagger` — Layer 2 (NLTagger) matched a parameter alias.
///   - `.embedding` — Layer 3 (NLEmbedding) resolved it via similarity.
///   - `.llm` — Layer 4 (Foundation Models) produced it.
///   - `.userAsked` — the Runtime asked the user via `AskView`.
enum AtomSource: Sendable, Hashable {
    case detector
    case tagger
    case embedding
    case llm
    case userAsked
}
