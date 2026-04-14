import Foundation
import Testing
@testable import Conductor

@Suite("Conductor shell")
struct ConductorShellTests {
    @available(iOS 19.0, macOS 26.0, *)
    struct IntentStub: IntentSessionRunning {
        let out: LanguageIntentQuery
        func extract(message: String, contextVerb: GetContextVerb?) async throws -> LanguageIntentQuery { out }
    }

    @available(iOS 19.0, macOS 26.0, *)
    struct AgentStub: AgentRunning {
        let body: String
        func run(goal: String, verbs: [any MemoryVerb], tools: [any AgentTool]) async throws -> String { body }
    }

    @available(iOS 19.0, macOS 26.0, *)
    struct ComposeStub: ComposeResponseRunning {
        func compose(intent: LanguageIntentQuery, ragBlock: String) async throws -> ComposedResponse {
            ComposedResponse(prose: "composed from \(ragBlock.prefix(20))", sections: nil)
        }
    }

    @Test("Deterministic answer shape produces a stitched response")
    func deterministicShape() async throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let conductor = await Conductor(
            tools: [WikipediaSearchTool(), ArXivSearchTool()],
            intentRunner: IntentStub(out: LanguageIntentQuery(
                verbs: [.find], subjects: ["crispr"],
                answerShape: .citations, continuation: nil
            )),
            agentRunner: AgentStub(body: "found: crispr paper"),
            composeRunner: ComposeStub()
        )
        let result = try await conductor.handle(message: "find crispr papers")
        #expect(result.text.contains("crispr paper"))
        #expect(result.failureCount == 0)
    }

    @Test("Overview answer shape routes through synthesis")
    func synthesisShape() async throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let conductor = await Conductor(
            tools: [WikipediaSearchTool(), ArXivSearchTool()],
            intentRunner: IntentStub(out: LanguageIntentQuery(
                verbs: [.find, .summarize], subjects: ["crispr"],
                answerShape: .overview, continuation: nil
            )),
            agentRunner: AgentStub(body: "edits DNA"),
            composeRunner: ComposeStub()
        )
        let result = try await conductor.handle(message: "overview of crispr")
        #expect(result.text.starts(with: "composed"))
    }
}
