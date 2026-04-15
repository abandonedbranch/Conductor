import Foundation
import Testing
@testable import Conductor

@Suite("Agent")
struct AgentTests {
    @available(iOS 19.0, macOS 26.0, *)
    struct Stub: AgentRunning {
        let output: String
        let shouldThrow: Bool
        func run(goal: String, verbs: [any MemoryVerb], tools: [any AgentTool]) async throws -> String {
            if shouldThrow { throw NSError(domain: "test", code: 1) }
            return output
        }
    }

    @Test("Success completes the Action and appends a success atom")
    func success() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let pool = [
            AffordanceDescriptor(name: "Wiki", affordance: .init(
                verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview, .citations], priority: 1
            ))
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .citations, continuation: nil))
        let action = await graph.allActions().first!
        let agent = Agent(
            actionID: action.id, goal: "g",
            verbs: [], tools: [], graph: graph,
            runner: Stub(output: "found 3 papers", shouldThrow: false)
        )
        await agent.run()
        let refreshed = await graph.action(for: action.id)
        #expect(refreshed?.status == .completed)
        #expect(refreshed?.atoms.count == 1)
    }

    @Test("Runner failure marks Action .failed and appends an error atom")
    func failure() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let pool = [
            AffordanceDescriptor(name: "Wiki", affordance: .init(
                verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview, .citations], priority: 1
            ))
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .citations, continuation: nil))
        let action = await graph.allActions().first!
        let agent = Agent(
            actionID: action.id, goal: "g",
            verbs: [], tools: [], graph: graph,
            runner: Stub(output: "", shouldThrow: true)
        )
        await agent.run()
        let refreshed = await graph.action(for: action.id)
        #expect(refreshed?.status == .failed)
        #expect(refreshed?.atoms.count == 1)
        if case .error = refreshed!.atoms[0] { #expect(true) } else { Issue.record("expected error atom") }
    }
}
