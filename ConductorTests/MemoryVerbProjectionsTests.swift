import Foundation
import Testing
@testable import Conductor

@Suite("MemoryVerbProjections")
struct MemoryVerbProjectionsTests {
    @Test("AppendSlot has both slots and is Generable-compatible Codable")
    func slotCodable() throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let data = try JSONEncoder().encode(AppendSlot.outcome)
        let decoded = try JSONDecoder().decode(AppendSlot.self, from: data)
        #expect(decoded == .outcome)
    }

    @Test("AppendReceipt distinguishes acceptance from refusal")
    func receiptVariants() {
        let accepted = AppendReceipt.accepted(atomID: UUID())
        let refused = AppendReceipt.refused(reason: "unauthorized slot")
        switch accepted { case .accepted: #expect(true); default: Issue.record("accepted") }
        switch refused { case .refused: #expect(true); default: Issue.record("refused") }
    }
}
