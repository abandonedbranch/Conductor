import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Generable
struct ExtractedIntent: Sendable {
    @Guide(description: "The list of purpose-tagged tasks with dependency edges")
    var purposes: [PurposeTask]
}

@available(iOS 19.0, macOS 26.0, *)
@Generable
struct PurposeTask: Sendable {
    @Guide(description: "The purpose category: overview, research, web, or build")
    var purpose: String

    @Guide(description: "What the agent should accomplish")
    var goal: String

    @Guide(description: "When the agent should stop, e.g. 'until you have 3 cited sources'")
    var completionCriteria: String

    @Guide(description: "Indices of tasks in this array that must complete before this one starts")
    var dependsOn: [Int]
}
