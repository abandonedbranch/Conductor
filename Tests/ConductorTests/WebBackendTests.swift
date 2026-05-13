import Testing
import Foundation
@testable import Conductor

@Suite struct WebBackendTests {
    @Test func parsesDuckDuckGoJSON() async throws {
        let http = FakeHTTPClient()
        let url = URL(string: "https://api.duckduckgo.com/?q=crispr&format=json&no_html=1&no_redirect=1")!
        let payload = #"""
        {
          "RelatedTopics": [
            {"Text": "CRISPR — a gene-editing system", "FirstURL": "https://duckduckgo.com/CRISPR"},
            {"Text": "Cas9", "FirstURL": "https://duckduckgo.com/Cas9"}
          ]
        }
        """#
        http.scripted[url] = Data(payload.utf8)
        let papers = try await WebBackend.search(terms: "crispr", limit: 2, http: http)
        #expect(papers.count == 2)
        #expect(papers[0].title.contains("CRISPR"))
    }
}
