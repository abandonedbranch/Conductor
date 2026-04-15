@available(iOS 19.0, macOS 26.0, *)
enum ClarificationTemplate {
    static func render(
        intent: LanguageIntentQuery,
        toolbox: [AffordanceDescriptor]
    ) -> String {
        let verbs = intent.verbs.map(\.rawValue).joined(separator: ", ")
        let subjects = intent.subjects.joined(separator: ", ")
        let hint = availableHint(from: toolbox)
        var lines: [String] = []
        lines.append("I couldn't match that to any available tools.")
        lines.append("You asked for: \(verbs.isEmpty ? "(no verbs)" : verbs) on \(subjects.isEmpty ? "(no subjects)" : subjects).")
        if !hint.isEmpty {
            lines.append("I can help with: \(hint).")
        }
        lines.append("Could you rephrase, or point me at a specific source?")
        return lines.joined(separator: "\n")
    }

    private static func availableHint(from toolbox: [AffordanceDescriptor]) -> String {
        let subjects = Set(toolbox.flatMap { $0.affordance.subjects }).map(\.rawValue).sorted()
        let shapes = Set(toolbox.flatMap { $0.affordance.answerShapes }).map(\.rawValue).sorted()
        let parts = [subjects, shapes].filter { !$0.isEmpty }.map { $0.joined(separator: ", ") }
        return parts.joined(separator: "; ")
    }
}
