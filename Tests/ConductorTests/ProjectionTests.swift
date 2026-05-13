import Testing
import Foundation
@testable import Conductor

@MainActor @Suite struct ProjectionTests {
    @Test func articleSummary_returnsLastWithArticleSummaryRole() {
        let log = EventLog()
        let id = UUID()
        log.append(SummaryProduced(summary: "A", claims: [], sentiment: "neutral", role: "articleSummary", origin: .step(id: id, index: 1)))
        log.append(SummaryProduced(summary: "B", claims: [], sentiment: "neutral", role: "paperSummary", origin: .step(id: UUID(), index: 2)))
        #expect(Projections.articleSummary(log: log.events)?.summary == "A")
    }

    @Test func pipelineStatus_reflectsCompletionPerStep() {
        let log = EventLog()
        let step1 = Step(index: 0, verb: .read)
        let step2 = Step(index: 1, verb: .summarize)
        log.append(ReadCompleted(body: "", title: "", url: URL(string: "https://x")!, origin: .step(id: step1.id, index: 0)))
        let statuses = Projections.pipelineStatus(log: log.events, steps: [step1, step2])
        #expect(statuses[0] == .completed)
        #expect(statuses[1] == .idle)
    }

    @Test func pipelineStatus_marksFailureFromStepFailed() {
        let step = Step(index: 0, verb: .read)
        let log = EventLog()
        log.append(StepFailed(stepID: step.id, message: "boom", origin: .step(id: step.id, index: 0)))
        let statuses = Projections.pipelineStatus(log: log.events, steps: [step])
        if case .failed = statuses[0] {} else { Issue.record("expected failed") }
    }

    @Test func searchResults_returnsLatest() {
        let log = EventLog()
        let p = Paper(title: "T", abstract: "A", identifier: "i", url: nil)
        log.append(SearchResults(papers: [p], target: "pubMed", origin: .step(id: UUID(), index: 2)))
        #expect(Projections.searchResults(log: log.events)?.papers.count == 1)
    }
}
