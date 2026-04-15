import Foundation
import Testing
@testable import Conductor

@Suite("ChatManager snapshot persistence")
struct ChatManagerSnapshotTests {
    @Test("Saving and loading a snapshot round-trips")
    @MainActor
    func roundTrip() throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let manager = ChatManager()
        let chat = manager.createNewChat()
        let snap = GraphSnapshot(
            intentStack: [LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .direct, continuation: nil)],
            subjects: SubjectStack(),
            actions: [],
            outcome: []
        )
        manager.saveSnapshot(snap, for: chat.id)
        let loaded = manager.loadSnapshot(for: chat.id)
        #expect(loaded?.intentStack.count == 1)
    }

    @Test("Loading a snapshot with a mismatched schemaVersion returns nil")
    @MainActor
    func schemaMismatch() throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let manager = ChatManager()
        let chat = manager.createNewChat()
        let old = GraphSnapshot(
            schemaVersion: 999,
            intentStack: [], subjects: SubjectStack(), actions: [], outcome: []
        )
        manager.saveSnapshotRaw(try JSONEncoder().encode(old), for: chat.id)
        let loaded = manager.loadSnapshot(for: chat.id)
        #expect(loaded == nil)
    }
}
