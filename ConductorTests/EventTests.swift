import Testing
import Foundation
@testable import Conductor

@Suite struct EventTests {
    private struct DummyEvent: Event {
        let id = UUID()
        let origin = Origin.compile()
        let timestamp = Date()
    }

    @Test func eventProtocol_requiresIDAndOrigin() {
        let e = DummyEvent()
        #expect(e.origin.stepID == nil)
        #expect(type(of: e.id) == UUID.self)
    }
}

@Suite struct VerbOutputEventTests {
    @Test func readCompleted_carriesBodyTitleURL() {
        let e = ReadCompleted(body: "B", title: "T", url: URL(string: "https://x")!, origin: .step(id: UUID(), index: 0))
        #expect(e.body == "B")
        #expect(e.title == "T")
    }

    @Test func summaryProduced_carriesRole() {
        let e = SummaryProduced(summary: "S", claims: ["c1"], sentiment: "neutral", role: "articleSummary", origin: .step(id: UUID(), index: 1))
        #expect(e.role == "articleSummary")
        #expect(e.claims.count == 1)
    }

    @Test func searchResults_carriesTarget() {
        let paper = Paper(title: "P", abstract: "A", identifier: "id1", url: nil)
        let e = SearchResults(papers: [paper], target: "pubMed", origin: .step(id: UUID(), index: 2))
        #expect(e.target == "pubMed")
        #expect(e.papers.count == 1)
    }

    @Test func claimsExtracted_carriesClaims() {
        let c = Claim(text: "the sky is blue")
        let e = ClaimsExtracted(claims: [c], origin: .step(id: UUID(), index: 3))
        #expect(e.claims.first?.text == "the sky is blue")
    }

    @Test func stepFailed_carriesError() {
        let e = StepFailed(stepID: UUID(), message: "boom", origin: .compile())
        #expect(e.message == "boom")
    }
}
