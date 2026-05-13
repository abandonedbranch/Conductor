import Foundation
import FoundationModels

@Generable
struct PipelineIntent: Sendable {
    @Guide(description: "The verbs the user wants executed, in order.")
    let verbs: [Verb]
}

@Generable
struct SummaryGenerable: Sendable {
    @Guide(description: "A short prose summary, 2–4 sentences.")
    let summary: String
    @Guide(description: "Factual claims present in the text, as short strings.")
    let claims: [String]
    @Guide(description: "Sentiment label.")
    let sentiment: String
}

@Generable
struct ClaimsGenerable: Sendable {
    @Guide(description: "Factual claims, one per entry.")
    let claims: [String]
}
