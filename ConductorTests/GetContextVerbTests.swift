import Testing
@testable import Conductor

@Suite("GetContextVerb")
struct GetContextVerbTests {
    @Test("Returns empty context when graph is untouched")
    func empty() async throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let graph = WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: [])
        let verb = GetContextVerb(graph: graph)
        let result = try await verb.call(arguments: .init())
        #expect(result.contains("intent"))
    }

    @Test("Includes the current intent's verbs in the projection")
    func projectsIntent() async throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let graph = WorkingMemoryGraph(toolDescriptors: [
            AffordanceDescriptor(name: "Wiki", affordance: .init(verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview], priority: 1))
        ], verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["alpha"], answerShape: .overview, continuation: nil))
        let verb = GetContextVerb(graph: graph)
        let result = try await verb.call(arguments: .init())
        #expect(result.contains("find"))
        #expect(result.contains("alpha"))
    }

    @Test("Declares the expected affordance")
    func affordance() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let verb = GetContextVerb(graph: WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: []))
        #expect(verb.affordance.verbs.contains(.recall))
        #expect(verb.verbName == "getContext")
    }
}
