import Foundation
import FoundationModels

// MARK: - Manual Pages

enum ManualPage: String, CaseIterable {
    case overview
    case search
    case automator

    var summary: String {
        switch self {
        case .overview:  return "What Conductor is and how it works"
        case .search:    return "Search across scientific and general knowledge sources"
        case .automator: return "Build macOS Automator workflows from natural language"
        }
    }

    var content: String {
        switch self {
        case .overview:
            return """
            Conductor is an on-device assistant that orchestrates system capabilities. \
            It interprets user intent and coordinates tools to fulfill requests. \
            All processing happens locally. Network access occurs only through \
            explicit search tools and is always transparent to the user.
            """
        case .search:
            return """
            Conductor can search multiple knowledge sources: \
            PubMed (biomedical/clinical), arXiv (physics, math, CS), \
            Semantic Scholar (cross-disciplinary academic), OpenAlex (bibliometrics), \
            CrossRef (DOI/citation metadata), and Wikipedia (general knowledge). \
            The appropriate source is selected automatically based on the query domain.
            """
        case .automator:
            return """
            On macOS, Conductor can build Automator workflow files from natural language descriptions. \
            It searches the system's installed Automator actions, plans a multi-step workflow, \
            and assembles a .workflow file. The user must explicitly request workflow creation.
            """
        }
    }

    static var index: String {
        allCases.map { "- \($0.rawValue): \($0.summary)" }.joined(separator: "\n")
    }
}

// MARK: - ManualTool

@available(iOS 19.0, macOS 26.0, *)
struct ManualTool: Tool {
    let name = "manual"
    let description = "Look up documentation about Conductor. Call with a page name for details, or without arguments for an index of available pages."

    @Generable
    struct Arguments {
        @Guide(description: "The manual page to look up. Omit for the index.")
        var page: String?
    }

    func call(arguments: Arguments) async -> String {
        guard let pageName = arguments.page else {
            return ManualPage.index
        }
        guard let page = ManualPage(rawValue: pageName.lowercased()) else {
            return "No manual page named \"\(pageName)\". Available pages:\n\(ManualPage.index)"
        }
        return page.content
    }
}
