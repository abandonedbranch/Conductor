import Testing
import Foundation
@testable import Conductor

@MainActor @Suite struct RuntimeTests {
    @Test func runs_readThenSummarize_endToEnd() async throws {
        let log = EventLog()
        let http = FakeHTTPClient()
        let llm = FakeLLMSession()
        let url = URL(string: "https://example.com")!
        http.scripted[url] = Data("<title>T</title><body>B</body>".utf8)
        llm.scriptedSummary = SummaryGenerable(summary: "Short.", claims: [], sentiment: "neutral")

        log.append(AtomRecorded(role: "url", value: .url(url), source: .detector, origin: .compile()))

        let runtime = Runtime(log: log, http: http, llm: llm, askResolver: AutoAcceptAskResolver())
        try await runtime.run(steps: [Step(index: 0, verb: .read), Step(index: 1, verb: .summarize)])

        #expect(log.eventsOfType(ReadCompleted.self).count == 1)
        #expect(log.eventsOfType(SummaryProduced.self).count == 1)
    }

    @Test func asks_whenRequiredAtomMissing() async throws {
        let log = EventLog()
        let asker = RecordingAskResolver(responses: [
            "url": .url(URL(string: "https://asked.com")!)
        ])
        let http = FakeHTTPClient()
        http.scripted[URL(string: "https://asked.com")!] = Data("<title>X</title>".utf8)
        let runtime = Runtime(log: log, http: http, llm: FakeLLMSession(), askResolver: asker)
        try await runtime.run(steps: [Step(index: 0, verb: .read)])
        #expect(asker.askedRoles == ["url"])
        #expect(log.eventsOfType(ReadCompleted.self).count == 1)
    }

    @Test func execute_throwing_emitsStepFailedWithStepID() async throws {
        let log = EventLog()
        let url = URL(string: "https://example.com")!
        let http = FakeHTTPClient()
        http.scripted[url] = Data("<title>T</title><body>B</body>".utf8)
        let llm = FakeLLMSession()
        log.append(AtomRecorded(role: "url", value: .url(url), source: .detector, origin: .compile()))

        let runtime = Runtime(log: log, http: http, llm: llm, askResolver: AutoAcceptAskResolver())
        let summarizeStep = Step(index: 1, verb: .summarize)
        await #expect(throws: (any Error).self) {
            try await runtime.run(steps: [Step(index: 0, verb: .read), summarizeStep])
        }

        let failures = log.eventsOfType(StepFailed.self)
        #expect(failures.count == 1)
        #expect(failures.first?.stepID == summarizeStep.id)
    }

    @Test func forEach_whenSummarizeFollowsMultiPaperSearch() async throws {
        let log = EventLog()
        let papers = [
            Paper(title: "P1", abstract: "A1", identifier: "1", url: nil),
            Paper(title: "P2", abstract: "A2", identifier: "2", url: nil)
        ]
        log.append(SearchResults(papers: papers, target: "pubMed", origin: .step(id: UUID(), index: 0)))

        let llm = FakeLLMSession()
        llm.scriptedSummary = SummaryGenerable(summary: "s", claims: [], sentiment: "neutral")

        let runtime = Runtime(log: log, http: FakeHTTPClient(), llm: llm, askResolver: AutoAcceptAskResolver())
        try await runtime.run(steps: [Step(index: 1, verb: .summarize)])

        let summaries = log.eventsOfType(SummaryProduced.self)
        #expect(summaries.count == 2)
        #expect(summaries.map { $0.origin.iteration } == [0, 1])
    }
}

final class AutoAcceptAskResolver: AskResolver, @unchecked Sendable {
    func ask(role: String, kind: AtomKind) async -> AtomValue? { nil }
}

final class RecordingAskResolver: AskResolver, @unchecked Sendable {
    let responses: [String: AtomValue]
    var askedRoles: [String] = []
    init(responses: [String: AtomValue]) { self.responses = responses }
    func ask(role: String, kind: AtomKind) async -> AtomValue? {
        askedRoles.append(role)
        return responses[role]
    }
}
