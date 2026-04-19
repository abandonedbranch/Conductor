import Foundation

enum Layer1DataDetector {
    static func extract(from prose: String) -> [AtomRecorded] {
        var out: [AtomRecorded] = []
        let types: NSTextCheckingResult.CheckingType = [.link, .date]
        guard let det = try? NSDataDetector(types: types.rawValue) else { return [] }
        let range = NSRange(prose.startIndex..., in: prose)

        det.enumerateMatches(in: prose, options: [], range: range) { match, _, _ in
            guard let m = match else { return }
            if let url = m.url {
                out.append(AtomRecorded(role: "url", value: .url(url), source: .detector, origin: .compile()))
            }
            if let date = m.date {
                out.append(AtomRecorded(role: "date", value: .date(date), source: .detector, origin: .compile()))
            }
        }

        // Numbers via NSRegularExpression — NSDataDetector doesn't match bare integers reliably.
        let numberRegex = try? NSRegularExpression(pattern: #"\b\d+(\.\d+)?\b"#)
        numberRegex?.enumerateMatches(in: prose, options: [], range: range) { match, _, _ in
            guard let m = match, let range = Range(m.range, in: prose) else { return }
            let token = String(prose[range])
            guard let value = Double(token) else { return }
            if let role = numberRole(for: token, at: range, in: prose) {
                out.append(AtomRecorded(role: role, value: .number(value), source: .detector, origin: .compile()))
            }
        }

        return out
    }

    /// Walks backward from the number to the nearest verb lemma. If the nearest catalog verb
    /// declares a `.number` parameter, the role is that parameter's role; otherwise `nil`
    /// (the atom is dropped — let auto-ask handle it).
    private static func numberRole(for token: String, at range: Range<String.Index>, in prose: String) -> String? {
        let prefix = prose[..<range.lowerBound]
        let words = prefix.split(whereSeparator: { !$0.isLetter }).map { String($0).lowercased() }
        for word in words.reversed() {
            if let verb = VerbCatalog.verb(forLemma: word) {
                let numberParam = VerbCatalog.definition(for: verb).parameters.first { p in
                    if case .number = p.kind { return true } else { return false }
                }
                return numberParam?.role
            }
        }
        return nil
    }
}
