import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Observable
final class ConductorOrchestrator {
    let toolbox: [any AgentTool]
    private(set) var activeGraph: TaskGraph?

    private static let instructions = """
    Extract the user's intent as a structured plan.
    Identify what purposes are needed and how they depend on each other.
    Available purposes: overview (background context via Wikipedia), research (academic papers), web (read a specific URL), build (create Automator workflow).
    Do not perform any tasks yourself. Only produce the plan.
    """

    init(toolbox: [any AgentTool]) {
        self.toolbox = toolbox
    }

    func handle(userMessage: String) async throws -> StitchedResponse {
        let intentSession = LanguageModelSession(
            tools: [IntentExtractionTool()],
            instructions: Self.instructions
        )

        let response = try await intentSession.respond(
            to: userMessage,
            generating: ExtractedIntent.self
        )

        let graph = await buildGraph(from: response.content)
        activeGraph = graph

        await execute(graph)

        let stitched = await graph.stitch()
        await graph.finishNarration()
        return stitched
    }

    func buildGraph(from intent: ExtractedIntent) async -> TaskGraph {
        let graph = TaskGraph()
        var idMap: [Int: [UUID]] = [:]

        for (index, purposeTask) in intent.purposes.enumerated() {
            guard let purpose = AgentPurpose(rawValue: purposeTask.purpose) else { continue }
            let tools = toolbox.filter { $0.purpose == purpose }
            guard !tools.isEmpty else { continue }

            let chunks = tools.chunked(into: 2)
            var nodeIDs: [UUID] = []
            let dependencies = Set(purposeTask.dependsOn.flatMap { idMap[$0] ?? [] })

            for chunk in chunks {
                let id = UUID()
                nodeIDs.append(id)
                let node = TaskGraph.TaskNode(
                    id: id,
                    purpose: purpose,
                    goal: purposeTask.goal,
                    completionCriteria: purposeTask.completionCriteria,
                    toolNames: chunk.map(\.friendlyName),
                    dependsOn: dependencies
                )
                await graph.addNode(node)
            }
            idMap[index] = nodeIDs
        }
        return graph
    }

    private func execute(_ graph: TaskGraph) async {
        while await !graph.isFullyResolved {
            let ready = await graph.readyToDispatch()
            guard !ready.isEmpty else { break }

            await withTaskGroup(of: Void.self) { group in
                for node in ready {
                    let tools = toolbox.filter { $0.purpose == node.purpose }
                    let nodeTools = tools.filter { node.toolNames.contains($0.friendlyName) }
                    group.addTask {
                        let agent = SubAgent(task: node, tools: nodeTools, graph: graph)
                        await agent.run()
                    }
                }
            }
        }
    }
}

// MARK: - IntentExtractionTool

@available(iOS 19.0, macOS 26.0, *)
struct IntentExtractionTool: Tool {
    let name = "extractIntent"
    let description = "Break down the user's message into a structured plan of purpose-tagged tasks with dependencies."

    @Generable
    struct Arguments {
        @Guide(description: "The user's original message to decompose")
        var userMessage: String
    }

    func call(arguments: Arguments) async throws -> String {
        return arguments.userMessage
    }
}

// MARK: - Array Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
