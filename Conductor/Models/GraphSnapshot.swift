@available(iOS 19.0, macOS 26.0, *)
struct GraphSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let intentStack: [LanguageIntentQuery]
    let subjects: SubjectStack
    let actions: [ActionNode]
    let outcome: [Atom]
    let turn: Int

    init(
        schemaVersion: Int = GraphSnapshot.currentSchemaVersion,
        intentStack: [LanguageIntentQuery],
        subjects: SubjectStack,
        actions: [ActionNode],
        outcome: [Atom],
        turn: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.intentStack = intentStack
        self.subjects = subjects
        self.actions = actions
        self.outcome = outcome
        self.turn = turn
    }
}
