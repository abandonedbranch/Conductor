import Foundation

struct WebBackend: SearchBackend {
    static let target = "web"

    static func search(terms: String, limit: Int, http: any HTTPClient) async throws -> [Paper] {
        let encoded = terms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? terms
        let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&no_redirect=1")!
        let data = try await http.get(url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let topics = root["RelatedTopics"] as? [[String: Any]] else { return [] }
        return topics.prefix(limit).enumerated().map { idx, entry in
            let text = entry["Text"] as? String ?? ""
            let u = (entry["FirstURL"] as? String).flatMap { URL(string: $0) }
            let title = text.components(separatedBy: " — ").first ?? text
            return Paper(title: title, abstract: text, identifier: "ddg-\(idx)", url: u)
        }
    }
}
