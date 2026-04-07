import Foundation
import Testing
@testable import Conductor

@Suite("OpenAlex Tests")
struct OpenAlexTests {

    // MARK: - Abstract Reconstruction

    @Test("Reconstruct abstract from inverted index")
    func reconstructAbstract() {
        let invertedIndex: [String: [Int]] = [
            "The": [0],
            "quick": [1],
            "brown": [2],
            "fox": [3],
            "jumps": [4],
        ]
        let result = OpenAlexAbstractReconstructor.reconstruct(from: invertedIndex)
        #expect(result == "The quick brown fox jumps")
    }

    @Test("Reconstruct empty inverted index returns empty string")
    func reconstructEmptyInvertedIndex() {
        let result = OpenAlexAbstractReconstructor.reconstruct(from: [:])
        #expect(result == "")
    }

    // MARK: - JSON Decoding

    @Test("Decode full work response with all fields")
    func decodeFullWorkResponse() throws {
        let json = """
        {
            "results": [
                {
                    "id": "https://openalex.org/W1234567890",
                    "doi": "https://doi.org/10.1234/example",
                    "title": "A Study of Swift Concurrency",
                    "publication_year": 2023,
                    "cited_by_count": 42,
                    "authorships": [
                        {
                            "author": {
                                "display_name": "Jane Doe"
                            }
                        },
                        {
                            "author": {
                                "display_name": "John Smith"
                            }
                        }
                    ],
                    "abstract_inverted_index": {
                        "Swift": [0],
                        "concurrency": [1],
                        "is": [2],
                        "powerful": [3]
                    }
                }
            ]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(OpenAlexResponse.self, from: data)

        #expect(response.results.count == 1)

        let work = try #require(response.results.first)
        #expect(work.id == "https://openalex.org/W1234567890")
        #expect(work.doi == "https://doi.org/10.1234/example")
        #expect(work.title == "A Study of Swift Concurrency")
        #expect(work.publicationYear == 2023)
        #expect(work.citedByCount == 42)
        #expect(work.authorships.count == 2)
        #expect(work.authorships[0].author.displayName == "Jane Doe")
        #expect(work.authorships[1].author.displayName == "John Smith")

        let abstract = try #require(work.abstractInvertedIndex)
        let reconstructed = OpenAlexAbstractReconstructor.reconstruct(from: abstract)
        #expect(reconstructed == "Swift concurrency is powerful")
    }

    @Test("Decode work with nil abstract_inverted_index")
    func decodeWorkWithNilAbstract() throws {
        let json = """
        {
            "results": [
                {
                    "id": "https://openalex.org/W9876543210",
                    "doi": null,
                    "title": "No Abstract Paper",
                    "publication_year": null,
                    "cited_by_count": 0,
                    "authorships": [],
                    "abstract_inverted_index": null
                }
            ]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(OpenAlexResponse.self, from: data)

        let work = try #require(response.results.first)
        #expect(work.abstractInvertedIndex == nil)
        #expect(work.doi == nil)
        #expect(work.publicationYear == nil)
        #expect(work.authorships.isEmpty)
    }
}
