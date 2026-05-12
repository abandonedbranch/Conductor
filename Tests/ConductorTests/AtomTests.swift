import Testing
import Foundation
@testable import Conductor

@Suite struct AtomTests {
    @Test func atomValue_urlCaseCarriesURL() throws {
        let url = URL(string: "https://example.com")!
        let v: AtomValue = .url(url)
        if case let .url(u) = v { #expect(u == url) } else { Issue.record("wrong case") }
    }

    @Test func atomValue_choiceCarriesNamespaceAndValue() {
        let v: AtomValue = .choice(namespace: "search.target", value: "pubMed")
        if case let .choice(ns, val) = v {
            #expect(ns == "search.target")
            #expect(val == "pubMed")
        } else { Issue.record("wrong case") }
    }

    @Test func atomKind_choiceListsCases() {
        let k: AtomKind = .choice(namespace: "search.target", cases: ["pubMed", "arxiv", "web"])
        if case let .choice(_, cases) = k { #expect(cases.count == 3) } else { Issue.record("wrong case") }
    }

    @Test func atomSource_fiveCases() {
        let all: [AtomSource] = [.detector, .tagger, .embedding, .llm, .userAsked]
        #expect(all.count == 5)
    }
}

@Suite struct AtomRecordedTests {
    @Test func recorded_exposesRoleValueSourceOrigin() {
        let e = AtomRecorded(
            role: "search.target",
            value: .choice(namespace: "search.target", value: "pubMed"),
            source: .tagger,
            origin: .compile()
        )
        #expect(e.role == "search.target")
        #expect(e.source == .tagger)
        #expect(e.origin.stepID == nil)
    }
}
