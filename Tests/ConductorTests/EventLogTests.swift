import Testing
import Foundation
@testable import Conductor

@MainActor
@Suite struct EventLogTests {
    @Test func append_growsLog() {
        let log = EventLog()
        #expect(log.events.isEmpty)
        log.append(AtomRecorded(role: "url", value: .url(URL(string: "https://x")!), source: .detector, origin: .compile()))
        #expect(log.events.count == 1)
    }

    @Test func append_preservesOrder() {
        let log = EventLog()
        log.append(AtomRecorded(role: "a", value: .text("1"), source: .tagger, origin: .compile()))
        log.append(AtomRecorded(role: "b", value: .text("2"), source: .tagger, origin: .compile()))
        #expect((log.events[0] as? AtomRecorded)?.role == "a")
        #expect((log.events[1] as? AtomRecorded)?.role == "b")
    }

    @Test func findAtom_byRole_returnsLatest() {
        let log = EventLog()
        log.append(AtomRecorded(role: "search.target", value: .choice(namespace: "search.target", value: "pubMed"), source: .tagger, origin: .compile()))
        log.append(AtomRecorded(role: "search.target", value: .choice(namespace: "search.target", value: "arxiv"), source: .userAsked, origin: .compile()))
        let found = log.latestAtom(role: "search.target")
        if case let .choice(_, v) = found?.value { #expect(v == "arxiv") } else { Issue.record("no atom") }
    }
}
