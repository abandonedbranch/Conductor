import Foundation
import Testing
@testable import Conductor

@Suite("SubjectStack")
struct SubjectStackTests {
    @Test("Push appends to active when under cap")
    func pushUnderCap() {
        var stack = SubjectStack()
        stack.push(name: "CRISPR", turn: 1, relatesTo: nil)
        #expect(stack.active.count == 1)
        #expect(stack.active.first?.name == "CRISPR")
    }

    @Test("Active overflow moves oldest entry to archived")
    func activeOverflow() {
        var stack = SubjectStack()
        for i in 0..<9 {
            stack.push(name: "subject-\(i)", turn: i, relatesTo: nil)
        }
        #expect(stack.active.count == 8)
        #expect(stack.archived.count == 1)
        #expect(stack.archived.first?.name == "subject-0")
    }

    @Test("Archive overflow drops least-recently-touched entry")
    func archiveLRU() {
        var stack = SubjectStack()
        for i in 0..<8 {
            stack.push(name: "active-\(i)", turn: i, relatesTo: nil)
        }
        for i in 0..<21 {
            stack.push(name: "overflow-\(i)", turn: 100 + i, relatesTo: nil)
        }
        #expect(stack.active.count == 8)
        #expect(stack.archived.count == 20)
        #expect(!stack.archived.contains { $0.name == "active-0" })
    }

    @Test("Archive all moves active entries into archived in order")
    func archiveAll() {
        var stack = SubjectStack()
        stack.push(name: "a", turn: 1, relatesTo: nil)
        stack.push(name: "b", turn: 2, relatesTo: nil)
        stack.archiveAll()
        #expect(stack.active.isEmpty)
        #expect(stack.archived.count == 2)
    }

    @Test("touch updates lastTouchedTurn on an active entry")
    func touchUpdates() {
        var stack = SubjectStack()
        stack.push(name: "a", turn: 1, relatesTo: nil)
        let id = stack.active[0].id
        stack.touch(id: id, turn: 5)
        #expect(stack.active[0].lastTouchedTurn == 5)
    }

    @Test("Codable round-trip preserves both tiers")
    func codable() throws {
        var stack = SubjectStack()
        stack.push(name: "alpha", turn: 1, relatesTo: nil)
        stack.push(name: "beta", turn: 2, relatesTo: stack.active[0].id)
        let data = try JSONEncoder().encode(stack)
        let decoded = try JSONDecoder().decode(SubjectStack.self, from: data)
        #expect(decoded.active.count == 2)
    }

    @Test("touch updates lastTouchedTurn on an archived entry")
    func touchArchived() {
        var stack = SubjectStack()
        for i in 0..<9 {
            stack.push(name: "subject-\(i)", turn: i, relatesTo: nil)
        }
        let archivedID = stack.archived[0].id
        stack.touch(id: archivedID, turn: 99)
        #expect(stack.archived[0].lastTouchedTurn == 99)
    }
}
