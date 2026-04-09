import Foundation
import FoundationModels

// MARK: - Routing Logic

enum LibraryRouter {
    static func route(query: String, domain: String?, registry: CapabilityRegistry) async -> String {
        let searchQuery: String
        if let domain {
            searchQuery = domain
        } else {
            searchQuery = query
        }

        let matches = await registry.search(query: searchQuery, maxResults: 1)

        guard let best = matches.first else {
            if let domain {
                return "No search backend matches domain \"\(domain)\". Try without specifying a domain."
            }
            return "No search backend available for this query."
        }

        let request = CapabilityRequest(
            userMessage: query,
            extractedGoal: query,
            parameters: nil
        )
        return await best.capability.execute(request)
    }
}

// MARK: - LibraryTool

@available(iOS 19.0, macOS 26.0, *)
struct LibraryTool: Tool {
    let name = "library"
    let description = "Search for information. Call when the user wants to know something — look up research, facts, or references."
    let registry: CapabilityRegistry
    let tracker: ToolUsageTracker

    @Generable
    struct Arguments {
        @Guide(description: "The search query")
        var query: String

        @Guide(description: "Optional knowledge domain to search, e.g. 'biomedical', 'physics', 'general'")
        var domain: String?
    }

    func call(arguments: Arguments) async -> String {
        await tracker.record(ToolBadge(icon: "books.vertical", tint: .blue, label: "Library"))
        return await Self.route(query: arguments.query, domain: arguments.domain, registry: registry)
    }

    static func route(query: String, domain: String?, registry: CapabilityRegistry) async -> String {
        await LibraryRouter.route(query: query, domain: domain, registry: registry)
    }
}
