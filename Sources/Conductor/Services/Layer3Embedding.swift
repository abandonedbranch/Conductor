import Foundation
import NaturalLanguage

enum Layer3Embedding {
    static let threshold: Double = 0.65

    static func fuzzyMatch(lemma: String) -> Verb? {
        if let direct = VerbCatalog.verb(forLemma: lemma) { return direct }
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return nil }
        guard embedding.contains(lemma) else { return nil }

        var best: (Verb, Double)?
        for verb in Verb.allCases {
            for catalogLemma in VerbCatalog.definition(for: verb).lemmas {
                guard embedding.contains(catalogLemma) else { continue }
                let d = embedding.distance(between: lemma, and: catalogLemma)
                let similarity = 1.0 - d
                if similarity >= threshold, similarity > (best?.1 ?? threshold) {
                    best = (verb, similarity)
                }
            }
        }
        return best?.0
    }
}
