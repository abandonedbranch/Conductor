import SwiftUI
import FoundationModels

// MARK: - Wikipedia Tool

@available(iOS 19.0, macOS 26.0, *)
struct WikipediaSearchTool: AgentTool {
    let name = "searchWikipedia"
    let description = "Search Wikipedia for general knowledge, overviews, historical context, and encyclopedic information."
    let purpose: AgentPurpose = .overview
    let friendlyName = "Wikipedia"

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: [.find, .summarize],
            subjects: [.encyclopedic],
            answerShapes: [.overview, .summary, .direct],
            priority: 5
        )
    }

    @Generable
    struct Arguments {
        @Guide(description: "The search query to look up on Wikipedia")
        var searchQuery: String

        @Guide(description: "Maximum length of the summary to return (default 500)")
        var maxSummaryLength: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let result = try await searchWikipedia(query: arguments.searchQuery)
            let maxLength = arguments.maxSummaryLength ?? 500
            let truncatedSummary = String(result.extract.prefix(maxLength))
            var output = """
                Wikipedia Summary for "\(arguments.searchQuery)":

                \(truncatedSummary)
                """
            if let url = result.url {
                output += "\n\nSource: \(url)"
            }
            return output
        } catch let error as WikipediaError {
            return "Wikipedia search failed for \"\(arguments.searchQuery)\": \(error.localizedDescription) Try a simpler or more specific search term."
        }
    }

    private struct SearchResult {
        let title: String
        let extract: String
        let url: String?
    }

    private func searchWikipedia(query: String) async throws -> SearchResult {
        // Step 1: Use Wikipedia's search API to find the best matching article
        let articleTitle = try await findArticleTitle(for: query)

        // Step 2: Fetch the summary for that article
        let summaryURL = "https://en.wikipedia.org/api/rest_v1/page/summary/"
        guard let encodedTitle = articleTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: summaryURL + encodedTitle) else {
            throw WikipediaError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue("Conductor/1.0 (Apple Intelligence App)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WikipediaError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw WikipediaError.notFound(query: query)
        }

        guard httpResponse.statusCode == 200 else {
            throw WikipediaError.httpError(statusCode: httpResponse.statusCode)
        }

        let wikipediaResponse = try JSONDecoder().decode(WikipediaResponse.self, from: data)

        return SearchResult(title: wikipediaResponse.title, extract: wikipediaResponse.extract, url: wikipediaResponse.articleURL)
    }

    private func findArticleTitle(for query: String) async throws -> String {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srlimit", value: "1"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else {
            throw WikipediaError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue("Conductor/1.0 (Apple Intelligence App)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let searchResponse = try JSONDecoder().decode(WikipediaSearchResponse.self, from: data)

        guard let firstResult = searchResponse.query.search.first else {
            throw WikipediaError.notFound(query: query)
        }

        return firstResult.title
    }
}

// MARK: - Wikipedia Supporting Types

struct WikipediaResponse: Codable {
    let extract: String
    let title: String
    let description: String?
    let contentUrls: ContentUrls?

    enum CodingKeys: String, CodingKey {
        case extract, title, description
        case contentUrls = "content_urls"
    }

    struct ContentUrls: Codable {
        let desktop: PageUrl?

        struct PageUrl: Codable {
            let page: String?
        }
    }

    var articleURL: String? {
        contentUrls?.desktop?.page
    }
}

struct WikipediaSearchResponse: Codable {
    let query: SearchQuery

    struct SearchQuery: Codable {
        let search: [SearchResult]
    }

    struct SearchResult: Codable {
        let title: String
    }
}

enum WikipediaError: LocalizedError {
    case invalidQuery
    case notFound(query: String)
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "The search query is invalid."
        case .notFound(let query):
            return "No Wikipedia article found for \"\(query)\"."
        case .invalidResponse:
            return "Received an invalid response from Wikipedia."
        case .httpError(let statusCode):
            return "Wikipedia returned an error (HTTP \(statusCode))."
        }
    }
}
