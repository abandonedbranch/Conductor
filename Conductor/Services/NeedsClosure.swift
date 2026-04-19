import Foundation

enum NeedsClosure {
    static func inflate(verbs: [Verb], existingLog: [any Event]) -> [Verb] {
        var output: [Verb] = []
        for verb in verbs {
            try? insert(verb: verb, into: &output, existingLog: existingLog)
        }
        return output
    }

    private static func insert(verb: Verb, into pipeline: inout [Verb], existingLog: [any Event]) throws {
        let def = VerbCatalog.definition(for: verb)
        for need in def.needs where need.required {
            let satisfiedByLog = existingLog.contains { evt in need.eventTypeNames.contains(typeName(evt)) }
            let satisfiedByPipeline = pipeline.contains { v in
                need.eventTypeNames.contains { emittedType(by: v)?.contains($0) ?? false }
            }
            if satisfiedByLog || satisfiedByPipeline { continue }
            guard let producer = producerVerb(forAny: need.eventTypeNames) else {
                throw NSError(domain: "closure", code: 1)
            }
            try insert(verb: producer, into: &pipeline, existingLog: existingLog)
        }
        if !pipeline.contains(verb) { pipeline.append(verb) }
    }

    private static func typeName(_ event: any Event) -> String {
        String(describing: type(of: event))
    }

    private static func emittedType(by verb: Verb) -> [String]? {
        switch verb {
        case .read: ["ReadCompleted"]
        case .summarize: ["SummaryProduced"]
        case .search: ["SearchResults"]
        case .extractClaims: ["ClaimsExtracted"]
        }
    }

    private static func producerVerb(forAny types: [String]) -> Verb? {
        for v in Verb.allCases {
            if let emits = emittedType(by: v), !Set(emits).isDisjoint(with: Set(types)) {
                return v
            }
        }
        return nil
    }
}
