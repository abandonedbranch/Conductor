import Foundation
import Testing
@testable import Conductor

@Suite("SemanticScholar Decoding Tests")
struct SemanticScholarTests {

    @Test("Decodes full response with all fields")
    func decodesFullResponse() throws {
        let json = """
        {
            "data": [
                {
                    "title": "Attention Is All You Need",
                    "abstract": "The dominant sequence transduction models are based on complex recurrent or convolutional neural networks.",
                    "authors": [
                        {"name": "Ashish Vaswani"},
                        {"name": "Noam Shazeer"}
                    ],
                    "year": 2017,
                    "citationCount": 90000,
                    "url": "https://www.semanticscholar.org/paper/abc123"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SemanticScholarResponse.self, from: json)

        #expect(response.data.count == 1)

        let paper = response.data[0]
        #expect(paper.title == "Attention Is All You Need")
        #expect(paper.abstract == "The dominant sequence transduction models are based on complex recurrent or convolutional neural networks.")
        #expect(paper.year == 2017)
        #expect(paper.citationCount == 90000)
        #expect(paper.url == "https://www.semanticscholar.org/paper/abc123")

        let authors = try #require(paper.authors)
        #expect(authors.count == 2)
        #expect(authors[0].name == "Ashish Vaswani")
        #expect(authors[1].name == "Noam Shazeer")
    }

    @Test("Decodes response with nil abstract")
    func decodesNilAbstract() throws {
        let json = """
        {
            "data": [
                {
                    "title": "A Paper Without Abstract",
                    "authors": [{"name": "Jane Doe"}],
                    "year": 2020,
                    "citationCount": 5,
                    "url": "https://www.semanticscholar.org/paper/xyz789"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SemanticScholarResponse.self, from: json)

        #expect(response.data.count == 1)

        let paper = response.data[0]
        #expect(paper.title == "A Paper Without Abstract")
        #expect(paper.abstract == nil)
        #expect(paper.year == 2020)
        #expect(paper.citationCount == 5)
    }

    @Test("Decodes empty data array")
    func decodesEmptyData() throws {
        let json = """
        {
            "data": []
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SemanticScholarResponse.self, from: json)
        #expect(response.data.isEmpty)
    }

    @Test("Decodes paper with nil optional fields")
    func decodesNilOptionalFields() throws {
        let json = """
        {
            "data": [
                {
                    "title": "Minimal Paper"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SemanticScholarResponse.self, from: json)

        let paper = response.data[0]
        #expect(paper.title == "Minimal Paper")
        #expect(paper.abstract == nil)
        #expect(paper.authors == nil)
        #expect(paper.year == nil)
        #expect(paper.citationCount == nil)
        #expect(paper.url == nil)
    }
}
