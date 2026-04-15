import Testing
@testable import Conductor

@Suite("IntentSession")
struct IntentSessionTests {
    @available(iOS 19.0, macOS 26.0, *)
    struct Stub: IntentSessionRunning {
        let output: LanguageIntentQuery
        func extract(message: String, contextVerb: GetContextVerb?) async throws -> LanguageIntentQuery { output }
    }

    @Test("parseIntent uses the stub runner and appends to the graph")
    func parseIntent() async throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let graph = WorkingMemoryGraph(toolDescriptors: [
            AffordanceDescriptor(name: "Wiki", affordance: .init(verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview], priority: 1))
        ], verbDescriptors: [])
        let stub = Stub(output: LanguageIntentQuery(verbs: [.find], subjects: ["crispr"], answerShape: .overview, continuation: nil))
        let session = IntentSession(runner: stub, graph: graph)
        try await session.handle(message: "tell me about crispr")
        let intent = await graph.currentIntent()
        #expect(intent?.verbs == [.find])
        #expect(intent?.subjects == ["crispr"])
    }
}
