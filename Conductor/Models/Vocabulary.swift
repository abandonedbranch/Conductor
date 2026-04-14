import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Generable
enum IntentVerb: String, Codable, CaseIterable, Sendable {
    case find
    case summarize
    case recall
    case build
    case read
}

@available(iOS 19.0, macOS 26.0, *)
@Generable
enum IntentSubject: String, Codable, CaseIterable, Sendable {
    case academic
    case biomedical
    case preprint
    case encyclopedic
    case webpage
    case workflow
    case conversational
}

@available(iOS 19.0, macOS 26.0, *)
@Generable
enum AnswerShape: String, Codable, CaseIterable, Sendable {
    case overview
    case summary
    case citations
    case workflow
    case direct
}
