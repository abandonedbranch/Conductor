import Foundation

enum AtomKind: Sendable, Hashable {
    case url
    case number
    case date
    case text
    case choice(namespace: String, cases: [String])
}

enum AtomValue: Sendable, Hashable {
    case url(URL)
    case number(Double)
    case date(Date)
    case text(String)
    case choice(namespace: String, value: String)
}

enum AtomSource: Sendable, Hashable {
    case detector
    case tagger
    case embedding
    case llm
    case userAsked
}
