import Foundation

struct PubMedBackend: SearchBackend {
    static let target = "pubMed"

    static func search(terms: String, limit: Int, http: any HTTPClient) async throws -> [Paper] {
        let termsEncoded = terms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? terms
        let searchURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=\(termsEncoded)&retmax=\(limit)&retmode=json")!
        let searchData = try await http.get(searchURL)
        let idList = try parseIDs(searchData)
        guard !idList.isEmpty else { return [] }
        let ids = idList.joined(separator: ",")
        let summaryURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=\(ids)&retmode=json")!
        let summaryData = try await http.get(summaryURL)
        return try parseSummaries(summaryData, ids: idList)
    }

    private static func parseIDs(_ data: Data) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let er = root["esearchresult"] as? [String: Any],
              let ids = er["idlist"] as? [String] else { return [] }
        return ids
    }

    private static func parseSummaries(_ data: Data, ids: [String]) throws -> [Paper] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else { return [] }
        return ids.compactMap { id -> Paper? in
            guard let entry = result[id] as? [String: Any] else { return nil }
            let title = entry["title"] as? String ?? "(untitled)"
            let abstract = entry["abstract"] as? String ?? ""
            return Paper(title: title, abstract: abstract, identifier: id, url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(id)/"))
        }
    }
}
