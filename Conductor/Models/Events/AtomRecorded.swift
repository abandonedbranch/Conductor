import Foundation

struct AtomRecorded: Event {
    let id: UUID
    let timestamp: Date
    let role: String
    let value: AtomValue
    let source: AtomSource
    let origin: Origin

    init(role: String, value: AtomValue, source: AtomSource, origin: Origin) {
        self.id = UUID()
        self.timestamp = Date()
        self.role = role
        self.value = value
        self.source = source
        self.origin = origin
    }
}
