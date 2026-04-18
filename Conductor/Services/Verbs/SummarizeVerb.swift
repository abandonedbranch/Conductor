import Foundation

enum SummarizeVerb: VerbDefinition {
    static let verb: Verb = .summarize
    static let lemmas = ["summarize", "summarise", "sum up", "digest"]
    static let parameters: [VerbParameter] = []
    static let needs = [
        UpstreamEventNeed(eventTypeNames: ["ReadCompleted", "SearchResults"], required: true)
    ]

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event] {
        fatalError("implemented in Task 20")
    }
}
