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
        let id = UUID()
        let ts = Date(timeIntervalSince1970: 500)
        let err = ErrorAtom(
            actionID: id,
            toolName: "PubMed",
            kind: .timeout,
            message: "slow",
            timestamp: ts
        )
        let data = try JSONEncoder().encode(err)
        let decoded = try JSONDecoder().decode(ErrorAtom.self, from: data)
        #expect(decoded.actionID == id)
        #expect(decoded.toolName == "PubMed")
        #expect(decoded.kind == .timeout)
        #expect(decoded.message == "slow")
        #expect(decoded.timestamp == ts)
    }

    @Test("Error-wrapped atom round-trips through Codable")
    func errorAtomWrapped() throws {
        let id = UUID()
        let err = ErrorAtom(
            actionID: id,
            toolName: nil,
            kind: .unknown,
            message: "x",
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let atom: Atom = .error(err)
        let data = try JSONEncoder().encode(atom)
        let decoded = try JSONDecoder().decode(Atom.self, from: data)
        guard case let .error(e) = decoded else {
            Issue.record("expected .error atom")
            return
        }
        #expect(e.actionID == id)
        #expect(e.toolName == nil)
        #expect(e.kind == .unknown)
        #expect(e.message == "x")
    }

    @Test("Note atom round-trips through Codable")
    func noteCodable() throws {
        let ts = Date(timeIntervalSince1970: 2000)
        let atom: Atom = .note(text: "memo", timestamp: ts)
        let data = try JSONEncoder().encode(atom)
        let decoded = try JSONDecoder().decode(Atom.self, from: data)
        guard case let .note(text, decodedTs) = decoded else {
            Issue.record("expected .note atom")
            return
        }
        #expect(text == "memo")
        #expect(decodedTs == ts)
    }

    @Test("ErrorKind has the seed set")
    func errorKindCases() {
        #expect(ErrorKind.allCases.count == 5)
    }
}
