import Foundation

/// Provenance for an `Event` — which `Step` produced it and under what
/// circumstances. Use the `.compile()` or `.step(...)` factories; the memberwise
/// initializer is internal noise.
///
/// - `.compile()`: pre-pipeline work, primarily `AtomRecorded` events the
///   `ProseCompiler` emits from Layers 1–2 before any verb has run. All
///   fields are `nil`.
/// - `.step(id:index:iteration:parentStepID:)`: an event produced by a
///   specific `Step`. `iteration` is populated when the step is running
///   under for-each fan-out (e.g. summarize-per-paper), so multiple events
///   with the same `stepID` can be ordered. `parentStepID` is reserved for
///   nested fan-out and is currently unused by v2.
struct Origin: Sendable, Hashable {
    let stepID: UUID?
    let stepIndex: Int?
    let iteration: Int?
    let parentStepID: UUID?

    static func compile() -> Origin {
        Origin(stepID: nil, stepIndex: nil, iteration: nil, parentStepID: nil)
    }

    static func step(id: UUID, index: Int, iteration: Int? = nil, parentStepID: UUID? = nil) -> Origin {
        Origin(stepID: id, stepIndex: index, iteration: iteration, parentStepID: parentStepID)
    }
}
