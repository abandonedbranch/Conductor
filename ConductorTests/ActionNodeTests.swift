import Foundation
import Testing
@testable import Conductor

@Suite("ActionNode")
struct ActionNodeTests {
    @Test("Terminal statuses are .completed and .failed")
    func terminalStatuses() {
        #expect(ActionStatus.completed.isTerminal)
        #expect(ActionStatus.failed.isTerminal)
        #expect(!ActionStatus.pending.isTerminal)
        #expect(!ActionStatus.running.isTerminal)
        #expect(!ActionStatus.awaitingUser.isTerminal)
    }

    @Test("Default node has empty atoms and pending status")
    func defaults() throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let node = ActionNode(
            kind: .work,
            goal: "find CRISPR papers",
            verbs: [.find],
            subjects: [.academic],
            answerShape: .citations,
            assignedVerbNames: ["getContext"],
            assignedToolNames: ["PubMed"],
            dependsOn: []
        )
        #expect(node.status == .pending)
        #expect(node.atoms.isEmpty)
        #expect(node.kind == .work)
    }

    @Test("Codable round-trip preserves assignments")
    func codable() throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let node = ActionNode(
            kind: .work, goal: "g",
            verbs: [.find], subjects: [.academic],
            answerShape: .citations,
            assignedVerbNames: ["append"],
            assignedToolNames: ["PubMed"],
            dependsOn: []
        )
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ActionNode.self, from: data)
        #expect(decoded.assignedToolNames == ["PubMed"])
        #expect(decoded.assignedVerbNames == ["append"])
    }
}
