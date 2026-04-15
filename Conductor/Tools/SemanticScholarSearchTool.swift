import SwiftUI
import FoundationModels

// MARK: - Semantic Scholar Tool

@available(iOS 19.0, macOS 26.0, *)
struct SemanticScholarSearchTool: AgentTool {
    let name = "searchSemanticScholar"
    let description = "Search Semantic Scholar for academic research across all disciplines. Good for highly cited papers and cross-disciplinary work."
    let friendlyName = "Semantic Scholar"

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: [.find],
            subjects: [.academic],
            answerShapes: [.citations, .direct],
            priority: 10
        )
    }

    @Generable
    struct Arguments {
        @Guide(description: "The search query to look up on Semantic Scholar")
        var searchQuery: String

        @Guide(description: "Maximum number of results to return (default 3)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let limit = arguments.maxResults ?? 3
            let papers = try await searchPapers(query: arguments.searchQuery, limit: limit)

            guard !papers.isEmpty else {
                return "Semantic Scholar found no results for \"\(arguments.searchQuery)\"."
            }

            var lines = ["Semantic Scholar results for \"\(arguments.searchQuery)\":\n"]
            for (index, paper) in papers.enumerated() {
                let yearString = paper.year.map { "(\($0))" } ?? "(year unknown)"
                lines.append("\(index + 1). \(paper.title) \(yearString)")

                let authorNames = paper.authors?.map(\.name).joined(separator: ", ") ?? "Unknown authors"
                lines.append("Authors: \(authorNames)")

                let citations = paper.citationCount ?? 0
                lines.append("Citations: \(citations)")

                if let abstract = paper.abstract {
                    let truncated = String(abstract.prefix(400))
                    let suffix = abstract.count > 400 ? "…" : ""
                    lines.append("Abstract: \(truncated)\(suffix)")
                } else {
                    lines.append("Abstract: Not available")
                }

                lines.append("")
            }

            return lines.joined(separator: "\n")
        } catch let error as SemanticScholarError {
            return "Semantic Scholar search failed for \"\(arguments.searchQuery)\": \(error.localizedDescription)"
        }
    }

    private func searchPapers(query: String, limit: Int) async throws -> [SemanticScholarPaper] {
        guard var components = URLComponents(string: "https://api.semanticscholar.org/graph/v1/paper/search") else {
            throw SemanticScholarError.invalidQuery
        }

        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "fields", value: "title,abstract,authors,year,citationCount,url"),
        ]

        guard let url = components.url else {
            throw SemanticScholarError.invalidQuery
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SemanticScholarError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw SemanticScholarError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(SemanticScholarResponse.self, from: data)
        return decoded.data
    }
}

// MARK: - Semantic Scholar Supporting Types

struct SemanticScholarResponse: Codable {
    let data: [SemanticScholarPaper]
}

struct SemanticScholarPaper: Codable {
    let title: String
    let abstract: String?
    let authors: [SemanticScholarAuthor]?
    let year: Int?
    let citationCount: Int?
    let url: String?
}

struct SemanticScholarAuthor: Codable {
    let name: String
}

enum SemanticScholarError: LocalizedError {
    case invalidQuery
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "The search query is invalid."
        case .invalidResponse:
            return "Received an invalid response from Semantic Scholar."
        case .httpError(let statusCode):
            return "Semantic Scholar returned an error (HTTP \(statusCode))."
        }
    }
}
