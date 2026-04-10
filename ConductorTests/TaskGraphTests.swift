import Foundation
import Testing
@testable import Conductor

@Suite("TaskGraph Tests", .serialized)
struct TaskGraphTests {

    private func makeDummyNode(
        id: UUID = UUID(),
        purpose: AgentPurpose = .research,
        dependsOn: Set<UUID> = []
    ) -> TaskGraph.TaskNode {
        TaskGraph.TaskNode(
            id: id,
            purpose: purpose,
            goal: "test goal",
            completionCriteria: "test criteria",
            toolNames: ["TestTool"],
            dependsOn: dependsOn
        )
    }

    @Test("New graph is not fully resolved when it has pending nodes")
    func notResolvedWhenPending() async {
        let graph = TaskGraph()
        let node = makeDummyNode()
        await graph.addNode(node)
        let resolved = await graph.isFullyResolved
        #expect(!resolved)
    }

    @Test("Graph is fully resolved when all nodes are completed")
    func resolvedWhenAllCompleted() async {
        let graph = TaskGraph()
        let node = makeDummyNode()
        await graph.addNode(node)
        await graph.updateStatus(node.id, to: .completed)
        let resolved = await graph.isFullyResolved
        #expect(resolved)
    }

    @Test("Graph is fully resolved when all nodes are terminal (completed or failed)")
    func resolvedWhenTerminal() async {
        let graph = TaskGraph()
        let a = makeDummyNode()
        let b = makeDummyNode()
        await graph.addNode(a)
        await graph.addNode(b)
        await graph.updateStatus(a.id, to: .completed)
        await graph.updateStatus(b.id, to: .failed)
        let resolved = await graph.isFullyResolved
        #expect(resolved)
    }

    @Test("readyToDispatch returns nodes with no unresolved dependencies")
    func readyNoDeps() async {
        let graph = TaskGraph()
        let node = makeDummyNode()
        await graph.addNode(node)
        let ready = await graph.readyToDispatch()
        #expect(ready.count == 1)
        #expect(ready[0].id == node.id)
    }

    @Test("readyToDispatch blocks nodes with unresolved dependencies")
    func blockedByDeps() async {
        let graph = TaskGraph()
        let a = makeDummyNode()
        let b = makeDummyNode(dependsOn: [a.id])
        await graph.addNode(a)
        await graph.addNode(b)
        let ready = await graph.readyToDispatch()
        #expect(ready.count == 1)
        #expect(ready[0].id == a.id)
    }

    @Test("readyToDispatch unblocks downstream when upstream completes")
    func unblocksDownstream() async {
        let graph = TaskGraph()
        let a = makeDummyNode()
        let b = makeDummyNode(dependsOn: [a.id])
        await graph.addNode(a)
        await graph.addNode(b)
        await graph.updateStatus(a.id, to: .completed)
        let ready = await graph.readyToDispatch()
        #expect(ready.count == 1)
        #expect(ready[0].id == b.id)
    }

    @Test("readyToDispatch does not return running or completed nodes")
    func skipsNonPending() async {
        let graph = TaskGraph()
        let a = makeDummyNode()
        let b = makeDummyNode()
        await graph.addNode(a)
        await graph.addNode(b)
        await graph.updateStatus(a.id, to: .running)
        let ready = await graph.readyToDispatch()
        #expect(ready.count == 1)
        #expect(ready[0].id == b.id)
    }

    @Test("Append entry to node and retrieve it")
    func appendAndRetrieve() async {
        let graph = TaskGraph()
        let node = makeDummyNode()
        await graph.addNode(node)
        let entry = LogEntry(
            id: UUID(), taskID: node.id, purpose: .research,
            toolName: "PubMed", content: "test content",
            sourceURL: nil, timestamp: .now
        )
        await graph.append(entry, to: node.id)
        let entries = await graph.entries(for: node.id)
        #expect(entries.count == 1)
        #expect(entries[0].content == "test content")
    }

    @Test("upstreamResults returns entries from dependency nodes only")
    func upstreamResults() async {
        let graph = TaskGraph()
        let a = makeDummyNode(purpose: .overview)
        let b = makeDummyNode(dependsOn: [a.id])
        let c = makeDummyNode()
        await graph.addNode(a)
        await graph.addNode(b)
        await graph.addNode(c)

        let entryA = LogEntry(
            id: UUID(), taskID: a.id, purpose: .overview,
            toolName: "Wikipedia", content: "upstream content",
            sourceURL: nil, timestamp: .now
        )
        let entryC = LogEntry(
            id: UUID(), taskID: c.id, purpose: .research,
            toolName: "PubMed", content: "unrelated content",
            sourceURL: nil, timestamp: .now
        )
        await graph.append(entryA, to: a.id)
        await graph.append(entryC, to: c.id)

        let upstream = await graph.upstreamResults(for: b.id)
        #expect(upstream.count == 1)
        #expect(upstream[0].content == "upstream content")
    }

    @Test("Topological sort respects dependencies")
    func topologicalSort() async {
        let graph = TaskGraph()
        let a = makeDummyNode(purpose: .overview)
        let b = makeDummyNode(purpose: .research, dependsOn: [a.id])
        let c = makeDummyNode(purpose: .build, dependsOn: [b.id])
        await graph.addNode(a)
        await graph.addNode(b)
        await graph.addNode(c)
        let sorted = await graph.topologicalSort()
        let ids = sorted.map(\.id)
        #expect(ids.firstIndex(of: a.id)! < ids.firstIndex(of: b.id)!)
        #expect(ids.firstIndex(of: b.id)! < ids.firstIndex(of: c.id)!)
    }

    @Test("Narration events are published via stream")
    func narrationStream() async {
        let graph = TaskGraph()
        let node = makeDummyNode()
        await graph.addNode(node)

        let stream = await graph.narrationStream

        await graph.narrate(node.id, "Starting research...")

        var events: [NarrationEvent] = []
        for await event in stream {
            events.append(event)
            if events.count == 1 { break }
        }
        #expect(events[0].message == "Starting research...")
        #expect(events[0].purpose == .research)
    }
}
