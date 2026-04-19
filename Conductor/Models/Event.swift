import Foundation

/// A fact that happened. Conductor is event-sourced: the `EventLog` is the
/// source of truth, and every observable piece of UI state is a projection
/// (fold) over the events.
///
/// Every event carries an `Origin` — the step that produced it, the
/// iteration within a fan-out, or `.compile()` for atoms extracted before
/// any verb ran. `Projections.pipelineStatus` and `StepFailed` attribution
/// both rely on this provenance to correlate events back to the `Step` that
/// emitted them.
///
/// Events are immutable values. Verbs emit new events; they never mutate
/// older ones. If something about an earlier event turns out to be wrong,
/// emit a corrective event — don't rewrite history.
protocol Event: Sendable {
    var id: UUID { get }
    var origin: Origin { get }
    var timestamp: Date { get }
}
