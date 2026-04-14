import Testing
@testable import Conductor

@Suite("GetActionsVerb")
struct GetActionsVerbTests {
    @Test("Filter by status returns matching actions only")
    func filters() async throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let pool = [
            AffordanceDescriptor(name: "Wiki", affordance: .init(
                verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview, .citations], priority: 1
            ))
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["a"], answerShape: .citations, continuation: nil))
        let verb = GetActionsVerb(graph: graph)
        let all = try await verb.call(arguments: .init(status: nil))
        let pending = try await verb.call(arguments: .init(status: .pending))
        #expect(all.contains("pending"))
        #expect(pending.contains("pending"))
    }

    @Test("Affordance maps to .recall")
    func aff() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let verb = GetActionsVerb(graph: WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: []))
        #expect(verb.affordance.verbs.contains(.recall))
    }
}
