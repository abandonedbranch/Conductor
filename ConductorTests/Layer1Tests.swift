import Testing
import Foundation
@testable import Conductor

@Suite struct Layer1Tests {
    @Test func extractsSingleURL() {
        let atoms = Layer1DataDetector.extract(from: "Read https://example.com please")
        let urls = atoms.filter { $0.role == "url" }
        #expect(urls.count == 1)
        if case let .url(u) = urls.first?.value { #expect(u.host == "example.com") } else { Issue.record("no url") }
    }

    @Test func extractsNumberWithRoleResolution() {
        // "find 3 papers" — the number is adjacent to `find` (which maps to search), so role = "search.limit"
        let atoms = Layer1DataDetector.extract(from: "find 3 papers")
        let nums = atoms.filter { if case .number = $0.value { return true } else { return false } }
        #expect(nums.first?.role == "search.limit")
    }

    @Test func unresolvedNumberRoleIsDropped() {
        // "I've read 3 articles" — no catalog verb nearby with a .number parameter → atom not emitted
        let atoms = Layer1DataDetector.extract(from: "I've read 3 articles")
        let nums = atoms.filter { if case .number = $0.value { return true } else { return false } }
        #expect(nums.isEmpty)
    }

    @Test func extractsDate() {
        let atoms = Layer1DataDetector.extract(from: "on January 5, 2026")
        let dates = atoms.filter { if case .date = $0.value { return true } else { return false } }
        #expect(dates.count >= 1)
    }

    @Test func sourceIsDetector() {
        let atoms = Layer1DataDetector.extract(from: "Read https://x")
        #expect(atoms.first?.source == .detector)
    }
}
