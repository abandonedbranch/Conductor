#if os(macOS)
import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct SearchAutomatorActionsTool: BadgedTool {
    let name = "searchAutomatorActions"
    let description = "Search for macOS Automator actions by keyword. Use this to discover available actions before building a workflow. Returns action names, descriptions, input/output types, and configurable parameters."
    let tracker: ToolUsageTracker
    let badge = ToolBadge(icon: "gear.badge", tint: .gray, label: "Automator")

    private let index: AutomatorActionIndex

    init(tracker: ToolUsageTracker, index: AutomatorActionIndex) {
        self.tracker = tracker
        self.index = index
    }

    @Generable
    struct Arguments {
        @Guide(description: "Keywords to search for in action names, categories, and descriptions")
        var searchQuery: String

        @Guide(description: "Optional UTI filter to find actions that accept a specific input type (e.g. public.image)")
        var inputType: String?

        @Guide(description: "Maximum number of results to return (default 5)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async -> String {
        await tracker.record(badge)

        let max = arguments.maxResults ?? 5
        let query = arguments.searchQuery
        let results = await index.search(query: query, inputType: arguments.inputType, maxResults: max)

        guard !results.isEmpty else {
            return "No Automator actions found matching \"\(query)\". Try different keywords."
        }

        var lines = ["Automator actions matching \"\(query)\":\n"]
        for (i, action) in results.enumerated() {
            let params = action.defaultParameters.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            let inputDesc = action.inputTypes.isEmpty ? "None" : "\(action.inputTypes.joined(separator: ", ")) (\(action.inputContainer))"
            let outputDesc = action.outputTypes.isEmpty ? "None" : "\(action.outputTypes.joined(separator: ", ")) (\(action.outputContainer))"

            lines.append("""
                \(i + 1). \(action.name) (\(action.category))
                   Description: \(action.descriptionSummary.isEmpty ? "No description" : action.descriptionSummary)
                   Accepts: \(inputDesc)
                   Provides: \(outputDesc)
                   Parameters: \(params.isEmpty ? "None" : params)
                   Bundle: \(action.bundleURL.path)
                """)
        }

        return lines.joined(separator: "\n")
    }
}
#endif
