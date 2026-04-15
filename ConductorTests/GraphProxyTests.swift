import Foundation
import Testing
@testable import Conductor

@Suite("GraphProxy")
@MainActor
struct GraphProxyTests {
    @Test("Proxy reflects the graph's current intent after an append")
    func reflectsIntent() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let graph = WorkingMemoryGraph(toolDescriptors: [
            AffordanceDescriptor(name: "Wiki", affordance: .init(verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview], priority: 1))
        ], verbDescriptors: [])
        let proxy = GraphProxy(graph: graph)
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .overview, continuation: nil))
        // Let the subscription drain
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(proxy.intent?.verbs == [.find])
    }
}
