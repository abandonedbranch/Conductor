import Testing
import Foundation
@testable import Conductor

@Suite struct FakeSmokeTests {
    @Test func fakeHTTP_returnsScriptedData() async throws {
        let c = FakeHTTPClient()
        let u = URL(string: "https://x")!
        c.scripted[u] = Data("hello".utf8)
        let d = try await c.get(u)
        #expect(String(data: d, encoding: .utf8) == "hello")
    }

    @Test func fakeLLM_returnsScriptedIntent() async throws {
        let l = FakeLLMSession()
        l.scriptedIntent = PipelineIntent(verbs: [.read, .summarize])
        let i = try await l.inferPipeline(from: "anything")
        #expect(i.verbs == [.read, .summarize])
    }
}
