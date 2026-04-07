# Scientific Research Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add PubMed, Semantic Scholar, arXiv, OpenAlex, and CrossRef search tools so the on-device model can find and synthesize scientific literature, with tappable source citations for each result.

**Architecture:** One file per tool under `Conductor/Tools/`. Shared types (`BadgedTool`, `ToolBadge`, `ToolSource`, `ToolUsageTracker`) extracted to `ToolSupport.swift`. ContentView updated to register all tools and updated system instructions.

**Tech Stack:** Swift 6, FoundationModels framework, Foundation `XMLParser` (for PubMed/arXiv), `JSONDecoder` (for Semantic Scholar/OpenAlex/CrossRef), Swift Testing

---

### Task 1: Extract Shared Tool Types to ToolSupport.swift

**Files:**
- Create: `Conductor/Tools/ToolSupport.swift`
- Modify: `Conductor/ContentView.swift` (remove extracted types)

- [ ] **Step 1: Create `Conductor/Tools/` directory**

```bash
mkdir -p Conductor/Tools
```

- [ ] **Step 2: Create `Conductor/Tools/ToolSupport.swift`**

Create the file with the shared types extracted from ContentView:

```swift
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
    }

    func badgeSnapshot() -> [ToolBadge] {
        Array(badges)
    }

    func sourceSnapshot() -> [ToolSource] {
        sources
    }
}
```

- [ ] **Step 3: Remove extracted types from ContentView.swift**

Remove the entire `// MARK: - Tool Badges` section from ContentView.swift (lines containing `BadgeTint`, `ToolBadge`, `BadgedTool`, `ToolSource`, `ToolUsageTracker`). These now live in `ToolSupport.swift`.

- [ ] **Step 4: Add new files to Xcode project**

Open `Conductor.xcodeproj/project.pbxproj` and add `Conductor/Tools/ToolSupport.swift` to the Conductor target's build sources. Alternatively, ensure the Xcode project uses a folder reference or add via Xcode.

- [ ] **Step 5: Build to verify extraction**

```bash
# Build via XcodeBuildMCP
```

Expected: Build succeeds. All types are resolved from ToolSupport.swift.

- [ ] **Step 6: Commit**

```bash
git add Conductor/Tools/ToolSupport.swift Conductor/ContentView.swift Conductor.xcodeproj/project.pbxproj
git commit -m "(tools): extract shared tool types to ToolSupport.swift"
```

---

### Task 2: Extract WikipediaSearchTool to Its Own File

**Files:**
- Create: `Conductor/Tools/WikipediaSearchTool.swift`
- Modify: `Conductor/ContentView.swift` (remove Wikipedia tool and supporting types)

- [ ] **Step 1: Create `Conductor/Tools/WikipediaSearchTool.swift`**

Move the entire `WikipediaSearchTool` struct, `WikipediaResponse`, `WikipediaSearchResponse`, and `WikipediaError` from ContentView.swift into this new file:

```swift
import SwiftUI
import FoundationModels

// MARK: - Wikipedia Search Tool

@available(iOS 19.0, macOS 26.0, *)
struct WikipediaSearchTool: BadgedTool {
    let name = "searchWikipedia"
    let description = "Search Wikipedia for a summary of a topic"
    let tracker: ToolUsageTracker
    let badge = ToolBadge(icon: "globe", tint: .orange, label: "Wikipedia")

    @Generable
    struct Arguments {
        @Guide(description: "The search query to look up on Wikipedia")
        var searchQuery: String

        @Guide(description: "Maximum length of the summary to return (default 500)")
        var maxSummaryLength: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await tracker.record(badge)

        do {
            let result = try await searchWikipedia(query: arguments.searchQuery)
            let maxLength = arguments.maxSummaryLength ?? 500
            let truncatedSummary = String(result.extract.prefix(maxLength))
            if let url = result.url {
                await tracker.addSource(ToolSource(title: result.title, url: url))
            }
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
        let articleTitle = try await findArticleTitle(for: query)

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
```

- [ ] **Step 2: Remove Wikipedia code from ContentView.swift**

Remove everything from `// MARK: - Wikipedia Tool` through `// MARK: - Tool Badges` (the tool struct, response types, and error enum). ContentView.swift should now start with `import SwiftUI` / `import FoundationModels` and go straight to `// MARK: - Models`.

- [ ] **Step 3: Add to Xcode project and build**

Add `Conductor/Tools/WikipediaSearchTool.swift` to the Conductor target. Build to verify.

Expected: Build succeeds. Wikipedia tool works identically but lives in its own file.

- [ ] **Step 4: Commit**

```bash
git add Conductor/Tools/WikipediaSearchTool.swift Conductor/ContentView.swift Conductor.xcodeproj/project.pbxproj
git commit -m "(tools): extract WikipediaSearchTool to its own file"
```

---

### Task 3: Implement SemanticScholarSearchTool

**Files:**
- Create: `Conductor/Tools/SemanticScholarSearchTool.swift`
- Test: `ConductorTests/SemanticScholarTests.swift`

- [ ] **Step 1: Write the response parsing test**

Create `ConductorTests/SemanticScholarTests.swift`:

```swift
import Testing
@testable import Conductor

@Suite("Semantic Scholar Response Parsing")
struct SemanticScholarTests {
    @Test("Decodes paper search response with all fields")
    func decodePaperResponse() throws {
        let json = """
        {
            "total": 100,
            "data": [
                {
                    "paperId": "abc123",
                    "title": "Attention Is All You Need",
                    "abstract": "The dominant sequence transduction models are based on complex recurrent or convolutional neural networks.",
                    "year": 2017,
                    "citationCount": 90000,
                    "authors": [
                        {"name": "Ashish Vaswani"},
                        {"name": "Noam Shazeer"}
                    ],
                    "url": "https://www.semanticscholar.org/paper/abc123"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SemanticScholarResponse.self, from: json)
        #expect(response.data.count == 1)
        #expect(response.data[0].title == "Attention Is All You Need")
        #expect(response.data[0].year == 2017)
        #expect(response.data[0].citationCount == 90000)
        #expect(response.data[0].authors.count == 2)
        #expect(response.data[0].authors[0].name == "Ashish Vaswani")
        #expect(response.data[0].url == "https://www.semanticscholar.org/paper/abc123")
    }

    @Test("Decodes response with nil abstract")
    func decodeNilAbstract() throws {
        let json = """
        {
            "total": 1,
            "data": [
                {
                    "paperId": "xyz",
                    "title": "Some Paper",
                    "abstract": null,
                    "year": 2020,
                    "citationCount": 5,
                    "authors": [],
                    "url": "https://www.semanticscholar.org/paper/xyz"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SemanticScholarResponse.self, from: json)
        #expect(response.data[0].abstract == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Build and run tests. Expected: FAIL — `SemanticScholarResponse` type not found.

- [ ] **Step 3: Implement SemanticScholarSearchTool**

Create `Conductor/Tools/SemanticScholarSearchTool.swift`:

```swift
import SwiftUI
import FoundationModels

// MARK: - Semantic Scholar Search Tool

@available(iOS 19.0, macOS 26.0, *)
struct SemanticScholarSearchTool: BadgedTool {
    let name = "searchSemanticScholar"
    let description = "Search Semantic Scholar for academic research papers across all disciplines"
    let tracker: ToolUsageTracker
    let badge = ToolBadge(icon: "brain.head.profile", tint: .blue, label: "Semantic Scholar")

    @Generable
    struct Arguments {
        @Guide(description: "The search query to find academic papers")
        var searchQuery: String

        @Guide(description: "Maximum number of results to return (default 3)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await tracker.record(badge)
        let limit = arguments.maxResults ?? 3

        do {
            let papers = try await searchPapers(query: arguments.searchQuery, limit: limit)

            if papers.isEmpty {
                return "Semantic Scholar returned no results for \"\(arguments.searchQuery)\". Try a broader or different search term."
            }

            var output = "Semantic Scholar results for \"\(arguments.searchQuery)\":\n"

            for (index, paper) in papers.enumerated() {
                let authors = paper.authors.map(\.name).joined(separator: ", ")
                let yearStr = paper.year.map { "(\($0))" } ?? ""
                let abstract = paper.abstract.map { String($0.prefix(400)) } ?? "No abstract available."

                output += """

                    \(index + 1). \(paper.title) \(yearStr)
                    Authors: \(authors.isEmpty ? "Unknown" : authors)
                    Citations: \(paper.citationCount ?? 0)
                    Abstract: \(abstract)
                    """

                if let url = paper.url {
                    await tracker.addSource(ToolSource(title: paper.title, url: url))
                }
            }

            return output
        } catch {
            return "Could not reach Semantic Scholar. Check your internet connection."
        }
    }

    private func searchPapers(query: String, limit: Int) async throws -> [SemanticScholarPaper] {
        var components = URLComponents(string: "https://api.semanticscholar.org/graph/v1/paper/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "fields", value: "title,abstract,authors,year,citationCount,url"),
        ]

        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Conductor/1.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SemanticScholarResponse.self, from: data)
        return response.data
    }
}

// MARK: - Semantic Scholar Response Types

struct SemanticScholarResponse: Codable {
    let data: [SemanticScholarPaper]
}

struct SemanticScholarPaper: Codable {
    let paperId: String
    let title: String
    let abstract: String?
    let year: Int?
    let citationCount: Int?
    let authors: [SemanticScholarAuthor]
    let url: String?
}

struct SemanticScholarAuthor: Codable {
    let name: String
}
```

- [ ] **Step 4: Add files to Xcode project and run tests**

Add `SemanticScholarSearchTool.swift` to the Conductor target and `SemanticScholarTests.swift` to the ConductorTests target. Build and run tests.

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Tools/SemanticScholarSearchTool.swift ConductorTests/SemanticScholarTests.swift Conductor.xcodeproj/project.pbxproj
git commit -m "(tools): implement SemanticScholarSearchTool"
```

---

### Task 4: Implement PubMedSearchTool

**Files:**
- Create: `Conductor/Tools/PubMedSearchTool.swift`
- Test: `ConductorTests/PubMedTests.swift`

- [ ] **Step 1: Write the XML parsing test**

Create `ConductorTests/PubMedTests.swift`:

```swift
import Testing
@testable import Conductor

@Suite("PubMed Response Parsing")
struct PubMedTests {
    @Test("Decodes esearch JSON response for PMIDs")
    func decodeSearchResponse() throws {
        let json = """
        {
            "esearchresult": {
                "idlist": ["38012345", "37998765", "37654321"]
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(PubMedSearchResponse.self, from: json)
        #expect(response.esearchresult.idlist.count == 3)
        #expect(response.esearchresult.idlist[0] == "38012345")
    }

    @Test("Parses efetch XML into articles")
    func parseArticleXML() {
        let xml = """
        <?xml version="1.0"?>
        <PubmedArticleSet>
            <PubmedArticle>
                <MedlineCitation>
                    <PMID>38012345</PMID>
                    <Article>
                        <ArticleTitle>CRISPR-Cas9 Gene Editing in Vivo</ArticleTitle>
                        <Abstract>
                            <AbstractText>We report a novel approach to in vivo gene editing using CRISPR-Cas9.</AbstractText>
                        </Abstract>
                        <AuthorList>
                            <Author>
                                <LastName>Zhang</LastName>
                                <ForeName>Feng</ForeName>
                            </Author>
                            <Author>
                                <LastName>Doudna</LastName>
                                <ForeName>Jennifer</ForeName>
                            </Author>
                        </AuthorList>
                    </Article>
                </MedlineCitation>
            </PubmedArticle>
        </PubmedArticleSet>
        """.data(using: .utf8)!

        let articles = PubMedXMLParser.parse(data: xml)
        #expect(articles.count == 1)
        #expect(articles[0].pmid == "38012345")
        #expect(articles[0].title == "CRISPR-Cas9 Gene Editing in Vivo")
        #expect(articles[0].abstract == "We report a novel approach to in vivo gene editing using CRISPR-Cas9.")
        #expect(articles[0].authors == "Zhang F, Doudna J")
    }

    @Test("Handles article with no abstract")
    func parseArticleWithoutAbstract() {
        let xml = """
        <?xml version="1.0"?>
        <PubmedArticleSet>
            <PubmedArticle>
                <MedlineCitation>
                    <PMID>99999999</PMID>
                    <Article>
                        <ArticleTitle>Brief Report</ArticleTitle>
                        <AuthorList>
                            <Author>
                                <LastName>Smith</LastName>
                                <ForeName>John</ForeName>
                            </Author>
                        </AuthorList>
                    </Article>
                </MedlineCitation>
            </PubmedArticle>
        </PubmedArticleSet>
        """.data(using: .utf8)!

        let articles = PubMedXMLParser.parse(data: xml)
        #expect(articles.count == 1)
        #expect(articles[0].abstract == "")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `PubMedSearchResponse` and `PubMedXMLParser` not found.

- [ ] **Step 3: Implement PubMedSearchTool**

Create `Conductor/Tools/PubMedSearchTool.swift`:

```swift
import SwiftUI
import FoundationModels

// MARK: - PubMed Search Tool

@available(iOS 19.0, macOS 26.0, *)
struct PubMedSearchTool: BadgedTool {
    let name = "searchPubMed"
    let description = "Search PubMed for biomedical and clinical research papers"
    let tracker: ToolUsageTracker
    let badge = ToolBadge(icon: "cross.case", tint: .red, label: "PubMed")

    @Generable
    struct Arguments {
        @Guide(description: "The search query to find biomedical research papers")
        var searchQuery: String

        @Guide(description: "Maximum number of results to return (default 3)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await tracker.record(badge)
        let limit = arguments.maxResults ?? 3

        do {
            let pmids = try await searchPMIDs(query: arguments.searchQuery, limit: limit)

            if pmids.isEmpty {
                return "PubMed returned no results for \"\(arguments.searchQuery)\". Try a broader or different search term."
            }

            let articles = try await fetchArticles(pmids: pmids)

            if articles.isEmpty {
                return "PubMed returned no results for \"\(arguments.searchQuery)\". Try a broader or different search term."
            }

            var output = "PubMed results for \"\(arguments.searchQuery)\":\n"

            for (index, article) in articles.enumerated() {
                let abstract = article.abstract.isEmpty
                    ? "No abstract available."
                    : String(article.abstract.prefix(400))

                output += """

                    \(index + 1). \(article.title)
                    Authors: \(article.authors.isEmpty ? "Unknown" : article.authors)
                    PMID: \(article.pmid)
                    Abstract: \(abstract)
                    """

                let url = "https://pubmed.ncbi.nlm.nih.gov/\(article.pmid)"
                await tracker.addSource(ToolSource(title: article.title, url: url))
            }

            return output
        } catch {
            return "Could not reach PubMed. Check your internet connection."
        }
    }

    private func searchPMIDs(query: String, limit: Int) async throws -> [String] {
        var components = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi")!
        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "retmode", value: "json"),
            URLQueryItem(name: "retmax", value: String(limit)),
            URLQueryItem(name: "term", value: query),
        ]

        guard let url = components.url else { return [] }

        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
        let response = try JSONDecoder().decode(PubMedSearchResponse.self, from: data)
        return response.esearchresult.idlist
    }

    private func fetchArticles(pmids: [String]) async throws -> [PubMedArticle] {
        let idString = pmids.joined(separator: ",")
        var components = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi")!
        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "retmode", value: "xml"),
            URLQueryItem(name: "id", value: idString),
        ]

        guard let url = components.url else { return [] }

        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
        return PubMedXMLParser.parse(data: data)
    }
}

// MARK: - PubMed Response Types

struct PubMedSearchResponse: Codable {
    let esearchresult: ESearchResult

    struct ESearchResult: Codable {
        let idlist: [String]
    }
}

struct PubMedArticle {
    let pmid: String
    let title: String
    let abstract: String
    let authors: String
}

// MARK: - PubMed XML Parser

final class PubMedXMLParser: NSObject, XMLParserDelegate {
    private var articles: [PubMedArticle] = []
    private var currentElement = ""
    private var currentPMID = ""
    private var currentTitle = ""
    private var currentAbstract = ""
    private var currentAuthors: [(last: String, fore: String)] = []
    private var currentLastName = ""
    private var currentForeName = ""
    private var inArticle = false
    private var characterBuffer = ""

    static func parse(data: Data) -> [PubMedArticle] {
        let handler = PubMedXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()
        return handler.articles
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        characterBuffer = ""

        if elementName == "PubmedArticle" {
            inArticle = true
            currentPMID = ""
            currentTitle = ""
            currentAbstract = ""
            currentAuthors = []
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characterBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let trimmed = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "PMID":
            if inArticle && currentPMID.isEmpty {
                currentPMID = trimmed
            }
        case "ArticleTitle":
            currentTitle = trimmed
        case "AbstractText":
            if !currentAbstract.isEmpty {
                currentAbstract += " "
            }
            currentAbstract += trimmed
        case "LastName":
            currentLastName = trimmed
        case "ForeName":
            currentForeName = trimmed
        case "Author":
            if !currentLastName.isEmpty {
                currentAuthors.append((last: currentLastName, fore: currentForeName))
                currentLastName = ""
                currentForeName = ""
            }
        case "PubmedArticle":
            let authorStr = currentAuthors.map { author in
                let initial = author.fore.isEmpty ? "" : " \(author.fore.prefix(1))"
                return "\(author.last)\(initial)"
            }.joined(separator: ", ")

            articles.append(PubMedArticle(
                pmid: currentPMID,
                title: currentTitle,
                abstract: currentAbstract,
                authors: authorStr
            ))
            inArticle = false
        default:
            break
        }

        currentElement = ""
    }
}
```

- [ ] **Step 4: Add files to Xcode project and run tests**

Add `PubMedSearchTool.swift` to the Conductor target and `PubMedTests.swift` to the ConductorTests target. Build and run tests.

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Tools/PubMedSearchTool.swift ConductorTests/PubMedTests.swift Conductor.xcodeproj/project.pbxproj
git commit -m "(tools): implement PubMedSearchTool with XML parser"
```

---

### Task 5: Implement ArXivSearchTool

**Files:**
- Create: `Conductor/Tools/ArXivSearchTool.swift`
- Test: `ConductorTests/ArXivTests.swift`

- [ ] **Step 1: Write the Atom XML parsing test**

Create `ConductorTests/ArXivTests.swift`:

```swift
import Testing
@testable import Conductor

@Suite("arXiv Response Parsing")
struct ArXivTests {
    @Test("Parses Atom feed into entries")
    func parseAtomFeed() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <id>http://arxiv.org/abs/2301.12345v1</id>
                <title>Large Language Models: A Survey</title>
                <summary>This paper surveys the landscape of large language models and their applications in natural language processing.</summary>
                <author><name>Alice Smith</name></author>
                <author><name>Bob Jones</name></author>
            </entry>
            <entry>
                <id>http://arxiv.org/abs/2302.67890v2</id>
                <title>Quantum Computing Advances</title>
                <summary>Recent advances in quantum error correction are discussed.</summary>
                <author><name>Carol Zhang</name></author>
            </entry>
        </feed>
        """.data(using: .utf8)!

        let entries = ArXivXMLParser.parse(data: xml)
        #expect(entries.count == 2)
        #expect(entries[0].title == "Large Language Models: A Survey")
        #expect(entries[0].summary == "This paper surveys the landscape of large language models and their applications in natural language processing.")
        #expect(entries[0].id == "http://arxiv.org/abs/2301.12345v1")
        #expect(entries[0].authors == "Alice Smith, Bob Jones")
        #expect(entries[1].authors == "Carol Zhang")
    }

    @Test("Handles empty feed")
    func parseEmptyFeed() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
        </feed>
        """.data(using: .utf8)!

        let entries = ArXivXMLParser.parse(data: xml)
        #expect(entries.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `ArXivXMLParser` not found.

- [ ] **Step 3: Implement ArXivSearchTool**

Create `Conductor/Tools/ArXivSearchTool.swift`:

```swift
import SwiftUI
import FoundationModels

// MARK: - arXiv Search Tool

@available(iOS 19.0, macOS 26.0, *)
struct ArXivSearchTool: BadgedTool {
    let name = "searchArXiv"
    let description = "Search arXiv for preprints in physics, math, computer science, and biology"
    let tracker: ToolUsageTracker
    let badge = ToolBadge(icon: "doc.text", tint: .green, label: "arXiv")

    @Generable
    struct Arguments {
        @Guide(description: "The search query to find preprint papers")
        var searchQuery: String

        @Guide(description: "Maximum number of results to return (default 3)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await tracker.record(badge)
        let limit = arguments.maxResults ?? 3

        do {
            let entries = try await searchArXiv(query: arguments.searchQuery, limit: limit)

            if entries.isEmpty {
                return "arXiv returned no results for \"\(arguments.searchQuery)\". Try a broader or different search term."
            }

            var output = "arXiv results for \"\(arguments.searchQuery)\":\n"

            for (index, entry) in entries.enumerated() {
                let abstract = String(entry.summary.prefix(400))

                output += """

                    \(index + 1). \(entry.title)
                    Authors: \(entry.authors.isEmpty ? "Unknown" : entry.authors)
                    Abstract: \(abstract)
                    """

                await tracker.addSource(ToolSource(title: entry.title, url: entry.id))
            }

            return output
        } catch {
            return "Could not reach arXiv. Check your internet connection."
        }
    }

    private func searchArXiv(query: String, limit: Int) async throws -> [ArXivEntry] {
        var components = URLComponents(string: "https://export.arxiv.org/api/query")!
        components.queryItems = [
            URLQueryItem(name: "search_query", value: "all:\(query)"),
            URLQueryItem(name: "max_results", value: String(limit)),
        ]

        guard let url = components.url else { return [] }

        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
        return ArXivXMLParser.parse(data: data)
    }
}

// MARK: - arXiv Response Types

struct ArXivEntry {
    let id: String
    let title: String
    let summary: String
    let authors: String
}

// MARK: - arXiv Atom XML Parser

final class ArXivXMLParser: NSObject, XMLParserDelegate {
    private var entries: [ArXivEntry] = []
    private var currentElement = ""
    private var characterBuffer = ""
    private var inEntry = false
    private var currentId = ""
    private var currentTitle = ""
    private var currentSummary = ""
    private var currentAuthors: [String] = []
    private var currentAuthorName = ""

    static func parse(data: Data) -> [ArXivEntry] {
        let handler = ArXivXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()
        return handler.entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        characterBuffer = ""

        if elementName == "entry" {
            inEntry = true
            currentId = ""
            currentTitle = ""
            currentSummary = ""
            currentAuthors = []
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characterBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let trimmed = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if inEntry {
            switch elementName {
            case "id":
                currentId = trimmed
            case "title":
                // arXiv titles often have newlines in them
                currentTitle = trimmed.replacingOccurrences(of: "\n", with: " ")
            case "summary":
                currentSummary = trimmed.replacingOccurrences(of: "\n", with: " ")
            case "name":
                currentAuthorName = trimmed
            case "author":
                if !currentAuthorName.isEmpty {
                    currentAuthors.append(currentAuthorName)
                    currentAuthorName = ""
                }
            case "entry":
                entries.append(ArXivEntry(
                    id: currentId,
                    title: currentTitle,
                    summary: currentSummary,
                    authors: currentAuthors.joined(separator: ", ")
                ))
                inEntry = false
            default:
                break
            }
        }

        currentElement = ""
    }
}
```

- [ ] **Step 4: Add files to Xcode project and run tests**

Add `ArXivSearchTool.swift` to the Conductor target and `ArXivTests.swift` to the ConductorTests target. Build and run tests.

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Tools/ArXivSearchTool.swift ConductorTests/ArXivTests.swift Conductor.xcodeproj/project.pbxproj
git commit -m "(tools): implement ArXivSearchTool with Atom XML parser"
```

---

### Task 6: Implement OpenAlexSearchTool

**Files:**
- Create: `Conductor/Tools/OpenAlexSearchTool.swift`
- Test: `ConductorTests/OpenAlexTests.swift`

- [ ] **Step 1: Write the inverted index reconstruction test**

Create `ConductorTests/OpenAlexTests.swift`:

```swift
import Testing
@testable import Conductor

@Suite("OpenAlex Response Parsing")
struct OpenAlexTests {
    @Test("Reconstructs abstract from inverted index")
    func reconstructAbstract() {
        let invertedIndex: [String: [Int]] = [
            "The": [0],
            "quick": [1],
            "brown": [2],
            "fox": [3],
            "jumps": [4]
        ]
        let result = OpenAlexAbstractReconstructor.reconstruct(from: invertedIndex)
        #expect(result == "The quick brown fox jumps")
    }

    @Test("Handles empty inverted index")
    func emptyAbstract() {
        let result = OpenAlexAbstractReconstructor.reconstruct(from: [:])
        #expect(result == "")
    }

    @Test("Decodes work response with all fields")
    func decodeWorkResponse() throws {
        let json = """
        {
            "results": [
                {
                    "id": "https://openalex.org/W123",
                    "doi": "https://doi.org/10.1234/test",
                    "title": "Test Paper",
                    "publication_year": 2023,
                    "cited_by_count": 42,
                    "authorships": [
                        {
                            "author": {
                                "display_name": "Jane Doe"
                            }
                        }
                    ],
                    "abstract_inverted_index": {
                        "Hello": [0],
                        "world": [1]
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(OpenAlexResponse.self, from: json)
        #expect(response.results.count == 1)
        #expect(response.results[0].title == "Test Paper")
        #expect(response.results[0].publicationYear == 2023)
        #expect(response.results[0].citedByCount == 42)
        #expect(response.results[0].authorships[0].author.displayName == "Jane Doe")
        #expect(response.results[0].doi == "https://doi.org/10.1234/test")
    }

    @Test("Decodes work with nil abstract inverted index")
    func decodeNilAbstract() throws {
        let json = """
        {
            "results": [
                {
                    "id": "https://openalex.org/W456",
                    "doi": null,
                    "title": "No Abstract Paper",
                    "publication_year": 2020,
                    "cited_by_count": 0,
                    "authorships": [],
                    "abstract_inverted_index": null
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(OpenAlexResponse.self, from: json)
        #expect(response.results[0].abstractInvertedIndex == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `OpenAlexResponse` and `OpenAlexAbstractReconstructor` not found.

- [ ] **Step 3: Implement OpenAlexSearchTool**

Create `Conductor/Tools/OpenAlexSearchTool.swift`:

```swift
import SwiftUI
import FoundationModels

// MARK: - OpenAlex Search Tool

@available(iOS 19.0, macOS 26.0, *)
struct OpenAlexSearchTool: BadgedTool {
    let name = "searchOpenAlex"
    let description = "Search OpenAlex for academic works across all disciplines with citation data"
    let tracker: ToolUsageTracker
    let badge = ToolBadge(icon: "books.vertical", tint: .purple, label: "OpenAlex")

    @Generable
    struct Arguments {
        @Guide(description: "The search query to find academic works")
        var searchQuery: String

        @Guide(description: "Maximum number of results to return (default 3)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await tracker.record(badge)
        let limit = arguments.maxResults ?? 3

        do {
            let works = try await searchWorks(query: arguments.searchQuery, limit: limit)

            if works.isEmpty {
                return "OpenAlex returned no results for \"\(arguments.searchQuery)\". Try a broader or different search term."
            }

            var output = "OpenAlex results for \"\(arguments.searchQuery)\":\n"

            for (index, work) in works.enumerated() {
                let authors = work.authorships.map(\.author.displayName).joined(separator: ", ")
                let yearStr = work.publicationYear.map { "(\($0))" } ?? ""
                let abstract: String
                if let invertedIndex = work.abstractInvertedIndex {
                    abstract = String(OpenAlexAbstractReconstructor.reconstruct(from: invertedIndex).prefix(400))
                } else {
                    abstract = "No abstract available."
                }

                output += """

                    \(index + 1). \(work.title) \(yearStr)
                    Authors: \(authors.isEmpty ? "Unknown" : authors)
                    Citations: \(work.citedByCount)
                    Abstract: \(abstract)
                    """

                let sourceURL = work.doi ?? work.id
                await tracker.addSource(ToolSource(title: work.title, url: sourceURL))
            }

            return output
        } catch {
            return "Could not reach OpenAlex. Check your internet connection."
        }
    }

    private func searchWorks(query: String, limit: Int) async throws -> [OpenAlexWork] {
        var components = URLComponents(string: "https://api.openalex.org/works")!
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "per_page", value: String(limit)),
            URLQueryItem(name: "select", value: "id,doi,title,authorships,publication_year,cited_by_count,abstract_inverted_index"),
        ]

        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Conductor/1.0 (mailto:conductor@example.com)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OpenAlexResponse.self, from: data)
        return response.results
    }
}

// MARK: - OpenAlex Response Types

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

// MARK: - Abstract Reconstruction

enum OpenAlexAbstractReconstructor {
    static func reconstruct(from invertedIndex: [String: [Int]]) -> String {
        var words: [(Int, String)] = []
        for (word, positions) in invertedIndex {
            for position in positions {
                words.append((position, word))
            }
        }
        words.sort { $0.0 < $1.0 }
        return words.map(\.1).joined(separator: " ")
    }
}
```

- [ ] **Step 4: Add files to Xcode project and run tests**

Add `OpenAlexSearchTool.swift` to the Conductor target and `OpenAlexTests.swift` to the ConductorTests target. Build and run tests.

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Tools/OpenAlexSearchTool.swift ConductorTests/OpenAlexTests.swift Conductor.xcodeproj/project.pbxproj
git commit -m "(tools): implement OpenAlexSearchTool with inverted index parser"
```

---

### Task 7: Implement CrossRefSearchTool

**Files:**
- Create: `Conductor/Tools/CrossRefSearchTool.swift`
- Test: `ConductorTests/CrossRefTests.swift`

- [ ] **Step 1: Write the HTML stripping and response parsing test**

Create `ConductorTests/CrossRefTests.swift`:

```swift
import Testing
@testable import Conductor

@Suite("CrossRef Response Parsing")
struct CrossRefTests {
    @Test("Strips HTML tags from abstract")
    func stripHTMLTags() {
        let html = "<jats:p>This is a <jats:italic>test</jats:italic> of HTML <jats:bold>stripping</jats:bold>.</jats:p>"
        let result = CrossRefHTMLStripper.strip(html)
        #expect(result == "This is a test of HTML stripping.")
    }

    @Test("Handles plain text without tags")
    func stripPlainText() {
        let text = "No HTML here"
        let result = CrossRefHTMLStripper.strip(text)
        #expect(result == "No HTML here")
    }

    @Test("Decodes CrossRef works response")
    func decodeWorksResponse() throws {
        let json = """
        {
            "message": {
                "items": [
                    {
                        "DOI": "10.1234/test.2023",
                        "title": ["A Test Paper"],
                        "author": [
                            {"given": "Alice", "family": "Smith"},
                            {"given": "Bob", "family": "Jones"}
                        ],
                        "abstract": "<jats:p>This paper tests things.</jats:p>",
                        "published-print": {"date-parts": [[2023, 6]]},
                        "is-referenced-by-count": 15
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CrossRefResponse.self, from: json)
        let item = response.message.items[0]
        #expect(item.doi == "10.1234/test.2023")
        #expect(item.title.first == "A Test Paper")
        #expect(item.author?.count == 2)
        #expect(item.author?[0].family == "Smith")
        #expect(item.abstract == "<jats:p>This paper tests things.</jats:p>")
        #expect(item.isReferencedByCount == 15)
    }

    @Test("Decodes item with missing optional fields")
    func decodeMissingFields() throws {
        let json = """
        {
            "message": {
                "items": [
                    {
                        "DOI": "10.5678/minimal",
                        "title": ["Minimal Paper"],
                        "is-referenced-by-count": 0
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CrossRefResponse.self, from: json)
        let item = response.message.items[0]
        #expect(item.author == nil)
        #expect(item.abstract == nil)
        #expect(item.publishedPrint == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `CrossRefResponse` and `CrossRefHTMLStripper` not found.

- [ ] **Step 3: Implement CrossRefSearchTool**

Create `Conductor/Tools/CrossRefSearchTool.swift`:

```swift
import SwiftUI
import FoundationModels

// MARK: - CrossRef Search Tool

@available(iOS 19.0, macOS 26.0, *)
struct CrossRefSearchTool: BadgedTool {
    let name = "searchCrossRef"
    let description = "Search CrossRef for DOI metadata, citation counts, and publisher information"
    let tracker: ToolUsageTracker
    let badge = ToolBadge(icon: "link.circle", tint: .gray, label: "CrossRef")

    @Generable
    struct Arguments {
        @Guide(description: "The search query to find published works")
        var searchQuery: String

        @Guide(description: "Maximum number of results to return (default 3)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await tracker.record(badge)
        let limit = arguments.maxResults ?? 3

        do {
            let items = try await searchWorks(query: arguments.searchQuery, limit: limit)

            if items.isEmpty {
                return "CrossRef returned no results for \"\(arguments.searchQuery)\". Try a broader or different search term."
            }

            var output = "CrossRef results for \"\(arguments.searchQuery)\":\n"

            for (index, item) in items.enumerated() {
                let title = item.title.first ?? "Untitled"
                let authors = (item.author ?? []).map { author in
                    [author.given, author.family].compactMap { $0 }.joined(separator: " ")
                }.joined(separator: ", ")
                let year = item.publishedPrint?.dateParts?.first?.first.map(String.init) ?? "Unknown year"
                let abstract: String
                if let rawAbstract = item.abstract {
                    abstract = String(CrossRefHTMLStripper.strip(rawAbstract).prefix(400))
                } else {
                    abstract = "No abstract available."
                }

                output += """

                    \(index + 1). \(title) (\(year))
                    Authors: \(authors.isEmpty ? "Unknown" : authors)
                    Citations: \(item.isReferencedByCount)
                    Abstract: \(abstract)
                    """

                let url = "https://doi.org/\(item.doi)"
                await tracker.addSource(ToolSource(title: title, url: url))
            }

            return output
        } catch {
            return "Could not reach CrossRef. Check your internet connection."
        }
    }

    private func searchWorks(query: String, limit: Int) async throws -> [CrossRefItem] {
        var components = URLComponents(string: "https://api.crossref.org/works")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "rows", value: String(limit)),
            URLQueryItem(name: "select", value: "DOI,title,author,abstract,published-print,is-referenced-by-count"),
        ]

        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Conductor/1.0 (mailto:conductor@example.com)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(CrossRefResponse.self, from: data)
        return response.message.items
    }
}

// MARK: - CrossRef Response Types

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
        case title, author, abstract
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

// MARK: - HTML Tag Stripper

enum CrossRefHTMLStripper {
    static func strip(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
```

- [ ] **Step 4: Add files to Xcode project and run tests**

Add `CrossRefSearchTool.swift` to the Conductor target and `CrossRefTests.swift` to the ConductorTests target. Build and run tests.

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Tools/CrossRefSearchTool.swift ConductorTests/CrossRefTests.swift Conductor.xcodeproj/project.pbxproj
git commit -m "(tools): implement CrossRefSearchTool with HTML stripper"
```

---

### Task 8: Register All Tools and Update System Instructions

**Files:**
- Modify: `Conductor/ContentView.swift` (tool registration and instructions)

- [ ] **Step 1: Update tool registration in `ChatDetailView.init`**

In `Conductor/ContentView.swift`, find the `init(chat:chatManager:)` method. Change the tools array from:

```swift
let tools: [any Tool] = [WikipediaSearchTool(tracker: tracker)]
```

to:

```swift
let tools: [any Tool] = [
    WikipediaSearchTool(tracker: tracker),
    PubMedSearchTool(tracker: tracker),
    SemanticScholarSearchTool(tracker: tracker),
    ArXivSearchTool(tracker: tracker),
    OpenAlexSearchTool(tracker: tracker),
    CrossRefSearchTool(tracker: tracker),
]
```

- [ ] **Step 2: Update system instructions**

Replace the `private static let instructions` string with:

```swift
private static let instructions = """
You are The Conductor — an intelligent intermediary that interprets human intent \
and coordinates device capabilities to fulfill that intent.

Your role is orchestration, not assistance. When given a request:
- Infer the underlying goal, not just the surface request
- Identify what system capabilities are needed to achieve it
- Coordinate actions across multiple functions when necessary
- Explain your reasoning and what you're doing — transparency is non-negotiable

IMPORTANT RULES:
- When you do not know something, ALWAYS search for it using your tools. \
  Do not guess. Do not apologize. Search first.
- If a search fails, tell the user exactly what you searched for and that no results \
  were found. Suggest a different search term.
- Never say "I am unable to provide information." Instead, explain specifically what \
  you tried and why it did not work.
- When answering, synthesize information from search results into a coherent response. \
  Do not dump raw search results.

Available tools — pick the best one for the topic:
- WikipediaSearchTool: General knowledge, overviews, historical context, definitions.
- PubMedSearchTool: Biomedical and clinical research papers. Use for medical, health, \
  biology, pharmacology, and clinical trial questions.
- SemanticScholarSearchTool: Broad academic research across all disciplines. Good default \
  for any scientific question.
- ArXivSearchTool: Cutting-edge preprints in physics, math, computer science, and \
  quantitative biology. Use for the latest research not yet peer-reviewed.
- OpenAlexSearchTool: Broad academic coverage with citation data. Good for understanding \
  how influential a research area is.
- CrossRefSearchTool: DOI metadata, publisher info, citation counts. Use when the user \
  needs specific publication details.

You may use multiple tools in one response when appropriate. For example, use PubMed \
and arXiv together for a biomedical topic to get both published and preprint research.

Core principles:
- Clarity over cleverness: Use direct language. No marketing speak.
- Systems thinking: Consider workflow and coordination, not just single actions.
- Minimal friction: Extend the user's thinking; don't make them operate a tool.
- Technical honesty: Acknowledge your limits specifically — never give vague refusals.
- Privacy: You process locally. The search tools access the internet to retrieve \
  information — be transparent when using them.

When you act, be explicit about what you're doing and why. The user should always \
understand your decision-making process.

You sit between what users want to accomplish and what their device can do. \
The user specifies the outcome; you determine the path.
"""
```

- [ ] **Step 3: Build to verify everything compiles**

Build via XcodeBuildMCP.

Expected: Build succeeds with all 6 tools registered.

- [ ] **Step 4: Commit**

```bash
git add Conductor/ContentView.swift
git commit -m "(chat): register all research tools and update system instructions"
```

---

### Task 9: Integration Smoke Test

**Files:** None created — manual testing

- [ ] **Step 1: Build and run on simulator**

Build and run the app on iOS simulator via XcodeBuildMCP.

- [ ] **Step 2: Test each tool category**

Create new chats and test prompts that should trigger each tool:

1. "What is quantum entanglement?" — should use Wikipedia
2. "Find recent clinical trials on CRISPR gene therapy" — should use PubMed
3. "What are the most cited papers on transformer architectures?" — should use Semantic Scholar or OpenAlex
4. "What are the latest preprints on quantum error correction?" — should use arXiv
5. "Find the DOI and citation count for the original attention paper" — should use CrossRef

For each, verify:
- The tool badge appears on the response
- Source links appear as tappable citations
- The model synthesizes a coherent response (not raw dump)

- [ ] **Step 3: Verify error handling**

Test with a gibberish query like "asdfghjklqwerty" and verify:
- No crash
- Friendly "no results" message appears

- [ ] **Step 4: Commit any fixes needed**

If any issues found during testing, fix and commit.
