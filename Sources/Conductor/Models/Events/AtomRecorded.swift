import Foundation

/// An atom entered the log. Atoms are themselves `Event`s — not a separate
/// side-table — so the log stays the single source of truth for both "work
/// that happened" and "values that exist". The Runtime resolves verb
/// parameters by scanning the log for the latest `AtomRecorded` matching a
/// `role`, which is why atoms need provenance (`source`, `origin`) rather
/// than just a value.
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
