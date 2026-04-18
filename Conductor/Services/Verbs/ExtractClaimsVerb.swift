import Foundation

enum ExtractClaimsVerb: VerbDefinition {
    static let verb: Verb = .extractClaims
    static let lemmas = ["extract", "pull", "identify"]
    static let parameters: [VerbParameter] = []
    static let needs = [
        UpstreamEventNeed(eventTypeNames: ["SummaryProduced"], required: true)
    ]

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event] {
        fatalError("implemented in Task 26")
    }
}
