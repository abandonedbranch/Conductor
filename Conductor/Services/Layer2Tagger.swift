import Foundation
import NaturalLanguage

struct Layer2Result: Sendable {
    let verbs: [Verb]
    let atoms: [AtomRecorded]
}

enum Layer2Tagger {
    static func extract(from prose: String) -> Layer2Result {
        let (verbs, _) = verbsAndPositions(in: prose)
        let atoms = nounPhraseAtoms(in: prose, verbPositions: []) + aliasAtoms(in: prose)
        return Layer2Result(verbs: verbs, atoms: atoms)
    }

    static func verbsAndPositions(in prose: String) -> ([Verb], [(Verb, Range<String.Index>)]) {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = prose
        var verbs: [Verb] = []
        var positions: [(Verb, Range<String.Index>)] = []
        let opts: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        tagger.enumerateTags(in: prose.startIndex..<prose.endIndex, unit: .word, scheme: .lexicalClass, options: opts) { tag, range in
            guard tag == .verb else { return true }
            let lemmaTag = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0
            let token = (lemmaTag?.rawValue ?? String(prose[range])).lowercased()
            if let v = VerbCatalog.verb(forLemma: token) {
                verbs.append(v)
                positions.append((v, range))
            }
            return true
        }
        return (verbs, positions)
    }

    static func nounPhraseAtoms(in prose: String, verbPositions: [(Verb, Range<String.Index>)]) -> [AtomRecorded] {
        // Implemented in Task 14
        []
    }

    static func aliasAtoms(in prose: String) -> [AtomRecorded] {
        // Implemented in Task 15
        []
    }
}
