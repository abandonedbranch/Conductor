import Foundation
@testable import Conductor
import FoundationModels

final class FakeLLMSession: LLMSession, @unchecked Sendable {
    var scriptedIntent: PipelineIntent?
    var scriptedSummary: SummaryGenerable?
    var scriptedClaims: ClaimsGenerable?

    func inferPipeline(from prose: String) async throws -> PipelineIntent {
        guard let i = scriptedIntent else { throw NSError(domain: "fake", code: 0) }
        return i
    }
    func summarize(text: String) async throws -> SummaryGenerable {
        guard let s = scriptedSummary else { throw NSError(domain: "fake", code: 0) }
        return s
    }
    func extractClaims(from summary: String) async throws -> ClaimsGenerable {
        guard let c = scriptedClaims else { throw NSError(domain: "fake", code: 0) }
        return c
    }
}
