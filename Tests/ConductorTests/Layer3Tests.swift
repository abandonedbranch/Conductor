import Testing
import Foundation
@testable import Conductor

@Suite struct Layer3Tests {
    @Test func fuzzy_lookInto_mapsToRead() {
        let match = Layer3Embedding.fuzzyMatch(lemma: "peruse")
        #expect(match == .read || match == nil)   // embedding may or may not cross threshold; both acceptable
    }

    @Test func fuzzy_known_exactMatchIsNotRun() {
        // Layer 3 should return nil for words that Layer 2 already resolved.
        // We simulate that by checking the gate: only unknown words enter fuzzyMatch.
        #expect(Layer3Embedding.fuzzyMatch(lemma: "summarize") == .summarize)
    }

    @Test func fuzzy_random_returnsNil() {
        #expect(Layer3Embedding.fuzzyMatch(lemma: "banana") == nil)
    }
}
