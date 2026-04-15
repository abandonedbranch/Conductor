import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct AppendVerb: MemoryVerb {
    let graph: WorkingMemoryGraph
    /// The Action this agent is authorized to write to, if any. Supplied at construction time.
    let actionID: UUID?

    let name = "append"
    let verbName = "append"
    let description = "Append an atom to the caller's Action node or to the running outcome."

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: Set(IntentVerb.allCases),
            subjects: Set(IntentSubject.allCases),
            answerShapes: Set(AnswerShape.allCases),
            priority: 100
        )
    }

    @Generable
    struct Arguments {
        @Guide(description: "Where to append: action (this agent's node) or outcome (shared running result)")
        var slot: AppendSlot
        @Guide(description: "The atom's text body")
        var content: String
        @Guide(description: "Optional source URL for citations")
        var sourceURL: String?
        @Guide(description: "Tool or subsystem name producing this atom")
        var toolName: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let bounded = ProjectionBudget.bound(arguments.content, characterBudget: ProjectionBudget.atomContent)
        let source = arguments.sourceURL.flatMap(URL.init(string:))
        let atom = Atom.success(
            content: bounded,
            source: source,
            toolName: arguments.toolName ?? "unknown",
            timestamp: .now
        )
        let atomID = UUID()

        let receipt: AppendReceipt
        switch arguments.slot {
        case .action:
            guard let actionID else {
                receipt = .refused(reason: "No bound Action for this agent; slot .action is unavailable.")
                break
            }
            await graph.append(atom: atom, to: actionID)
            receipt = .accepted(atomID: atomID)
        case .outcome:
            await graph.appendOutcome(atom)
            receipt = .accepted(atomID: atomID)
        }

        let data = try JSONEncoder().encode(receipt)
        return String(data: data, encoding: .utf8) ?? "{\"error\":\"encode\"}"
    }
}
