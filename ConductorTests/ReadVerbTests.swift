import Testing
import Foundation
@testable import Conductor

@Suite struct ReadVerbTests {
    @Test func fetches_andEmitsReadCompleted() async throws {
        let http = FakeHTTPClient()
        let url = URL(string: "https://example.com")!
        http.scripted[url] = Data("<html><title>T</title><body>B</body></html>".utf8)
        let llm = FakeLLMSession()
        let inputs = ResolvedInputs(atoms: ["url": .url(url)], upstream: [])
        let events = try await ReadVerb.execute(
            resolved: inputs,
            origin: .step(id: UUID(), index: 0),
            http: http,
            llm: llm
        )
        let read = events.compactMap { $0 as? ReadCompleted }
        #expect(read.count == 1)
        #expect(read.first?.url == url)
        #expect(read.first?.title.contains("T") == true)
    }

    @Test func failure_emitsStepFailed() async throws {
        let http = FakeHTTPClient()
        let llm = FakeLLMSession()
        let inputs = ResolvedInputs(atoms: ["url": .url(URL(string: "https://x")!)], upstream: [])
        let stepID = UUID()
        let events = try await ReadVerb.execute(resolved: inputs, origin: .step(id: stepID, index: 0), http: http, llm: llm)
        let fails = events.compactMap { $0 as? StepFailed }
        #expect(fails.first?.stepID == stepID)
    }
}
