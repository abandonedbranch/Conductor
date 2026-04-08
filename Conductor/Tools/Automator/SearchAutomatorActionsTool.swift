#if os(macOS)
import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct SearchAutomatorActionsTool: BadgedTool {
    let name = "searchAutomatorActions"
    let description = "Search for macOS Automator actions by keyword. You MUST call this before buildAutomatorWorkflow to get exact bundle paths and parameter names. Keep responses concise — summarize results briefly."
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

        @Guide(description: "Maximum number of results to return (default 3)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async -> String {
        await tracker.record(badge)

        let max = arguments.maxResults ?? 3
        let query = arguments.searchQuery
        let results = await index.search(query: query, inputType: arguments.inputType, maxResults: max)

        guard !results.isEmpty else {
            return "No Automator actions found matching \"\(query)\". Try different keywords."
        }

        var lines = ["Found \(results.count) actions:\n"]
        for (i, action) in results.enumerated() {
            let paramKeys = action.defaultParameters.keys.sorted().joined(separator: ", ")
            lines.append("\(i + 1). \(action.name) — \(action.descriptionSummary.isEmpty ? "No description" : action.descriptionSummary)")
            lines.append("   Bundle: \(action.bundleURL.path)")
            if !paramKeys.isEmpty {
                lines.append("   Params: \(paramKeys)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
#endif
