import SwiftUI
import FoundationModels

// MARK: - CrossRef Tool

@available(iOS 19.0, macOS 26.0, *)
struct CrossRefSearchTool: AgentTool {
    let name = "searchCrossRef"
    let description = "Search CrossRef for DOI metadata, publisher information, and citation counts. Good for verifying publication details."
    let purpose: AgentPurpose = .research
    let friendlyName = "CrossRef"

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: [.find],
            subjects: [.academic],
            answerShapes: [.citations, .direct],
            priority: 8
        )
    }

    @Generable
    struct Arguments {
        @Guide(description: "The search query to look up on CrossRef")
        var searchQuery: String

        @Guide(description: "Maximum number of results to return (default 3)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let maxResults = arguments.maxResults ?? 3
            let items = try await fetchResults(query: arguments.searchQuery, maxResults: maxResults)

            guard !items.isEmpty else {
                return "CrossRef results for \"\(arguments.searchQuery)\":\n\nNo results found."
            }

            var lines = ["CrossRef results for \"\(arguments.searchQuery)\":\n"]
            for (index, item) in items.enumerated() {
                let title = item.title.first ?? "Untitled"
                let year = item.publishedPrint?.dateParts?.first?.first.map(String.init) ?? "n.d."
                let authors = item.author?.compactMap { author -> String? in
                    let parts = [author.given, author.family].compactMap { $0 }.filter { !$0.isEmpty }
                    return parts.isEmpty ? nil : parts.joined(separator: " ")
                }.joined(separator: ", ") ?? "Unknown"
                let citations = item.isReferencedByCount
                let rawAbstract = item.abstract ?? ""
                let strippedAbstract = CrossRefHTMLStripper.strip(rawAbstract)
                let abstract = strippedAbstract.isEmpty ? "No abstract available." : String(strippedAbstract.prefix(400))

                lines.append("""
                    \(index + 1). \(title) (\(year))
                    Authors: \(authors)
                    Citations: \(citations)
                    Abstract: \(abstract)
                    """)
            }

            return lines.joined(separator: "\n")
        } catch {
            return "CrossRef search failed for \"\(arguments.searchQuery)\": \(error.localizedDescription)"
        }
    }

    private func fetchResults(query: String, maxResults: Int) async throws -> [CrossRefItem] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw CrossRefError.invalidQuery
        }

        let urlString = "https://api.crossref.org/works?query=\(encodedQuery)&rows=\(maxResults)&select=DOI,title,author,abstract,published-print,is-referenced-by-count"
        guard let url = URL(string: urlString) else {
            throw CrossRefError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue("Conductor/1.0 (mailto:conductor@example.com)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CrossRefError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw CrossRefError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let crossRefResponse = try decoder.decode(CrossRefResponse.self, from: data)
        return crossRefResponse.message.items
    }
}

// MARK: - CrossRef Supporting Types

struct CrossRefResponse: Codable {
    let message: CrossRefMessage
}

struct CrossRefMessage: Codable {
    let items: [CrossRefItem]
}

struct CrossRefItem: Codable {
    let doi: String
    let title: [String]
    let author: [CrossRefAuthor]?
    let abstract: String?
    let publishedPrint: CrossRefDate?
    let isReferencedByCount: Int

    enum CodingKeys: String, CodingKey {
        case doi = "DOI"
        case title
        case author
        case abstract
        case publishedPrint = "published-print"
        case isReferencedByCount = "is-referenced-by-count"
    }
}

struct CrossRefAuthor: Codable {
    let given: String?
    let family: String?
}

struct CrossRefDate: Codable {
    let dateParts: [[Int]]?

    enum CodingKeys: String, CodingKey {
        case dateParts = "date-parts"
    }
}

enum CrossRefHTMLStripper {
    static func strip(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

// MARK: - CrossRef Errors

enum CrossRefError: LocalizedError {
    case invalidQuery
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "The search query is invalid."
        case .invalidResponse:
            return "Received an invalid response from CrossRef."
        case .httpError(let statusCode):
            return "CrossRef returned an error (HTTP \(statusCode))."
        }
    }
}
