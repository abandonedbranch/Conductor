import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
protocol AgentRunning: Sendable {
    func run(goal: String, verbs: [any MemoryVerb], tools: [any AgentTool]) async throws -> String
}

@available(iOS 19.0, macOS 26.0, *)
actor Agent {
    let actionID: UUID
    let goal: String
    let verbs: [any MemoryVerb]
    let tools: [any AgentTool]
    let graph: WorkingMemoryGraph
    let runner: any AgentRunning

    init(
        actionID: UUID,
        goal: String,
        verbs: [any MemoryVerb],
        tools: [any AgentTool],
        graph: WorkingMemoryGraph,
        runner: any AgentRunning
    ) {
        self.actionID = actionID
        self.goal = goal
        self.verbs = verbs
        self.tools = tools
        self.graph = graph
        self.runner = runner
    }

    func run() async {
        await graph.updateStatus(.running, for: actionID)
        do {
            let content = try await runner.run(goal: goal, verbs: verbs, tools: tools)
            let bounded = ProjectionBudget.bound(content, characterBudget: ProjectionBudget.atomContent)
            let atom = Atom.success(content: bounded, source: nil, toolName: tools.first?.friendlyName ?? "agent", timestamp: .now)
            await graph.append(atom: atom, to: actionID)
            await graph.updateStatus(.completed, for: actionID)
        } catch {
            let err = ErrorAtom(
                actionID: actionID,
                toolName: nil,
                kind: classify(error),
                message: error.localizedDescription,
                timestamp: .now
            )
            await graph.append(atom: .error(err), to: actionID)
            await graph.updateStatus(.failed, for: actionID)
        }
    }

    private func classify(_ error: Error) -> ErrorKind {
        let s = String(describing: error).lowercased()
        if s.contains("unsafe") { return .unsafeContent }
        if s.contains("timeout") || s.contains("timed out") { return .timeout }
        if s.contains("no results") { return .noResults }
        if s.contains("network") || s.contains("internet") { return .networkError }
        return .unknown
    }
}

@available(iOS 19.0, macOS 26.0, *)
struct LiveAgentRunner: AgentRunning {
    func run(goal: String, verbs: [any MemoryVerb], tools: [any AgentTool]) async throws -> String {
        let allTools: [any Tool] = (verbs as [any Tool]) + (tools as [any Tool])
        let session = LanguageModelSession(
            tools: allTools,
            instructions: """
            Your goal: \(goal)
            You have memory verbs for reading the graph and appending results, and domain tools for calling external sources.
            Read only what you need, call tools, and append a concise atom when done.
            """
        )
        var content = ""
        for try await partial in session.streamResponse(to: goal) {
            content = partial.content
        }
        return content
    }
}
