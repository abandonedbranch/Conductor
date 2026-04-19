import Testing
import Foundation
@testable import Conductor

@Suite struct SummarizeVerbTests {
    @Test func summarizesReadCompletedArticle() async throws {
        let llm = FakeLLMSession()
        llm.scriptedSummary = SummaryGenerable(summary: "Short.", claims: ["c1"], sentiment: "neutral")
        let read = ReadCompleted(body: "long body", title: "T", url: URL(string: "https://x")!, origin: .step(id: UUID(), index: 0))
        let inputs = ResolvedInputs(atoms: [:], upstream: [read])
        let events = try await SummarizeVerb.execute(
            resolved: inputs,
            origin: .step(id: UUID(), index: 1),
            http: FakeHTTPClient(),
            llm: llm
        )
        let summary = events.compactMap { $0 as? SummaryProduced }.first
        #expect(summary?.summary == "Short.")
        #expect(summary?.role == "articleSummary")
    }

    @Test func rolesAsPaperSummary_whenSourceIsSearchResult() async throws {
        let llm = FakeLLMSession()
        llm.scriptedSummary = SummaryGenerable(summary: "Paper gist.", claims: [], sentiment: "neutral")
        let p = Paper(title: "P", abstract: "A", identifier: "i", url: nil)
        let results = SearchResults(papers: [p], target: "pubMed", origin: .step(id: UUID(), index: 0))
        let inputs = ResolvedInputs(atoms: [:], upstream: [results])
        let events = try await SummarizeVerb.execute(
            resolved: inputs,
            origin: .step(id: UUID(), index: 1, iteration: 0),
            http: FakeHTTPClient(),
            llm: llm
        )
        #expect((events.first as? SummaryProduced)?.role == "paperSummary")
    }
}
