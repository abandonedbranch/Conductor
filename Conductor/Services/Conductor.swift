import Foundation

@available(iOS 19.0, macOS 26.0, *)
struct TurnResult: Sendable {
    let text: String
    let failureCount: Int
    let sources: [ToolSource]
}

@available(iOS 19.0, macOS 26.0, *)
@MainActor
@Observable
final class Conductor {
    let tools: [any AgentTool]
    private(set) var graph: WorkingMemoryGraph
    private(set) var proxy: GraphProxy

    private let intentRunner: any IntentSessionRunning
    private let agentRunner: any AgentRunning
    private let composeRunner: any ComposeResponseRunning

    private let toolDescriptors: [AffordanceDescriptor]
    private let verbDescriptors: [AffordanceDescriptor]
    private var pendingSnapshot: GraphSnapshot?

    init(
        tools: [any AgentTool],
        snapshot: GraphSnapshot? = nil,
        intentRunner: any IntentSessionRunning = LiveIntentRunner(),
        agentRunner: any AgentRunning = LiveAgentRunner(),
        composeRunner: any ComposeResponseRunning = LiveComposeRunner()
    ) {
        self.tools = tools
        let toolDescriptors = tools.map { AffordanceDescriptor(name: $0.friendlyName, affordance: $0.affordance) }
        let verbDescriptors = Self.verbDescriptors()
        self.toolDescriptors = toolDescriptors
        self.verbDescriptors = verbDescriptors

        // WorkingMemoryGraph.restore is async. To keep this init synchronous (Task 27
        // constructs the Conductor from a SwiftUI View init), start with a fresh graph
        // seeded only with subjects/turn, and defer intentStack/actions/outcome
        // rehydration to the first `handle(message:)` call.
        let initialSubjects = snapshot?.subjects ?? SubjectStack()
        let initialTurn = snapshot?.turn ?? 0
        let g = WorkingMemoryGraph(
            toolDescriptors: toolDescriptors,
            verbDescriptors: verbDescriptors,
            subjects: initialSubjects,
            turn: initialTurn
        )
        self.graph = g
        self.proxy = GraphProxy(graph: g)
        self.pendingSnapshot = snapshot
        self.intentRunner = intentRunner
        self.agentRunner = agentRunner
        self.composeRunner = composeRunner
    }

    private static func verbDescriptors() -> [AffordanceDescriptor] {
        let dummyGraph = WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: [])
        let verbs: [any MemoryVerb] = [
            GetContextVerb(graph: dummyGraph),
            GetActionsVerb(graph: dummyGraph),
            AppendVerb(graph: dummyGraph, actionID: nil),
            FindRelatedVerb(graph: dummyGraph),
        ]
        return verbs.map { AffordanceDescriptor(name: $0.verbName, affordance: $0.affordance) }
    }

    func handle(message: String) async throws -> TurnResult {
        // 0. Apply any pending snapshot rehydration. Replace graph+proxy with a fully
        //    restored graph the first time we run.
        if let snapshot = pendingSnapshot {
            pendingSnapshot = nil
            let restored = await WorkingMemoryGraph.restore(
                from: snapshot,
                toolDescriptors: toolDescriptors,
                verbDescriptors: verbDescriptors
            )
            graph = restored
            proxy = GraphProxy(graph: restored)
        }

        // 1. Intent
        let session = IntentSession(runner: intentRunner, graph: graph)
        try await session.handle(message: message)

        // 2. Dispatch until all Actions are terminal or awaitingUser
        try await dispatchLoop()

        // 3. Compose response
        let intent = await graph.currentIntent()!
        let actions = await graph.allActions()
        let failures = actions.filter { $0.status == .failed }.count
        let text = try await buildText(intent: intent, actions: actions)
        let sources = actions.flatMap { action in
            action.atoms.compactMap { atom -> ToolSource? in
                if case let .success(_, source, toolName, _) = atom, let source {
                    return ToolSource(title: toolName, url: source.absoluteString)
                }
                return nil
            }
        }
        return TurnResult(text: text, failureCount: failures, sources: sources)
    }

    func snapshot() async -> GraphSnapshot {
        await graph.snapshot()
    }

    // MARK: - Private

    private func dispatchLoop() async throws {
        while true {
            let actions = await graph.allActions()
            let ready = actions.filter { $0.status == .pending && $0.kind == .work }
            if ready.isEmpty { break }

            await withTaskGroup(of: Void.self) { [self] group in
                for action in ready {
                    group.addTask { await self.runAgent(for: action) }
                }
            }
        }
    }

    private func runAgent(for action: ActionNode) async {
        let verbInstances = resolveVerbs(names: action.assignedVerbNames, actionID: action.id)
        let toolInstances = tools.filter { action.assignedToolNames.contains($0.friendlyName) }
        let agent = Agent(
            actionID: action.id,
            goal: action.goal,
            verbs: verbInstances,
            tools: toolInstances,
            graph: graph,
            runner: agentRunner
        )
        await agent.run()
    }

    private func resolveVerbs(names: [String], actionID: UUID) -> [any MemoryVerb] {
        names.compactMap { name in
            switch name {
            case "getContext":  return GetContextVerb(graph: graph)
            case "getActions":  return GetActionsVerb(graph: graph)
            case "append":      return AppendVerb(graph: graph, actionID: actionID)
            case "findRelated": return FindRelatedVerb(graph: graph)
            default:            return nil
            }
        }
    }

    private func buildText(intent: LanguageIntentQuery, actions: [ActionNode]) async throws -> String {
        switch intent.answerShape {
        case .overview, .summary:
            let outcome = await graph.currentOutcome()
            let response = try await ComposeResponseSession(runner: composeRunner).compose(intent: intent, outcome: outcome)
            return response.prose
        case .citations, .workflow, .direct:
            return stitchDeterministic(actions: actions)
        }
    }

    private func stitchDeterministic(actions: [ActionNode]) -> String {
        let lines = actions.flatMap { action -> [String] in
            action.atoms.compactMap { atom in
                if case let .success(content, _, _, _) = atom { return content }
                return nil
            }
        }
        // Clarifications surface directly as the response.
        let clarifications = actions.filter { $0.kind == .clarification }.map(\.goal)
        if !clarifications.isEmpty { return clarifications.joined(separator: "\n\n") }
        return lines.joined(separator: "\n\n")
    }
}
