import Testing
import Foundation
@testable import Conductor

@Suite struct WikipediaBackendTests {
    @Test func parsesRestSearchJSON() async throws {
        let http = FakeHTTPClient()
        let url = URL(string: "https://en.wikipedia.org/w/rest.php/v1/search/page?q=crispr&limit=2")!
        let payload = #"""
        {
          "pages": [
            {
              "id": 12345,
              "key": "CRISPR",
              "title": "CRISPR",
              "excerpt": "a <span class=\"searchmatch\">gene</span>-editing system",
              "description": "Family of DNA sequences found in prokaryotes"
            },
            {
              "id": 67890,
              "key": "Cas9",
              "title": "Cas9",
              "excerpt": "",
              "description": "CRISPR-associated endonuclease"
            }
          ]
        }
        """#
        http.scripted[url] = Data(payload.utf8)

        let papers = try await WikipediaBackend.search(terms: "crispr", limit: 2, http: http)

        #expect(papers.count == 2)
        #expect(papers[0].title == "CRISPR")
        #expect(papers[0].identifier == "12345")
        #expect(papers[0].abstract == "a gene-editing system")
        #expect(papers[0].url?.absoluteString == "https://en.wikipedia.org/wiki/CRISPR")
        #expect(papers[1].abstract == "CRISPR-associated endonuclease")
    }
}
