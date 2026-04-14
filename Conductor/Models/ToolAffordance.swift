import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct ToolAffordance: Sendable, Hashable {
    let verbs: Set<IntentVerb>
    let subjects: Set<IntentSubject>
    let answerShapes: Set<AnswerShape>
    let priority: Int
}

@available(iOS 19.0, macOS 26.0, *)
protocol AffordanceBearing {
    var affordance: ToolAffordance { get }
}

@available(iOS 19.0, macOS 26.0, *)
struct AffordanceDescriptor: Sendable, AffordanceBearing, Hashable {
    let name: String
    let affordance: ToolAffordance
}
