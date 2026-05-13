import Foundation

/// Queries the English Wikipedia REST search endpoint and maps each hit to a `Paper`.
///
/// Uses `rest.php/v1/search/page` rather than the older `action=query` interface because the
/// response is already shaped as plain JSON (`title`, `excerpt`, `description`) and needs only
/// minimal HTML stripping — the excerpt wraps matched terms in `<span class="searchmatch">`.
struct WikipediaBackend: SearchBackend {
    static let target = "wikipedia"

    static func search(terms: String, limit: Int, http: any HTTPClient) async throws -> [Paper] {
        let encoded = terms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? terms
        let url = URL(string: "https://en.wikipedia.org/w/rest.php/v1/search/page?q=\(encoded)&limit=\(limit)")!
        let data = try await http.get(url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = root["pages"] as? [[String: Any]] else { return [] }
        return pages.compactMap { entry in
            guard let title = entry["title"] as? String,
                  let id = entry["id"] as? Int else { return nil }
            let excerpt = entry["excerpt"] as? String ?? ""
            let description = entry["description"] as? String ?? ""
            let abstract = stripSearchMatchTags(excerpt).isEmpty ? description : stripSearchMatchTags(excerpt)
            let key = (entry["key"] as? String) ?? title.replacingOccurrences(of: " ", with: "_")
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
            return Paper(
                title: title,
                abstract: abstract,
                identifier: String(id),
                url: URL(string: "https://en.wikipedia.org/wiki/\(encodedKey)")
            )
        }
    }

    /// Removes the `<span class="searchmatch">…</span>` wrappers the REST API adds around matched
    /// terms, leaving the inner text intact. Only these spans appear in `excerpt`, so a regex is
    /// sufficient and avoids pulling in a full HTML parser.
    private static func stripSearchMatchTags(_ html: String) -> String {
        let pattern = #"</?span[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return html
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }
}
