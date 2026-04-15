@available(iOS 19.0, macOS 26.0, *)
func deterministicSearch<T: AffordanceBearing>(
    intent: LanguageIntentQuery,
    intentSubjects: [IntentSubject],
    pool: [T],
    cap: Int
) -> [T] {
    let intentVerbs = Set(intent.verbs)
    let intentSubjectSet = Set(intentSubjects)

    return pool
        .compactMap { item -> (T, Int)? in
            let aff = item.affordance
            let sharedVerbs = aff.verbs.intersection(intentVerbs)
            guard !sharedVerbs.isEmpty else { return nil }
            guard aff.answerShapes.contains(intent.answerShape) else { return nil }
            if !intentSubjectSet.isEmpty {
                guard !aff.subjects.intersection(intentSubjectSet).isEmpty else { return nil }
            }
            let sharedSubjects = aff.subjects.intersection(intentSubjectSet)
            let score = aff.priority * 100 + sharedVerbs.count + sharedSubjects.count
            return (item, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(cap)
        .map(\.0)
}
