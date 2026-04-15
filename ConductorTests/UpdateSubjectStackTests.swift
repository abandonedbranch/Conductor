import Testing
@testable import Conductor

@Suite("updateSubjectStack observer")
struct UpdateSubjectStackTests {
    @Test(".extends appends a new active subject")
    func extendsAppends() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let pool = [
            AffordanceDescriptor(name: "Wikipedia", affordance: .init(
                verbs: [.find, .summarize], subjects: [.encyclopedic],
                answerShapes: [.overview, .direct, .summary, .citations], priority: 5
            )),
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        let a = LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .overview, continuation: nil)
        await graph.append(intent: a)
        let b = LanguageIntentQuery(verbs: [.find], subjects: ["transformers"], answerShape: .overview, continuation: .extends)
        await graph.append(intent: b)
        let active = await graph.activeSubjects()
        #expect(active.map(\.name) == ["CRISPR", "transformers"])
    }

    @Test(".pivots archives current active subjects and pushes new one")
    func pivotsArchives() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let pool = [
            AffordanceDescriptor(name: "Wikipedia", affordance: .init(
                verbs: [.find, .summarize], subjects: [.encyclopedic],
                answerShapes: [.overview, .direct, .summary, .citations], priority: 5
            )),
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .overview, continuation: nil))
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["transformers"], answerShape: .overview, continuation: .pivots))
        let active = await graph.activeSubjects()
        let archived = await graph.archivedSubjects()
        #expect(active.map(\.name) == ["transformers"])
        #expect(archived.map(\.name) == ["CRISPR"])
    }

    @Test(".refines touches the matching active subject")
    func refinesTouches() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let pool = [
            AffordanceDescriptor(name: "Wikipedia", affordance: .init(
                verbs: [.find, .summarize], subjects: [.encyclopedic],
                answerShapes: [.overview, .direct, .summary, .citations], priority: 5
            )),
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .overview, continuation: nil))
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .overview, continuation: .refines))
        let active = await graph.activeSubjects()
        #expect(active.count == 1)
        #expect(active[0].lastTouchedTurn == 2)
    }

    @Test(".recalls does not change structure")
    func recallsNoop() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let pool = [
            AffordanceDescriptor(name: "Wikipedia", affordance: .init(
                verbs: [.find, .summarize], subjects: [.encyclopedic],
                answerShapes: [.overview, .direct, .summary, .citations], priority: 5
            )),
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .overview, continuation: nil))
        await graph.append(intent: LanguageIntentQuery(verbs: [.recall], subjects: ["CRISPR"], answerShape: .summary, continuation: .recalls))
        let active = await graph.activeSubjects()
        #expect(active.count == 1)
    }
}
