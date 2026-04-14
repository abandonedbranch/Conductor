import Testing
@testable import Conductor

@Suite("FindRelatedVerb")
struct FindRelatedVerbTests {
    @Test("Matches an atom in the outcome by case-insensitive substring")
    func matchesOutcome() async throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let pool = [
            AffordanceDescriptor(name: "Wiki", affordance: .init(
                verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview, .citations], priority: 1
            ))
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .citations, continuation: nil))
        await graph.appendOutcome(.success(content: "CRISPR cas9 editing", source: nil, toolName: "Wiki", timestamp: .now))
        let verb = FindRelatedVerb(graph: graph)
        let result = try await verb.call(arguments: .init(keyword: "crispr"))
        #expect(result.contains("CRISPR") || result.contains("cas9"))
    }

    @Test("Empty result yields []")
    func empty() async throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let pool = [
            AffordanceDescriptor(name: "Wiki", affordance: .init(
                verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview, .citations], priority: 1
            ))
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        let verb = FindRelatedVerb(graph: graph)
        let result = try await verb.call(arguments: .init(keyword: "ghost"))
        #expect(result == "[]")
    }
}
