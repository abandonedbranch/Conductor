import SwiftUI
import FoundationModels

// MARK: - ArXiv Tool

@available(iOS 19.0, macOS 26.0, *)
struct ArXivSearchTool: AgentTool {
    let name = "searchArXiv"
    let description = "Search arXiv for cutting-edge preprints in physics, math, computer science, and quantitative biology."
    let purpose: AgentPurpose = .research
    let friendlyName = "arXiv"

    @Generable
    struct Arguments {
        @Guide(description: "The search query to look up on arXiv")
        var searchQuery: String

        @Guide(description: "Maximum number of results to return (default 3)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let max = arguments.maxResults ?? 3
        let query = arguments.searchQuery

        do {
            let entries = try await fetchArXivEntries(query: query, maxResults: max)

            guard !entries.isEmpty else {
                return "arXiv results for \"\(query)\":\n\nNo results found."
            }

            var lines = ["arXiv results for \"\(query)\":\n"]
            for (index, entry) in entries.enumerated() {
                let truncated = String(entry.summary.prefix(400))
                let abstract = truncated.count < entry.summary.count ? truncated + "…" : truncated
                lines.append("""
                    \(index + 1). \(entry.title)
                    Authors: \(entry.authors)
                    Abstract: \(abstract)
                    """)
            }
            return lines.joined(separator: "\n")
        } catch {
            return "arXiv search failed for \"\(query)\": \(error.localizedDescription)"
        }
    }

    private func fetchArXivEntries(query: String, maxResults: Int) async throws -> [ArXivEntry] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://export.arxiv.org/api/query?search_query=all:\(encoded)&max_results=\(maxResults)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Conductor/1.0 (Apple Intelligence App)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return ArXivXMLParser.parse(data: data)
    }
}

// MARK: - ArXiv Supporting Types

struct ArXivEntry {
    let id: String
    let title: String
    let summary: String
    let authors: String
}

class ArXivXMLParser: NSObject, XMLParserDelegate {
    private var entries: [ArXivEntry] = []

    private var inEntry = false
    private var currentElement = ""
    private var currentChars = ""

    private var currentID = ""
    private var currentTitle = ""
    private var currentSummary = ""
    private var currentAuthors: [String] = []
    private var inAuthor = false
    private var currentAuthorName = ""

    static func parse(data: Data) -> [ArXivEntry] {
        let instance = ArXivXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = instance
        parser.parse()
        return instance.entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentChars = ""

        switch elementName {
        case "entry":
            inEntry = true
            currentID = ""
            currentTitle = ""
            currentSummary = ""
            currentAuthors = []
        case "author" where inEntry:
            inAuthor = true
            currentAuthorName = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentChars += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = currentChars
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        switch elementName {
        case "entry":
            let entry = ArXivEntry(
                id: currentID,
                title: currentTitle,
                summary: currentSummary,
                authors: currentAuthors.joined(separator: ", ")
            )
            entries.append(entry)
            inEntry = false
        case "id" where inEntry && !inAuthor:
            currentID = value
        case "title" where inEntry:
            currentTitle = value
        case "summary" where inEntry:
            currentSummary = value
        case "name" where inAuthor:
            currentAuthorName = value
        case "author" where inEntry:
            if !currentAuthorName.isEmpty {
                currentAuthors.append(currentAuthorName)
            }
            inAuthor = false
            currentAuthorName = ""
        default:
            break
        }

        currentChars = ""
        currentElement = ""
    }
}
