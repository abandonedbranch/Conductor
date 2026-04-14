import Foundation

// Atom uses SE-0295 synthesized Codable. The case names (`success`, `error`, `note`)
// and every associated-value label are part of the persistence contract —
// renaming any of them silently breaks decoding of previously persisted data.
// Any rename requires a migration path.
enum Atom: Codable, Sendable {
    case success(content: String, source: URL?, toolName: String, timestamp: Date)
    case error(ErrorAtom)
    case note(text: String, timestamp: Date)
}

struct ErrorAtom: Codable, Sendable, Hashable {
    let actionID: UUID
    let toolName: String?
    let kind: ErrorKind
    let message: String
    let timestamp: Date
}

enum ErrorKind: String, Codable, Sendable, CaseIterable {
    case networkError
    case unsafeContent
    case timeout
    case noResults
    case unknown
}
