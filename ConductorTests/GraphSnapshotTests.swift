import Foundation
import Testing
@testable import Conductor

@Suite("GraphSnapshot")
struct GraphSnapshotTests {
    @Test("Default snapshot carries currentSchemaVersion")
    func schemaVersion() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let snap = GraphSnapshot(
            intentStack: [], subjects: SubjectStack(), actions: [], outcome: []
        )
        #expect(snap.schemaVersion == GraphSnapshot.currentSchemaVersion)
    }

    @Test("Round-trips through Codable")
    func codable() throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let snap = GraphSnapshot(
            intentStack: [
                LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .direct, continuation: nil)
            ],
            subjects: SubjectStack(),
            actions: [],
            outcome: []
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(GraphSnapshot.self, from: data)
        #expect(decoded.intentStack.count == 1)
    }
}
