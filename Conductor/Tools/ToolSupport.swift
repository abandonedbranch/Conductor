import SwiftUI
import FoundationModels

// MARK: - Tool Badges

enum BadgeTint: String, Codable {
    case orange, blue, green, purple, red, gray

    var color: Color {
        switch self {
        case .orange: return .orange
        case .blue:   return .blue
        case .green:  return .green
        case .purple: return .purple
        case .red:    return .red
        case .gray:   return .gray
        }
    }
}

struct ToolBadge: Codable, Hashable {
    let icon: String
    let tint: BadgeTint
    let label: String
}

@available(iOS 19.0, macOS 26.0, *)
protocol BadgedTool: Tool {
    var badge: ToolBadge { get }
}

struct ToolSource: Codable, Hashable {
    let title: String
    let url: String
}

actor ToolUsageTracker {
    private var badges: Set<ToolBadge> = []
    private var sources: [ToolSource] = []
    private var workflowPreview: WorkflowPreview?
    private var webReaderStatus: WebReaderStatus?

    func record(_ badge: ToolBadge) {
        badges.insert(badge)
    }

    func addSource(_ source: ToolSource) {
        if !sources.contains(source) {
            sources.append(source)
        }
    }

    func reset() {
        badges.removeAll()
        sources.removeAll()
        workflowPreview = nil
        webReaderStatus = nil
    }

    func badgeSnapshot() -> [ToolBadge] {
        Array(badges)
    }

    func sourceSnapshot() -> [ToolSource] {
        sources
    }

    func setWorkflowPreview(_ preview: WorkflowPreview) {
        workflowPreview = preview
    }

    func workflowPreviewSnapshot() -> WorkflowPreview? {
        workflowPreview
    }

    func setWebReaderStatus(_ status: WebReaderStatus) {
        webReaderStatus = status
    }

    func webReaderStatusSnapshot() -> WebReaderStatus? {
        webReaderStatus
    }
}

@available(iOS 19.0, macOS 26.0, *)
enum SearchCapabilityAdapter {
    static func execute(tool: any BadgedTool, query: String, tracker: ToolUsageTracker) async -> String {
        switch tool {
        case let t as PubMedSearchTool:
            return await t.call(arguments: .init(searchQuery: query))
        case let t as WikipediaSearchTool:
            return (try? await t.call(arguments: .init(searchQuery: query))) ?? "Wikipedia search failed."
        case let t as ArXivSearchTool:
            return (try? await t.call(arguments: .init(searchQuery: query))) ?? "arXiv search failed."
        case let t as SemanticScholarSearchTool:
            return (try? await t.call(arguments: .init(searchQuery: query))) ?? "Semantic Scholar search failed."
        case let t as OpenAlexSearchTool:
            return (try? await t.call(arguments: .init(searchQuery: query))) ?? "OpenAlex search failed."
        case let t as CrossRefSearchTool:
            return (try? await t.call(arguments: .init(searchQuery: query))) ?? "CrossRef search failed."
        default:
            return "Unknown search tool."
        }
    }
}
