import Foundation
import Testing
@testable import Conductor

@Suite("WorkingMemoryGraph")
struct WorkingMemoryGraphTests {
    @Test("Reads return empty before any writes")
    func emptyReads() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let graph = WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: [])
        let intent = await graph.currentIntent()
        let subjects = await graph.activeSubjects()
        let actions = await graph.allActions()
        #expect(intent == nil)
        #expect(subjects.isEmpty)
        #expect(actions.isEmpty)
    }

    @Test("append(intent:) stores the value and emits .intent")
    func appendIntent() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let graph = WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: [])
        let stream = graph.changes
        let intent = LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .direct, continuation: nil)
        await graph.append(intent: intent)

        let stored = await graph.currentIntent()
        #expect(stored?.verbs == [.find])

        var received: [ChangeKind] = []
        for await change in stream {
            received.append(change)
            if received.contains(.intent) { break }
        }
        #expect(received.contains(.intent))
    }

    @Test("updateStatus reflects in allActions")
    func updateStatus() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let graph = WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: [])
        let node = ActionNode(
            kind: .work, goal: "g", verbs: [.find], subjects: [.academic],
            answerShape: .citations, assignedVerbNames: [],
            assignedToolNames: ["PubMed"], dependsOn: []
        )
        await graph.insertAction(node)
        await graph.updateStatus(.running, for: node.id)
        let actions = await graph.allActions()
        #expect(actions.first?.status == .running)
    }

    @Test("Snapshot and restore preserves graph contents")
    func snapshotRestore() async {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let graph = WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: [])
        let intent = LanguageIntentQuery(verbs: [.read], subjects: ["doc"], answerShape: .summary, continuation: nil)
        await graph.append(intent: intent)
        let snap = await graph.snapshot()

        let restored = await WorkingMemoryGraph.restore(from: snap, toolDescriptors: [], verbDescriptors: [])
        let intent2 = await restored.currentIntent()
        #expect(intent2?.subjects == ["doc"])
    }
}
