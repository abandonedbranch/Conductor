import Foundation
import FoundationModels

@Generable
enum Verb: String, CaseIterable, Sendable {
    case read
    case summarize
    case search
    case extractClaims
}

struct VerbParameter: Sendable {
    let role: String
    let kind: AtomKind
    let aliases: [String: String]
    let required: Bool
    let defaultValue: AtomValue?
}

struct UpstreamEventNeed: Sendable {
    let eventTypeNames: [String]
    let required: Bool
}

struct ResolvedInputs: Sendable {
    let atoms: [String: AtomValue]
    let upstream: [any Event]
}

protocol VerbDefinition: Sendable {
    static var verb: Verb { get }
    static var lemmas: [String] { get }
    static var parameters: [VerbParameter] { get }
    static var needs: [UpstreamEventNeed] { get }

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event]
}

extension VerbDefinition {
    var verb: Verb { Self.verb }
}
