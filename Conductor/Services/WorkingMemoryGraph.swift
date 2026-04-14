import Foundation

enum ChangeKind: Sendable { case intent, actions, subject, outcome }

@available(iOS 19.0, macOS 26.0, *)
actor WorkingMemoryGraph {
    private var intentStack: [LanguageIntentQuery] = []
    private var actions: [UUID: ActionNode] = [:]
    private var subjects: SubjectStack
    private var outcome: [Atom] = []
    private var turn: Int = 0

    let toolDescriptors: [AffordanceDescriptor]
    let verbDescriptors: [AffordanceDescriptor]

    nonisolated let changes: AsyncStream<ChangeKind>
    private let changesContinuation: AsyncStream<ChangeKind>.Continuation

    init(
        toolDescriptors: [AffordanceDescriptor],
        verbDescriptors: [AffordanceDescriptor],
        subjects: SubjectStack = SubjectStack(),
        turn: Int = 0
    ) {
        self.toolDescriptors = toolDescriptors
        self.verbDescriptors = verbDescriptors
        self.subjects = subjects
        self.turn = turn
        var continuation: AsyncStream<ChangeKind>.Continuation!
        self.changes = AsyncStream { continuation = $0 }
        self.changesContinuation = continuation
    }

    // MARK: - Writes

    func append(intent: LanguageIntentQuery) {
        intentStack.insert(intent, at: 0)
        turn += 1
        rebuildActionNodes(for: intent)
        updateSubjectStack(for: intent)
        changesContinuation.yield(.intent)
    }

    // MARK: - Observers

    private func rebuildActionNodes(for intent: LanguageIntentQuery) {
        // 1. Any prior awaitingUser clarifications are now answered.
        for (id, node) in actions where node.status == .awaitingUser && node.kind == .clarification {
            actions[id]?.status = .completed
        }
        changesContinuation.yield(.actions)

        // 2. Decide intent subjects to filter on (best-effort map from strings to enum).
        let intentSubjects = intent.subjects.compactMap(IntentSubject.init(rawValue:))

        // 3. Search toolbox.
        let toolMatches = deterministicSearch(
            intent: intent, intentSubjects: intentSubjects,
            pool: toolDescriptors, cap: 4
        )
        let verbMatches = deterministicSearch(
            intent: intent, intentSubjects: intentSubjects,
            pool: verbDescriptors, cap: 4
        )

        // 4. If the toolbox doesn't match, write a clarification and stop.
        guard !toolMatches.isEmpty else {
            let clarification = ActionNode(
                kind: .clarification,
                goal: ClarificationTemplate.render(intent: intent, toolbox: toolDescriptors),
                verbs: intent.verbs,
                subjects: intentSubjects,
                answerShape: intent.answerShape,
                assignedVerbNames: [],
                assignedToolNames: [],
                status: .awaitingUser,
                dependsOn: []
            )
            actions[clarification.id] = clarification
            changesContinuation.yield(.actions)
            return
        }

        // 5. One work Action per intent (v1).
        let work = ActionNode(
            kind: .work,
            goal: intent.subjects.joined(separator: ", "),
            verbs: intent.verbs,
            subjects: intentSubjects,
            answerShape: intent.answerShape,
            assignedVerbNames: verbMatches.map(\.name),
            assignedToolNames: toolMatches.map(\.name),
            status: .pending,
            dependsOn: []
        )
        actions[work.id] = work
        changesContinuation.yield(.actions)
    }

    private func updateSubjectStack(for intent: LanguageIntentQuery) {
        let currentTurn = turn
        switch intent.continuation {
        case .none, .refines:
            for name in intent.subjects {
                if let match = subjects.active.first(where: { $0.name == name }) {
                    subjects.touch(id: match.id, turn: currentTurn)
                } else {
                    subjects.push(name: name, turn: currentTurn, relatesTo: nil)
                }
            }
        case .extends:
            for name in intent.subjects where !subjects.active.contains(where: { $0.name == name }) {
                subjects.push(name: name, turn: currentTurn, relatesTo: nil)
            }
        case .pivots:
            subjects.archiveAll()
            for name in intent.subjects {
                subjects.push(name: name, turn: currentTurn, relatesTo: nil)
            }
        case .recalls:
            break
        }
        changesContinuation.yield(.subject)
    }

    func insertAction(_ node: ActionNode) {
        actions[node.id] = node
        changesContinuation.yield(.actions)
    }

    func updateStatus(_ status: ActionStatus, for actionID: UUID) {
        actions[actionID]?.status = status
        changesContinuation.yield(.actions)
    }

    func append(atom: Atom, to actionID: UUID) {
        actions[actionID]?.atoms.append(atom)
        outcome.append(atom)
        changesContinuation.yield(.actions)
        changesContinuation.yield(.outcome)
    }

    func appendOutcome(_ atom: Atom) {
        outcome.append(atom)
        changesContinuation.yield(.outcome)
    }

    // MARK: - Reads (Sendable projections)

    func currentIntent() -> LanguageIntentQuery? { intentStack.first }

    func intentStackCopy() -> [LanguageIntentQuery] { intentStack }

    func activeSubjects() -> [SubjectStack.Entry] { subjects.active }

    func archivedSubjects() -> [SubjectStack.Entry] { subjects.archived }

    func allActions() -> [ActionNode] { Array(actions.values).sorted { $0.createdAt < $1.createdAt } }

    func action(for id: UUID) -> ActionNode? { actions[id] }

    func currentOutcome() -> [Atom] { outcome }

    func currentTurn() -> Int { turn }

    // MARK: - Persistence

    func snapshot() -> GraphSnapshot {
        GraphSnapshot(
            intentStack: intentStack,
            subjects: subjects,
            actions: allActions(),
            outcome: outcome,
            turn: turn
        )
    }

    static func restore(
        from snapshot: GraphSnapshot,
        toolDescriptors: [AffordanceDescriptor],
        verbDescriptors: [AffordanceDescriptor]
    ) async -> WorkingMemoryGraph {
        let graph = WorkingMemoryGraph(
            toolDescriptors: toolDescriptors,
            verbDescriptors: verbDescriptors,
            subjects: snapshot.subjects,
            turn: snapshot.turn
        )
        await graph.rehydrate(intentStack: snapshot.intentStack, actions: snapshot.actions, outcome: snapshot.outcome)
        return graph
    }

    private func rehydrate(intentStack: [LanguageIntentQuery], actions: [ActionNode], outcome: [Atom]) {
        self.intentStack = intentStack
        self.actions = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        self.outcome = outcome
    }

    // MARK: - Scoped mutations for observers (same-actor privileged access)

    func updateSubjects(_ transform: (inout SubjectStack) -> Void) {
        transform(&subjects)
        changesContinuation.yield(.subject)
    }
}
