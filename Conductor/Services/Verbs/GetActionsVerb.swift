import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct GetActionsVerb: MemoryVerb {
    let graph: WorkingMemoryGraph

    let name = "getActions"
    let verbName = "getActions"
    let description = "List action nodes in the working memory graph, optionally filtered by status."

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: [.recall, .summarize],
            subjects: Set(IntentSubject.allCases),
            answerShapes: Set(AnswerShape.allCases),
            priority: 80
        )
    }

    @Generable
    struct Arguments {
        @Guide(description: "Filter by action status (pending, running, completed, failed, awaitingUser). If omitted, all actions are returned.")
        var status: ActionStatusArg?
    }

    @Generable
    enum ActionStatusArg: String, Codable {
        case pending, running, completed, failed, awaitingUser
        var asStatus: ActionStatus {
            switch self {
            case .pending: return .pending
            case .running: return .running
            case .completed: return .completed
            case .failed: return .failed
            case .awaitingUser: return .awaitingUser
            }
        }
    }

    func call(arguments: Arguments) async throws -> String {
        let all = await graph.allActions()
        let filtered = arguments.status.map { arg in all.filter { $0.status == arg.asStatus } } ?? all
        let projections = filtered.map {
            ActionProjection(id: $0.id, kind: $0.kind, goal: $0.goal, status: $0.status, atomCount: $0.atoms.count)
        }
        let data = try JSONEncoder().encode(projections)
        let raw = String(data: data, encoding: .utf8) ?? "[]"
        return ProjectionBudget.bound(raw, characterBudget: ProjectionBudget.actionsProjection, remainingHint: max(0, projections.count - 10))
    }
}
