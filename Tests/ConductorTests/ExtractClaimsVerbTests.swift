import Testing
import Foundation
@testable import Conductor

@Suite struct ExtractClaimsVerbTests {
    @Test func extractsClaimsFromLastSummary() async throws {
        let llm = FakeLLMSession()
        llm.scriptedClaims = ClaimsGenerable(claims: ["sky is blue", "water is wet"])
        let summary = SummaryProduced(summary: "the sky is blue; water is wet", claims: [], sentiment: "neutral", role: "articleSummary", origin: .step(id: UUID(), index: 0))
        let events = try await ExtractClaimsVerb.execute(
            resolved: ResolvedInputs(atoms: [:], upstream: [summary]),
            origin: .step(id: UUID(), index: 1),
            http: FakeHTTPClient(),
            llm: llm
        )
        let ce = events.compactMap { $0 as? ClaimsExtracted }.first
        #expect(ce?.claims.count == 2)
        #expect(ce?.claims.first?.text == "sky is blue")
    }
}
