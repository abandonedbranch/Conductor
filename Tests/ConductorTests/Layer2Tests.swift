import Testing
import Foundation
@testable import Conductor

@Suite struct Layer2VerbTests {
    @Test func findsSummarizeAndSearch() {
        let r = Layer2Tagger.extract(from: "Summarize the article and find papers")
        #expect(r.verbs == [.summarize, .search])
    }

    @Test func lemmatizes_summarized_to_summarize() {
        let r = Layer2Tagger.extract(from: "I summarized it")
        #expect(r.verbs == [.summarize])
    }

    @Test func verbsAppearInSentenceOrder() {
        let r = Layer2Tagger.extract(from: "Find 3 papers then summarize them")
        #expect(r.verbs == [.search, .summarize])
    }
}

@Suite struct Layer2NPTests {
    @Test func extractsSearchTermsAdjacentToFind() {
        let r = Layer2Tagger.extract(from: "find papers about CRISPR and sickle-cell")
        let terms = r.atoms.first { $0.role == "search.terms" }
        if case let .text(t) = terms?.value { #expect(t.localizedCaseInsensitiveContains("CRISPR")) } else { Issue.record("no terms") }
    }

    @Test func nounPhraseIsNearestToMatchedVerb() {
        // "summarize the article and find recent work" → `summarize` has no declared NP param,
        // `search.terms` goes with `find` / `search`. The NP nearest `find` wins.
        let r = Layer2Tagger.extract(from: "summarize the article and find recent work")
        let terms = r.atoms.first { $0.role == "search.terms" }
        if case let .text(t) = terms?.value { #expect(t.localizedCaseInsensitiveContains("work")) }
    }
}

@Suite struct Layer2AliasTests {
    @Test func pubmedTokenMatchesSearchTarget() {
        let r = Layer2Tagger.extract(from: "find 3 PubMed papers")
        let target = r.atoms.first { $0.role == "search.target" }
        if case let .choice(_, v) = target?.value { #expect(v == "pubMed") } else { Issue.record("no target") }
    }

    @Test func arxivOrgTokenMatchesSearchTarget() {
        let r = Layer2Tagger.extract(from: "search arxiv.org for transformers")
        let target = r.atoms.first { $0.role == "search.target" }
        if case let .choice(_, v) = target?.value { #expect(v == "arxiv") }
    }

    @Test func missingTargetProducesNoAtom() {
        let r = Layer2Tagger.extract(from: "find 3 papers")
        #expect(r.atoms.first { $0.role == "search.target" } == nil)
    }
}
