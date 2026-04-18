import Foundation
import FoundationModels

protocol LLMSession: Sendable {
    func inferPipeline(from prose: String) async throws -> PipelineIntent
    func summarize(text: String) async throws -> SummaryGenerable
    func extractClaims(from summary: String) async throws -> ClaimsGenerable
}

struct FoundationModelsSession: LLMSession {
    func inferPipeline(from prose: String) async throws -> PipelineIntent {
        let session = LanguageModelSession(instructions: """
        You classify prose into a short list of verbs from a fixed enum. \
        Return only the verbs, in execution order.
        """)
        return try await session.respond(to: prose, generating: PipelineIntent.self).content
    }
    func summarize(text: String) async throws -> SummaryGenerable {
        let session = LanguageModelSession(instructions: """
        Summarize the given text in 2–4 sentences. Extract up to 5 factual claims. \
        Classify sentiment as "positive", "neutral", or "negative".
        """)
        return try await session.respond(to: text, generating: SummaryGenerable.self).content
    }
    func extractClaims(from summary: String) async throws -> ClaimsGenerable {
        let session = LanguageModelSession(instructions: """
        Return the factual claims in the given summary as a list of short strings. \
        One claim per item. No speculation.
        """)
        return try await session.respond(to: summary, generating: ClaimsGenerable.self).content
    }
}
