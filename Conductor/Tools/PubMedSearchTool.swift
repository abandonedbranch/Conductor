import Foundation
import SwiftUI
import FoundationModels

// MARK: - PubMed Tool

@available(iOS 19.0, macOS 26.0, *)
struct PubMedSearchTool: AgentTool {
    let name = "searchPubMed"
    let description = "Search PubMed for biomedical and clinical research papers. Use for medical, health, and life science topics."
    let friendlyName = "PubMed"

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: [.find],
            subjects: [.academic, .biomedical],
            answerShapes: [.citations, .direct],
            priority: 10
        )
    }

    @Generable
    struct Arguments {
        @Guide(description: "The search query to look up on PubMed")
        var searchQuery: String

        @Guide(description: "Maximum number of results to return (default 3)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async -> String {
        let max = arguments.maxResults ?? 3
        let query = arguments.searchQuery

        do {
            let pmids = try await fetchPMIDs(query: query, max: max)
            guard !pmids.isEmpty else {
                return "PubMed results for \"\(query)\":\n\nNo results found."
            }

            let articles = try await fetchArticles(pmids: pmids)

            var lines = ["PubMed results for \"\(query)\":\n"]
            for (index, article) in articles.enumerated() {
                let authors = article.authors
                    .map { "\($0.lastName) \(String($0.foreName.prefix(1)))" }
                    .joined(separator: ", ")
                let abstract = article.abstract.isEmpty
                    ? ""
                    : String(article.abstract.prefix(400))
                lines.append("""
                    \(index + 1). \(article.title)
                    Authors: \(authors.isEmpty ? "Unknown" : authors)
                    PMID: \(article.pmid)
                    Abstract: \(abstract)
                    """)
            }

            return lines.joined(separator: "\n")
        } catch {
            return "PubMed search failed for \"\(query)\": \(error.localizedDescription)"
        }
    }

    // MARK: - Private helpers

    private func fetchPMIDs(query: String, max: Int) async throws -> [String] {
        var components = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi")!
        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "retmode", value: "json"),
            URLQueryItem(name: "retmax", value: "\(max)"),
            URLQueryItem(name: "term", value: query),
        ]

        guard let url = components.url else {
            throw PubMedError.invalidQuery
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PubMedError.httpError
        }

        let searchResponse = try JSONDecoder().decode(PubMedSearchResponse.self, from: data)
        return searchResponse.esearchresult.idlist
    }

    private func fetchArticles(pmids: [String]) async throws -> [PubMedArticle] {
        let idParam = pmids.joined(separator: ",")
        var components = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi")!
        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "retmode", value: "xml"),
            URLQueryItem(name: "id", value: idParam),
        ]

        guard let url = components.url else {
            throw PubMedError.invalidQuery
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PubMedError.httpError
        }

        return PubMedXMLParser.parse(data: data)
    }
}

// MARK: - Response Types

struct PubMedSearchResponse: Codable {
    let esearchresult: ESearchResult

    struct ESearchResult: Codable {
        let idlist: [String]
    }
}

struct PubMedAuthor {
    let lastName: String
    let foreName: String
}

struct PubMedArticle {
    let pmid: String
    let title: String
    let abstract: String
    let authors: [PubMedAuthor]
}

// MARK: - XML Parser

final class PubMedXMLParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var articles: [PubMedArticle] = []

    // Per-article state
    private var currentPMID = ""
    private var currentTitle = ""
    private var currentAbstract = ""
    private var currentAuthors: [PubMedAuthor] = []
    private var currentLastName = ""
    private var currentForeName = ""

    // Element tracking
    private var currentElement = ""
    private var insideArticle = false
    private var insideAuthor = false
    private var buffer = ""

    static func parse(data: Data) -> [PubMedArticle] {
        let delegate = PubMedXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.articles
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        buffer = ""

        switch elementName {
        case "PubmedArticle":
            insideArticle = true
            currentPMID = ""
            currentTitle = ""
            currentAbstract = ""
            currentAuthors = []
        case "Author":
            insideAuthor = true
            currentLastName = ""
            currentForeName = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "PMID":
            // Only capture the first PMID (article-level, not citation-level)
            if insideArticle && currentPMID.isEmpty {
                currentPMID = text
            }
        case "ArticleTitle":
            if insideArticle {
                currentTitle = text
            }
        case "AbstractText":
            if insideArticle {
                if currentAbstract.isEmpty {
                    currentAbstract = text
                } else {
                    currentAbstract += " " + text
                }
            }
        case "LastName":
            if insideAuthor {
                currentLastName = text
            }
        case "ForeName":
            if insideAuthor {
                currentForeName = text
            }
        case "Author":
            if insideAuthor {
                currentAuthors.append(PubMedAuthor(lastName: currentLastName, foreName: currentForeName))
                insideAuthor = false
            }
        case "PubmedArticle":
            guard insideArticle else { break }
            articles.append(PubMedArticle(
                pmid: currentPMID,
                title: currentTitle,
                abstract: currentAbstract,
                authors: currentAuthors
            ))
            insideArticle = false
        default:
            break
        }

        buffer = ""
        currentElement = ""
    }
}

// MARK: - Errors

enum PubMedError: LocalizedError {
    case invalidQuery
    case httpError

    var errorDescription: String? {
        switch self {
        case .invalidQuery: return "The search query is invalid."
        case .httpError: return "PubMed returned an unexpected HTTP response."
        }
    }
}
