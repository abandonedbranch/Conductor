import Foundation
import FoundationModels

/// The on-device LLM boundary. Every method is a stateless typed inference:
/// `(instructions, input) → @Generable output`. There is no shared session
/// state between calls — see the concrete implementation for why.
protocol LLMSession: Sendable {
    func inferPipeline(from prose: String) async throws -> PipelineIntent
    func summarize(text: String) async throws -> SummaryGenerable
    func extractClaims(from summary: String) async throws -> ClaimsGenerable
}

/// Production `LLMSession` backed by Foundation Models.
///
/// Each method constructs a fresh `LanguageModelSession` with the
/// instructions scoped to that call and destroys it on return. Nothing
/// about one call's session survives to the next. When one call's output
/// must inform another, the orchestrating code (Runtime, verb dispatch)
/// writes it to the `EventLog` and the next call reads it back through
/// its instructions/input — not through session history.
///
/// This is enforced by the `LLMSession` protocol's shape: the inputs are
/// plain values (prose, text, summary), never a conversation handle.
/// Nothing in the protocol lets a caller thread context through implicitly.
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
