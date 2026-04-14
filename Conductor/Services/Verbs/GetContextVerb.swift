import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct GetContextVerb: MemoryVerb {
    let graph: WorkingMemoryGraph

    let name = "getContext"
    let verbName = "getContext"
    let description = "Return the current user intent and the active subjects under discussion."

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: [.recall, .summarize, .find, .read, .build],
            subjects: Set(IntentSubject.allCases),
            answerShapes: Set(AnswerShape.allCases),
            priority: 100
        )
    }

    @Generable
    struct Arguments { }

    func call(arguments: Arguments) async throws -> String {
        let intent = await graph.currentIntent()
        let active = await graph.activeSubjects()
        let projection = ContextProjection(intent: intent, activeSubjects: active)
        let data = try JSONEncoder().encode(projection)
        let raw = String(data: data, encoding: .utf8) ?? "{}"
        return ProjectionBudget.bound(raw, characterBudget: ProjectionBudget.contextProjection)
    }
}
