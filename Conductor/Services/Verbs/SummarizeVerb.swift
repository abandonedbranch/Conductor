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
        if let read = resolved.upstream.compactMap({ $0 as? ReadCompleted }).last {
            let gen = try await llm.summarize(text: read.body)
            return [SummaryProduced(
                summary: gen.summary,
                claims: gen.claims,
                sentiment: gen.sentiment,
                role: "articleSummary",
                origin: origin
            )]
        }
        if let results = resolved.upstream.compactMap({ $0 as? SearchResults }).last {
            let iteration = origin.iteration ?? 0
            guard iteration < results.papers.count else {
                return [StepFailed(stepID: origin.stepID ?? UUID(), message: "no paper at iteration", origin: origin)]
            }
            let paper = results.papers[iteration]
            let gen = try await llm.summarize(text: paper.abstract)
            return [SummaryProduced(
                summary: gen.summary,
                claims: gen.claims,
                sentiment: gen.sentiment,
                role: "paperSummary",
                origin: origin
            )]
        }
        return [StepFailed(stepID: origin.stepID ?? UUID(), message: "no readable upstream", origin: origin)]
    }
}
