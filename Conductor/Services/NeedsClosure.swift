import Foundation

/// Fills in implicit producer verbs a user didn't write.
///
/// When a user types "Summarize https://example.com", the prose compiler
/// only sees `[.summarize]`. But `summarize` has a declared need for an
/// upstream `ReadCompleted`, which only `read` can produce. Rather than
/// reject the pipeline or ask the user to restate, the needs-closure
/// algorithm prepends the missing producer — turning `[.summarize]` into
/// `[.read, .summarize]` automatically.
///
/// The algorithm is recursive because a prepended producer may itself have
/// unsatisfied needs. `insert` walks the dependency chain depth-first,
/// stopping when a need is already satisfied by either an earlier event in
/// the log (`existingLog`) or a verb earlier in the pipeline being built.
///
/// `existingLog` matters for the in-flight case: when `AppModel.run()`
/// inflates after Layer 1 already wrote `AtomRecorded` events, those
/// compile-origin atoms don't count as needs satisfied — but if earlier
/// runs left `ReadCompleted` events in the log, those would satisfy a
/// `summarize` without inflating a new `read`.
///
/// The emitted-type and producer-verb maps are hard-coded by design. v2
/// has four verbs and one-to-one producer/consumer relationships; a
/// reflection-driven registry would be more ceremony than signal. Adding
/// a new verb means extending both maps.
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
