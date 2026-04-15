import Foundation

@available(iOS 19.0, macOS 26.0, *)
@MainActor
@Observable
final class GraphProxy {
    private(set) var intent: LanguageIntentQuery?
    private(set) var subjects: [SubjectStack.Entry] = []
    private(set) var actions: [ActionNode] = []
    private(set) var outcome: [Atom] = []

    private let graph: WorkingMemoryGraph
    nonisolated(unsafe) private var subscribeTask: Task<Void, Never>?

    init(graph: WorkingMemoryGraph) {
        self.graph = graph
        self.subscribeTask = Task { [weak self] in
            guard let self else { return }
            // Prime
            await self.refreshAll()
            for await kind in graph.changes {
                if Task.isCancelled { return }
                switch kind {
                case .intent:  self.intent = await graph.currentIntent()
                case .subject: self.subjects = await graph.activeSubjects()
                case .actions: self.actions = await graph.allActions()
                case .outcome: self.outcome = await graph.currentOutcome()
                }
            }
        }
    }

    deinit { subscribeTask?.cancel() }

    private func refreshAll() async {
        self.intent = await graph.currentIntent()
        self.subjects = await graph.activeSubjects()
        self.actions = await graph.allActions()
        self.outcome = await graph.currentOutcome()
    }
}
