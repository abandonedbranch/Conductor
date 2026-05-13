import Testing
import Foundation
@testable import Conductor

@Suite struct ArxivBackendTests {
    @Test func parsesAtomFeed() async throws {
        let http = FakeHTTPClient()
        let url = URL(string: "https://export.arxiv.org/api/query?search_query=all:transformers&max_results=1")!
        let feed = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>http://arxiv.org/abs/2101.00001</id>
            <title>Attention Is All You Need Again</title>
            <summary>Abstract text.</summary>
          </entry>
        </feed>
        """
        http.scripted[url] = Data(feed.utf8)
        let papers = try await ArxivBackend.search(terms: "transformers", limit: 1, http: http)
        #expect(papers.count == 1)
        #expect(papers[0].title.contains("Attention"))
        #expect(papers[0].identifier.contains("2101.00001"))
    }
}
