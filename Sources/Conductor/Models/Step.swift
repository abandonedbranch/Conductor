import Foundation

/// One position in a compiled pipeline: a `Verb` bound to a stable identity.
///
/// A pipeline is `[Step]`, not `[Verb]`, so that events emitted by the
/// Runtime can be attributed back to a specific position even when the same
/// verb appears more than once — e.g. a `summarize` after `read`, then
/// another `summarize` fanned out across `search` results. Every event's
/// `Origin` carries this `id`; `Projections.pipelineStatus` and the
/// `StepFailed` attribution both match on it.
///
/// `index` is the ordinal in the compiled pipeline (0-based). `id` is a
/// fresh UUID per construction — two `Step`s with the same verb and index
/// are not equal, because they represent different runs.
struct Step: Sendable, Identifiable, Hashable {
    let id: UUID
    let index: Int
    let verb: Verb

    init(index: Int, verb: Verb) {
        self.id = UUID()
        self.index = index
        self.verb = verb
    }
}
