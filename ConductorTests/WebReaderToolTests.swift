import Foundation
import Testing
@testable import Conductor

@Suite("WebReaderTool Tests", .serialized)
struct WebReaderToolTests {

    @Test("validateURL rejects malformed input")
    @available(iOS 19.0, macOS 26.0, *)
    func rejectsMalformed() {
        let result = WebReaderTool.validateURL("not a url")
        switch result {
        case .failure(let error):
            if case .invalidURL = error {
                // pass
            } else {
                Issue.record("Expected invalidURL, got \(error)")
            }
        case .success:
            Issue.record("Expected failure")
        }
    }

    @Test("validateURL rejects http")
    @available(iOS 19.0, macOS 26.0, *)
    func rejectsHTTP() {
        let result = WebReaderTool.validateURL("http://example.com")
        switch result {
        case .failure(let error):
            if case .insecureURL = error {
                // pass
            } else {
                Issue.record("Expected insecureURL, got \(error)")
            }
        case .success:
            Issue.record("Expected failure")
        }
    }

    @Test("validateURL accepts https")
    @available(iOS 19.0, macOS 26.0, *)
    func acceptsHTTPS() {
        let result = WebReaderTool.validateURL("https://example.com")
        switch result {
        case .success(let url):
            #expect(url.scheme == "https")
        case .failure:
            Issue.record("Expected success")
        }
    }
}
