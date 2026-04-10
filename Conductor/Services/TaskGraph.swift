import Foundation

actor TaskGraph {

    struct TaskNode: Sendable {
        let id: UUID
        let purpose: AgentPurpose
        let goal: String
        let completionCriteria: String
        let toolNames: [String]
        let dependsOn: Set<UUID>

        var entries: [LogEntry] = []
        var status: TaskStatus = .pending
    }

    enum TaskStatus: Sendable {
        case pending, running, completed, failed

        var isTerminal: Bool {
            self == .completed || self == .failed
        }
    }

    private var nodes: [UUID: TaskNode] = [:]
    private var narrationContinuation: AsyncStream<NarrationEvent>.Continuation?
    private var _narrationStream: AsyncStream<NarrationEvent>?

    var narrationStream: AsyncStream<NarrationEvent> {
        if let existing = _narrationStream { return existing }
        let stream = AsyncStream<NarrationEvent> { continuation in
            self.narrationContinuation = continuation
        }
        _narrationStream = stream
        return stream
    }

    func addNode(_ node: TaskNode) {
        nodes[node.id] = node
    }

    func updateStatus(_ id: UUID, to status: TaskStatus) {
        nodes[id]?.status = status
    }

    func append(_ entry: LogEntry, to taskID: UUID) {
        nodes[taskID]?.entries.append(entry)
    }

    func entries(for taskID: UUID) -> [LogEntry] {
        nodes[taskID]?.entries ?? []
    }

    func upstreamResults(for taskID: UUID) -> [LogEntry] {
        guard let node = nodes[taskID] else { return [] }
        return node.dependsOn.flatMap { nodes[$0]?.entries ?? [] }
    }

    func readyToDispatch() -> [TaskNode] {
        nodes.values.filter { node in
            node.status == .pending &&
            node.dependsOn.allSatisfy { nodes[$0]?.status.isTerminal == true }
        }
    }

    var isFullyResolved: Bool {
        !nodes.isEmpty && nodes.values.allSatisfy(\.status.isTerminal)
    }

    func narrate(_ taskID: UUID, _ message: String) {
        guard let node = nodes[taskID] else { return }
        let event = NarrationEvent(taskID: taskID, purpose: node.purpose, message: message)
        narrationContinuation?.yield(event)
    }

    func finishNarration() {
        narrationContinuation?.finish()
    }

    func topologicalSort() -> [TaskNode] {
        var sorted: [TaskNode] = []
        var visited = Set<UUID>()

        func visit(_ id: UUID) {
            guard !visited.contains(id), let node = nodes[id] else { return }
            visited.insert(id)
            for dep in node.dependsOn {
                visit(dep)
            }
            sorted.append(node)
        }

        for id in nodes.keys {
            visit(id)
        }
        return sorted
    }

    var allNodes: [TaskNode] {
        Array(nodes.values)
    }

    var nodeCount: Int {
        nodes.count
    }

    func node(for id: UUID) -> TaskNode? {
        nodes[id]
    }
}
