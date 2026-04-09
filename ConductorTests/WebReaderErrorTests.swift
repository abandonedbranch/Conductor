import Foundation
import Testing
@testable import Conductor

@Suite("WebReaderError Tests", .serialized)
struct WebReaderErrorTests {

    @Test("invalidURL carries the original string")
    func invalidURLCarriesString() {
        let error = WebReaderError.invalidURL("not a url")
        if case .invalidURL(let raw) = error {
            #expect(raw == "not a url")
        } else {
            Issue.record("Expected invalidURL")
        }
    }

    @Test("insecureURL rejects http scheme")
    func insecureURLRejectsHTTP() {
        let url = URL(string: "http://example.com")!
        let error = WebReaderError.insecureURL(url)
        if case .insecureURL(let rejected) = error {
            #expect(rejected.scheme == "http")
        } else {
            Issue.record("Expected insecureURL")
        }
    }

    @Test("validate rejects malformed strings")
    func validateRejectsMalformed() {
        let result = WebReaderError.validate(urlString: "not a url")
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

    @Test("validate rejects http URLs")
    func validateRejectsHTTP() {
        let result = WebReaderError.validate(urlString: "http://example.com")
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

    @Test("validate accepts https URLs")
    func validateAcceptsHTTPS() {
        let result = WebReaderError.validate(urlString: "https://example.com")
        switch result {
        case .success(let url):
            #expect(url.scheme == "https")
        case .failure(let error):
            Issue.record("Expected success, got \(error)")
        }
    }
}
