import Foundation

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
