import Foundation

enum ActionKind: String, Codable, Sendable { case work, clarification }

enum ActionStatus: String, Codable, Sendable {
    case pending, running, completed, failed, awaitingUser

    var isTerminal: Bool {
        self == .completed || self == .failed
    }
}

@available(iOS 19.0, macOS 26.0, *)
struct ActionNode: Identifiable, Codable, Sendable {
    let id: UUID
    let kind: ActionKind
    let goal: String
    let verbs: [IntentVerb]
    let subjects: [IntentSubject]
    let answerShape: AnswerShape
    let assignedVerbNames: [String]
    let assignedToolNames: [String]
    var status: ActionStatus
    var atoms: [Atom]
    let dependsOn: Set<UUID>
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: ActionKind,
        goal: String,
        verbs: [IntentVerb],
        subjects: [IntentSubject],
        answerShape: AnswerShape,
        assignedVerbNames: [String],
        assignedToolNames: [String],
        status: ActionStatus = .pending,
        atoms: [Atom] = [],
        dependsOn: Set<UUID>,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.goal = goal
        self.verbs = verbs
        self.subjects = subjects
        self.answerShape = answerShape
        self.assignedVerbNames = assignedVerbNames
        self.assignedToolNames = assignedToolNames
        self.status = status
        self.atoms = atoms
        self.dependsOn = dependsOn
        self.createdAt = createdAt
    }
}
