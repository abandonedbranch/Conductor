import Testing
import Foundation
@testable import Conductor

@Suite struct VerbCatalogTests {
    @Test func everyEnumCaseHasADefinition() {
        for verb in Verb.allCases {
            let def = VerbCatalog.definition(for: verb)
            #expect(def.verb == verb)
        }
    }

    @Test func lemmaLookup_findsVerbByLemma() {
        #expect(VerbCatalog.verb(forLemma: "summarize") == .summarize)
        #expect(VerbCatalog.verb(forLemma: "find") == .search)
        #expect(VerbCatalog.verb(forLemma: "unicorn") == nil)
    }
}
