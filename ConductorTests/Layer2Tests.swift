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
