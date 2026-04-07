import Foundation
import Testing
@testable import Conductor

@Suite("ArXiv Tests")
struct ArXivTests {

    // MARK: - Sample Atom XML

    private static let twoEntryFeed = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>ArXiv Query</title>
          <entry>
            <id>https://arxiv.org/abs/2301.12345v1</id>
            <title>Attention Is All
        You Need</title>
            <summary>We propose a new
        simple network architecture, the Transformer.</summary>
            <author><name>Alice Smith</name></author>
            <author><name>Bob Jones</name></author>
          </entry>
          <entry>
            <id>https://arxiv.org/abs/1706.99999v2</id>
            <title>Deep Residual
        Learning</title>
            <summary>We present a residual learning
        framework.</summary>
            <author><name>Carol White</name></author>
          </entry>
        </feed>
        """.data(using: .utf8)!

    private static let emptyFeed = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>ArXiv Query</title>
        </feed>
        """.data(using: .utf8)!

    // MARK: - Tests

    @Test("Parses two entries with correct titles, summaries, IDs, and authors")
    func parseTwoEntries() {
        let entries = ArXivXMLParser.parse(data: ArXivTests.twoEntryFeed)

        #expect(entries.count == 2)

        let first = entries[0]
        #expect(first.id == "https://arxiv.org/abs/2301.12345v1")
        #expect(first.title == "Attention Is All You Need")
        #expect(first.summary == "We propose a new simple network architecture, the Transformer.")
        #expect(first.authors == "Alice Smith, Bob Jones")

        let second = entries[1]
        #expect(second.id == "https://arxiv.org/abs/1706.99999v2")
        #expect(second.title == "Deep Residual Learning")
        #expect(second.summary == "We present a residual learning framework.")
        #expect(second.authors == "Carol White")
    }

    @Test("Returns empty array for feed with no entries")
    func parseEmptyFeed() {
        let entries = ArXivXMLParser.parse(data: ArXivTests.emptyFeed)
        #expect(entries.isEmpty)
    }
}
