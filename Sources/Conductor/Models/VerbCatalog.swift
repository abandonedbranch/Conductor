import Foundation

enum VerbCatalog {
    static func definition(for verb: Verb) -> any VerbDefinition.Type {
        switch verb {
        case .read: ReadVerb.self
        case .summarize: SummarizeVerb.self
        case .search: SearchVerb.self
        case .extractClaims: ExtractClaimsVerb.self
        }
    }

    static func verb(forLemma lemma: String) -> Verb? {
        let needle = lemma.lowercased()
        for v in Verb.allCases {
            if definition(for: v).lemmas.contains(needle) { return v }
        }
        return nil
    }

    static var all: [Verb] { Verb.allCases }
}
