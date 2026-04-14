import Foundation
import FoundationModels

// MARK: - OpenAlex Tool

@available(iOS 19.0, macOS 26.0, *)
struct OpenAlexSearchTool: AgentTool {
    let name = "searchOpenAlex"
    let description = "Search OpenAlex for scholarly works with citation data. Good for cross-disciplinary search and bibliometric analysis."
    let friendlyName = "OpenAlex"

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: [.find],
            subjects: [.academic],
            answerShapes: [.citations, .direct],
            priority: 9
        )
    }

    @Generable
    struct Arguments {
        @Guide(description: "The search query to look up on OpenAlex")
        var searchQuery: String

        @Guide(description: "Maximum number of results to return (default 3)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let limit = arguments.maxResults ?? 3

        do {
            let works = try await fetchWorks(query: arguments.searchQuery, limit: limit)

            var lines = ["OpenAlex results for \"\(arguments.searchQuery)\":\n"]

            for (index, work) in works.enumerated() {
                let year = work.publicationYear.map { String($0) } ?? "n/a"
                let authors = work.authorships
                    .map { $0.author.displayName }
                    .joined(separator: ", ")
                let abstract: String
                if let invertedIndex = work.abstractInvertedIndex {
                    let reconstructed = OpenAlexAbstractReconstructor.reconstruct(from: invertedIndex)
                    abstract = String(reconstructed.prefix(400))
                } else {
                    abstract = "No abstract available."
                }

                lines.append("""
                    \(index + 1). \(work.title) (\(year))
                    Authors: \(authors.isEmpty ? "Unknown" : authors)
                    Citations: \(work.citedByCount)
                    Abstract: \(abstract)
                    """)
            }

            return lines.joined(separator: "\n")
        } catch {
            return "OpenAlex search failed for \"\(arguments.searchQuery)\": \(error.localizedDescription)"
        }
    }

    private func fetchWorks(query: String, limit: Int) async throws -> [OpenAlexWork] {
        var components = URLComponents(string: "https://api.openalex.org/works")!
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "per_page", value: String(limit)),
            URLQueryItem(
                name: "select",
                value: "id,doi,title,authorships,publication_year,cited_by_count,abstract_inverted_index"
            ),
        ]

        guard let url = components.url else {
            throw OpenAlexError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Conductor/1.0 (mailto:conductor@example.com)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAlexError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw OpenAlexError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenAlexResponse.self, from: data)
        return decoded.results
    }
}

// MARK: - OpenAlex Supporting Types

struct OpenAlexResponse: Codable {
    let results: [OpenAlexWork]
}

struct OpenAlexWork: Codable {
    let id: String
    let doi: String?
    let title: String
    let publicationYear: Int?
    let citedByCount: Int
    let authorships: [OpenAlexAuthorship]
    let abstractInvertedIndex: [String: [Int]]?

    enum CodingKeys: String, CodingKey {
        case id, doi, title, authorships
        case publicationYear = "publication_year"
        case citedByCount = "cited_by_count"
        case abstractInvertedIndex = "abstract_inverted_index"
    }
}

struct OpenAlexAuthorship: Codable {
    let author: OpenAlexAuthor
}

struct OpenAlexAuthor: Codable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

enum OpenAlexAbstractReconstructor {
    static func reconstruct(from invertedIndex: [String: [Int]]) -> String {
        guard !invertedIndex.isEmpty else { return "" }

        var pairs: [(position: Int, word: String)] = []
        for (word, positions) in invertedIndex {
            for position in positions {
                pairs.append((position, word))
            }
        }

        pairs.sort { $0.position < $1.position }
        return pairs.map(\.word).joined(separator: " ")
    }
}

enum OpenAlexError: LocalizedError {
    case invalidQuery
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "The search query is invalid."
        case .invalidResponse:
            return "Received an invalid response from OpenAlex."
        case .httpError(let statusCode):
            return "OpenAlex returned an error (HTTP \(statusCode))."
        }
    }
}
