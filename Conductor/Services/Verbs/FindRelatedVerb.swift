import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct FindRelatedVerb: MemoryVerb {
    let graph: WorkingMemoryGraph

    let name = "findRelated"
    let verbName = "findRelated"
    let description = "Search the running outcome and archived subjects for entries matching a keyword."

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: [.recall, .find],
            subjects: Set(IntentSubject.allCases),
            answerShapes: Set(AnswerShape.allCases),
            priority: 90
        )
    }

    @Generable
    struct Arguments {
        @Guide(description: "The keyword to search for, case-insensitive substring")
        var keyword: String
    }

    func call(arguments: Arguments) async throws -> String {
        let needle = arguments.keyword.lowercased()
        let outcome = await graph.currentOutcome()
        let archived = await graph.archivedSubjects()

        var hits: [AtomProjection] = []
        for atom in outcome {
            switch atom {
            case let .success(content, source, toolName, timestamp):
                if content.lowercased().contains(needle) {
                    hits.append(AtomProjection(actionID: nil, subjectID: nil, preview: content, source: source, toolName: toolName, timestamp: timestamp))
                }
            case let .note(text, timestamp):
                if text.lowercased().contains(needle) {
                    hits.append(AtomProjection(actionID: nil, subjectID: nil, preview: text, source: nil, toolName: nil, timestamp: timestamp))
                }
            case .error:
                continue
            }
        }
        for entry in archived where entry.name.lowercased().contains(needle) {
            hits.append(AtomProjection(actionID: nil, subjectID: entry.id, preview: entry.name, source: nil, toolName: nil, timestamp: entry.introducedAt))
        }

        let data = try JSONEncoder().encode(hits)
        let raw = String(data: data, encoding: .utf8) ?? "[]"
        return ProjectionBudget.bound(raw, characterBudget: ProjectionBudget.findRelatedResults)
    }
}
