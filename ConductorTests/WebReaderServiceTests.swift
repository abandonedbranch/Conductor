import Foundation
import Testing
@testable import Conductor

@Suite("WebReaderService Tests", .serialized)
struct WebReaderServiceTests {

    @Test("parseExtraction decodes valid JSON")
    func parseExtractionValid() throws {
        let json = """
        {"title":"Example Domain","text":"This domain is for use in illustrative examples."}
        """
        let result = try WebReaderService.parseExtraction(json)
        #expect(result.title == "Example Domain")
        #expect(result.text == "This domain is for use in illustrative examples.")
    }

    @Test("parseExtraction throws on invalid JSON")
    func parseExtractionInvalid() {
        #expect(throws: (any Error).self) {
            try WebReaderService.parseExtraction("not json")
        }
    }

    @Test("parseExtraction handles empty title")
    func parseExtractionEmptyTitle() throws {
        let json = """
        {"title":"","text":"Some body text."}
        """
        let result = try WebReaderService.parseExtraction(json)
        #expect(result.title.isEmpty)
        #expect(result.text == "Some body text.")
    }

    @Test("extractionScript is deterministic")
    func extractionScriptIsDeterministic() {
        let a = WebReaderService.extractionScript
        let b = WebReaderService.extractionScript
        #expect(a == b)
    }
}
