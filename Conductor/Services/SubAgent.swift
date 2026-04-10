import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
actor SubAgent {
    let task: TaskGraph.TaskNode
    let graph: TaskGraph
    let tools: [any AgentTool]
    private let session: LanguageModelSession

    init(task: TaskGraph.TaskNode, tools: [any AgentTool], graph: TaskGraph) {
        self.task = task
        self.tools = tools
        self.graph = graph
        self.session = LanguageModelSession(
            tools: tools,
            instructions: """
            You are \(task.purpose.agentDescription).
            Your goal: \(task.goal)
            You have these tools: \(task.toolNames.joined(separator: ", "))
            Keep working until: \(task.completionCriteria)
            """
        )
    }

    func run() async {
        await graph.updateStatus(task.id, to: .running)
        await graph.narrate(
            task.id,
            "\(task.purpose.narrationPrefix) (\(task.toolNames.joined(separator: ", ")))"
        )

        let upstream = await graph.upstreamResults(for: task.id)
        let prompt = buildPrompt(upstream: upstream)

        do {
            var content = ""
            let stream = session.streamResponse(to: prompt)
            for try await partial in stream {
                content = partial.content
            }

            if !content.isEmpty {
                let entry = LogEntry(
                    id: UUID(),
                    taskID: task.id,
                    purpose: task.purpose,
                    toolName: task.toolNames.joined(separator: ", "),
                    content: content,
                    sourceURL: nil,
                    timestamp: .now
                )
                await graph.append(entry, to: task.id)
            }
            await graph.updateStatus(task.id, to: .completed)
            await graph.narrate(task.id, "Completed.")
        } catch {
            let errorEntry = LogEntry(
                id: UUID(),
                taskID: task.id,
                purpose: task.purpose,
                toolName: "error",
                content: error.localizedDescription,
                sourceURL: nil,
                timestamp: .now
            )
            await graph.append(errorEntry, to: task.id)
            await graph.updateStatus(task.id, to: .failed)
            await graph.narrate(task.id, "Failed: \(error.localizedDescription)")
        }
    }

    private func buildPrompt(upstream: [LogEntry]) -> String {
        if upstream.isEmpty { return task.goal }
        let context = upstream
            .map { "[\($0.purpose.rawValue)] \($0.content)" }
            .joined(separator: "\n---\n")
        return """
        Context from prior work:
        \(context)

        Your task: \(task.goal)
        """
    }
}
