import Foundation
import Testing
@testable import Conductor

@Suite("CrossRef Tests")
struct CrossRefTests {

    // MARK: - HTML Stripping

    @Test("Strip JATS XML tags from abstract")
    func stripJATSTags() {
        let input = "<jats:p>This is a <jats:italic>test</jats:italic> of HTML <jats:bold>stripping</jats:bold>.</jats:p>"
        let expected = "This is a test of HTML stripping."
        #expect(CrossRefHTMLStripper.strip(input) == expected)
    }

    @Test("Plain text passes through unchanged")
    func plainTextPassthrough() {
        let input = "No tags here, just plain text."
        #expect(CrossRefHTMLStripper.strip(input) == input)
    }

    // MARK: - Decoding

    @Test("Decode full CrossRef response with all fields")
    func decodeFullResponse() throws {
        let json = """
        {
            "message": {
                "items": [
                    {
                        "DOI": "10.1000/xyz123",
                        "title": ["An Interesting Paper"],
                        "author": [
                            {"given": "Alice", "family": "Smith"},
                            {"given": "Bob", "family": "Jones"}
                        ],
                        "abstract": "<jats:p>This is the abstract.</jats:p>",
                        "published-print": {
                            "date-parts": [[2023, 4, 15]]
                        },
                        "is-referenced-by-count": 42
                    }
                ]
            }
        }
        """

        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(CrossRefResponse.self, from: data)
        let item = try #require(response.message.items.first)

        #expect(item.doi == "10.1000/xyz123")
        #expect(item.title.first == "An Interesting Paper")
        #expect(item.author?.count == 2)
        #expect(item.author?.first?.given == "Alice")
        #expect(item.author?.first?.family == "Smith")
        #expect(item.abstract == "<jats:p>This is the abstract.</jats:p>")
        #expect(item.publishedPrint?.dateParts?.first?.first == 2023)
        #expect(item.isReferencedByCount == 42)
    }

    @Test("Decode item with missing optional fields")
    func decodeMissingOptionalFields() throws {
        let json = """
        {
            "message": {
                "items": [
                    {
                        "DOI": "10.9999/minimal",
                        "title": ["Minimal Paper"],
                        "is-referenced-by-count": 0
                    }
                ]
            }
        }
        """

        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(CrossRefResponse.self, from: data)
        let item = try #require(response.message.items.first)

        #expect(item.doi == "10.9999/minimal")
        #expect(item.title.first == "Minimal Paper")
        #expect(item.author == nil)
        #expect(item.abstract == nil)
        #expect(item.publishedPrint == nil)
        #expect(item.isReferencedByCount == 0)
    }
}
