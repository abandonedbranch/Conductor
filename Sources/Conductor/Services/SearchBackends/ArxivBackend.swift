import Foundation

struct ArxivBackend: SearchBackend {
    static let target = "arxiv"

    static func search(terms: String, limit: Int, http: any HTTPClient) async throws -> [Paper] {
        let encoded = terms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? terms
        let url = URL(string: "https://export.arxiv.org/api/query?search_query=all:\(encoded)&max_results=\(limit)")!
        let data = try await http.get(url)
        let parser = ArxivParser()
        return parser.parse(data: data)
    }
}

private final class ArxivParser: NSObject, XMLParserDelegate {
    private var papers: [Paper] = []
    private var current: [String: String] = [:]
    private var inEntry = false
    private var text = ""

    func parse(data: Data) -> [Paper] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return papers
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "entry" { inEntry = true; current = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if inEntry && ["id", "title", "summary"].contains(elementName) {
            current[elementName] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if elementName == "entry" {
            inEntry = false
            let id = current["id"] ?? ""
            papers.append(Paper(
                title: current["title"] ?? "",
                abstract: current["summary"] ?? "",
                identifier: id.components(separatedBy: "/").last ?? id,
                url: URL(string: id)
            ))
        }
    }
}
