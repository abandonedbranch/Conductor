import Foundation
import Testing
@testable import Conductor

@Suite("rebuildActionNodes observer")
struct RebuildActionNodesTests {
    @Test("Appending intent creates one pending Action matching the toolbox")
    func createsAction() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let tools = [
            AffordanceDescriptor(name: "PubMed", affordance: .init(
                verbs: [.find], subjects: [.academic], answerShapes: [.citations], priority: 10
            )),
            AffordanceDescriptor(name: "Wikipedia", affordance: .init(
                verbs: [.find, .summarize], subjects: [.encyclopedic], answerShapes: [.overview, .direct], priority: 5
            )),
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: tools, verbDescriptors: [])
        let intent = LanguageIntentQuery(
            verbs: [.find], subjects: ["CRISPR"],
            answerShape: .citations, continuation: nil
        )
        await graph.append(intent: intent)
        let actions = await graph.allActions()
        #expect(actions.count == 1)
        #expect(actions[0].kind == .work)
        #expect(actions[0].status == .pending)
        #expect(actions[0].assignedToolNames.contains("PubMed"))
    }

    @Test("Empty toolbox match produces a clarification Action")
    func clarification() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let tools = [
            AffordanceDescriptor(name: "PubMed", affordance: .init(
                verbs: [.find], subjects: [.academic], answerShapes: [.citations], priority: 10
            )),
            AffordanceDescriptor(name: "Wikipedia", affordance: .init(
                verbs: [.find, .summarize], subjects: [.encyclopedic], answerShapes: [.overview, .direct], priority: 5
            )),
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: tools, verbDescriptors: [])
        let intent = LanguageIntentQuery(
            verbs: [.build], subjects: ["CRISPR"],
            answerShape: .workflow, continuation: nil
        )
        await graph.append(intent: intent)
        let actions = await graph.allActions()
        #expect(actions.count == 1)
        #expect(actions[0].kind == .clarification)
        #expect(actions[0].status == .awaitingUser)
    }

    @Test("Prior awaitingUser clarifications transition to completed on new turn")
    func priorClarificationResolves() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let tools = [
            AffordanceDescriptor(name: "PubMed", affordance: .init(
                verbs: [.find], subjects: [.academic], answerShapes: [.citations], priority: 10
            )),
            AffordanceDescriptor(name: "Wikipedia", affordance: .init(
                verbs: [.find, .summarize], subjects: [.encyclopedic], answerShapes: [.overview, .direct], priority: 5
            )),
        ]
        let graph = WorkingMemoryGraph(toolDescriptors: tools, verbDescriptors: [])
        let bad = LanguageIntentQuery(verbs: [.build], subjects: ["x"], answerShape: .workflow, continuation: nil)
        await graph.append(intent: bad)
        let stale = await graph.allActions().first!.id
        let follow = LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .citations, continuation: .refines)
        await graph.append(intent: follow)
        let staleNow = await graph.action(for: stale)
        #expect(staleNow?.status == .completed)
    }
}
