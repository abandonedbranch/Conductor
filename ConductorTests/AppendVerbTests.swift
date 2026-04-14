import Testing
@testable import Conductor

@Suite("AppendVerb")
struct AppendVerbTests {
    @Test("Writes to an action's atoms when slot is .action")
    func actionAppend() async throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let pool = [
            AffordanceDescriptor(name: "Wiki", affordance: .init(
                verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview, .citations], priority: 1
            ))
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["a"], answerShape: .citations, continuation: nil))
        let actionID = await graph.allActions().first!.id
        let verb = AppendVerb(graph: graph, actionID: actionID)
        _ = try await verb.call(arguments: .init(slot: .action, content: "found 3 papers", sourceURL: nil, toolName: "PubMed"))
        let stored = await graph.action(for: actionID)?.atoms.count ?? 0
        #expect(stored == 1)
    }

    @Test("Writing with no bound actionID to slot .action is refused")
    func refusesUnbound() async throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let pool = [
            AffordanceDescriptor(name: "Wiki", affordance: .init(
                verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview, .citations], priority: 1
            ))
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        let verb = AppendVerb(graph: graph, actionID: nil)
        let receipt = try await verb.call(arguments: .init(slot: .action, content: "x", sourceURL: nil, toolName: nil))
        #expect(receipt.contains("refused"))
    }
}
