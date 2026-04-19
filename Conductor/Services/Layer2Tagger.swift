import Foundation
import NaturalLanguage

struct Layer2Result: Sendable {
    let verbs: [Verb]
    let atoms: [AtomRecorded]
}

enum Layer2Tagger {
    static func extract(from prose: String) -> Layer2Result {
        let (verbs, positions) = verbsAndPositions(in: prose)
        let npAtoms = nounPhraseAtoms(in: prose, verbPositions: positions)
        // "about X" phrases are a reliable signal for search topics; prefer them over
        // the nearest bare NP when the search verb is present.
        let aboutAtoms = aboutPhraseAtoms(in: prose, verbs: verbs)
        // aboutAtoms override npAtoms for the same roles — union with aboutAtoms last
        // so the runtime (which uses latestAtom) picks them up.
        let atoms = npAtoms + aliasAtoms(in: prose) + aboutAtoms
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
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = prose
        let opts: NLTagger.Options = [.omitWhitespace]
        var phrases: [(text: String, range: Range<String.Index>)] = []
        var current: (text: String, start: String.Index, end: String.Index)?

        tagger.enumerateTags(in: prose.startIndex..<prose.endIndex, unit: .word, scheme: .lexicalClass, options: opts) { tag, range in
            let piece = String(prose[range])
            if tag == .noun || tag == .adjective {
                if var c = current {
                    c.text += " " + piece
                    c.end = range.upperBound
                    current = c
                } else {
                    current = (piece, range.lowerBound, range.upperBound)
                }
            } else if tag == .determiner || tag == .preposition {
                if var c = current {
                    c.text += " " + piece
                    c.end = range.upperBound
                    current = c
                }
            } else {
                if let c = current {
                    phrases.append((c.text, c.start..<c.end))
                    current = nil
                }
            }
            return true
        }
        if let c = current { phrases.append((c.text, c.start..<c.end)) }

        var out: [AtomRecorded] = []
        for (verb, verbRange) in verbPositions {
            let params = VerbCatalog.definition(for: verb).parameters.filter { if case .text = $0.kind { return true } else { return false } }
            for param in params {
                let nearest = phrases.min { a, b in
                    distance(from: a.range, to: verbRange, in: prose) < distance(from: b.range, to: verbRange, in: prose)
                }
                if let np = nearest {
                    out.append(AtomRecorded(role: param.role, value: .text(np.text), source: .tagger, origin: .compile()))
                }
            }
        }
        return out
    }

    private static func distance(from a: Range<String.Index>, to b: Range<String.Index>, in prose: String) -> Int {
        let aMid = prose.distance(from: prose.startIndex, to: a.lowerBound) + prose.distance(from: a.lowerBound, to: a.upperBound) / 2
        let bMid = prose.distance(from: prose.startIndex, to: b.lowerBound) + prose.distance(from: b.lowerBound, to: b.upperBound) / 2
        return abs(aMid - bMid)
    }

    /// Extracts topic phrases introduced by "about X" when a search verb is present.
    /// English search sentences frequently state the topic as "about <topic>" before
    /// the search verb, which is more reliable than the nearest bare noun phrase.
    static func aboutPhraseAtoms(in prose: String, verbs: [Verb]) -> [AtomRecorded] {
        guard verbs.contains(.search) else { return [] }
        // Match "about <topic>" where <topic> runs until a hard clause boundary
        // (comma, semicolon, or end-of-string). We intentionally do NOT stop at
        // "and <noun>" so that "CRISPR and sickle-cell" is captured whole.
        guard let regex = try? NSRegularExpression(
            pattern: #"\babout\s+([\w][\w\s-]*?)(?=\s*[,;]|\s*$)"#,
            options: .caseInsensitive
        ) else { return [] }
        let range = NSRange(prose.startIndex..., in: prose)
        var out: [AtomRecorded] = []
        regex.enumerateMatches(in: prose, options: [], range: range) { match, _, _ in
            guard let m = match, let captureRange = Range(m.range(at: 1), in: prose) else { return }
            let topic = String(prose[captureRange]).trimmingCharacters(in: .whitespaces)
            guard !topic.isEmpty else { return }
            out.append(AtomRecorded(role: "search.terms", value: .text(topic), source: .tagger, origin: .compile()))
        }
        return out
    }

    static func aliasAtoms(in prose: String) -> [AtomRecorded] {
        var out: [AtomRecorded] = []
        let lower = prose.lowercased()
        for verb in Verb.allCases {
            let params = VerbCatalog.definition(for: verb).parameters
            for param in params {
                guard case let .choice(namespace, _) = param.kind else { continue }
                for (alias, canonical) in param.aliases {
                    if lower.contains(alias) {
                        out.append(AtomRecorded(
                            role: param.role,
                            value: .choice(namespace: namespace, value: canonical),
                            source: .tagger,
                            origin: .compile()
                        ))
                        break
                    }
                }
            }
        }
        return out
    }
}
