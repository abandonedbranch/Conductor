import Foundation
import Observation

/// Append-only log of every `Event` produced by the system. This is the
/// single point of coordination: verbs don't call each other, they consume
/// upstream events out of the log. Views are SwiftUI projections over it.
///
/// `@Observable` + `@MainActor` so SwiftUI can observe `events` directly.
/// There is no write-ahead queue or async buffer — verbs emit events on the
/// main actor via `Runtime`, which also reads resolved atoms back out. That
/// single-threaded ordering is why verbs don't need locks.
///
/// The helpers below are the read-side API verbs and projections use:
///   - `latestAtom(role:)` — resolves a parameter value.
///   - `allAtoms(role:)` — for roles that can legitimately repeat.
///   - `eventsOfType(_:)` — typed fold over the log.
@Observable
@MainActor
final class EventLog {
    private(set) var events: [any Event] = []

    func append(_ event: any Event) {
        events.append(event)
    }

    func append(_ batch: [any Event]) {
        events.append(contentsOf: batch)
    }

    func latestAtom(role: String) -> AtomRecorded? {
        events.reversed().compactMap { $0 as? AtomRecorded }.first { $0.role == role }
    }

    func allAtoms(role: String) -> [AtomRecorded] {
        events.compactMap { $0 as? AtomRecorded }.filter { $0.role == role }
    }

    func eventsOfType<E: Event>(_ type: E.Type) -> [E] {
        events.compactMap { $0 as? E }
    }
}
