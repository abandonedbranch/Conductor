import Foundation
import Testing
@testable import Conductor

@Suite("Atom")
struct AtomTests {
    @Test("Success atom round-trips through Codable")
    func successCodable() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        let atom: Atom = .success(
            content: "hello",
            source: URL(string: "https://example.com"),
            toolName: "Wikipedia",
            timestamp: timestamp
        )
        let data = try JSONEncoder().encode(atom)
        let decoded = try JSONDecoder().decode(Atom.self, from: data)
        if case let .success(content, source, toolName, ts) = decoded {
            #expect(content == "hello")
            #expect(source?.absoluteString == "https://example.com")
            #expect(toolName == "Wikipedia")
            #expect(ts == timestamp)
        } else {
            Issue.record("expected .success atom")
        }
    }

    @Test("ErrorAtom round-trips")
    func errorCodable() throws {
        let err = ErrorAtom(
            actionID: UUID(),
            toolName: "PubMed",
            kind: .timeout,
            message: "slow",
            timestamp: .now
        )
        let data = try JSONEncoder().encode(err)
        let decoded = try JSONDecoder().decode(ErrorAtom.self, from: data)
        #expect(decoded.kind == .timeout)
        #expect(decoded.message == "slow")
    }

    @Test("ErrorKind has the seed set")
    func errorKindCases() {
        #expect(ErrorKind.allCases.count == 5)
    }
}
