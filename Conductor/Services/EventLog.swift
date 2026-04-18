import Foundation
import Observation

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
