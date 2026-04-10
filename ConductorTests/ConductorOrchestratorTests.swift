import Foundation
import Testing
@testable import Conductor

@Suite("ConductorOrchestrator Tests", .serialized)
struct ConductorOrchestratorTests {

    @Test("buildGraph creates nodes grouped by purpose with correct tool count")
    func buildGraphGroupsByPurpose() async {
        let toolbox: [any AgentTool] = [
            WikipediaSearchTool(),
            PubMedSearchTool(),
            ArXivSearchTool(),
            SemanticScholarSearchTool(),
        ]
        let orchestrator = ConductorOrchestrator(toolbox: toolbox)

        let intent = ExtractedIntent(purposes: [
            PurposeTask(purpose: "overview", goal: "understand topic",
                        completionCriteria: "until summarized", dependsOn: []),
            PurposeTask(purpose: "research", goal: "find papers",
                        completionCriteria: "until 3 sources found", dependsOn: [0]),
        ])

        let graph = await orchestrator.buildGraph(from: intent)
        let nodes = await graph.allNodes

        // overview has 1 tool (Wikipedia) → 1 node
        let overviewNodes = nodes.filter { $0.purpose == .overview }
        #expect(overviewNodes.count == 1)
        #expect(overviewNodes[0].toolNames.count == 1)

        // research has 3 tools → 2 nodes (chunks of 2: [PubMed, arXiv], [SemanticScholar])
        let researchNodes = nodes.filter { $0.purpose == .research }
        #expect(researchNodes.count == 2)
    }

    @Test("buildGraph sets correct dependencies across chunked nodes")
    func buildGraphDependencies() async {
        let toolbox: [any AgentTool] = [
            WikipediaSearchTool(),
            PubMedSearchTool(),
            ArXivSearchTool(),
        ]
        let orchestrator = ConductorOrchestrator(toolbox: toolbox)

        let intent = ExtractedIntent(purposes: [
            PurposeTask(purpose: "overview", goal: "overview",
                        completionCriteria: "done", dependsOn: []),
            PurposeTask(purpose: "research", goal: "research",
                        completionCriteria: "done", dependsOn: [0]),
        ])

        let graph = await orchestrator.buildGraph(from: intent)
        let nodes = await graph.allNodes
        let overviewNode = nodes.first { $0.purpose == .overview }!
        let researchNodes = nodes.filter { $0.purpose == .research }

        for researchNode in researchNodes {
            #expect(researchNode.dependsOn.contains(overviewNode.id))
        }
    }

    @Test("buildGraph with no matching tools creates no nodes for that purpose")
    func buildGraphNoMatchingTools() async {
        let toolbox: [any AgentTool] = [WikipediaSearchTool()]
        let orchestrator = ConductorOrchestrator(toolbox: toolbox)

        let intent = ExtractedIntent(purposes: [
            PurposeTask(purpose: "build", goal: "build something",
                        completionCriteria: "done", dependsOn: []),
        ])

        let graph = await orchestrator.buildGraph(from: intent)
        let count = await graph.nodeCount
        #expect(count == 0)
    }
}
