import Foundation
import Testing
@testable import Conductor

@Suite("ManualTool Tests")
struct ManualToolTests {

    @Test("Returns index when no page specified")
    func returnsIndex() {
        let index = ManualPage.index
        for page in ManualPage.allCases {
            #expect(index.contains(page.rawValue))
            #expect(index.contains(page.summary))
        }
    }

    @Test("Returns page content for known page")
    func returnsPageContent() {
        let content = ManualPage.search.content
        #expect(!content.isEmpty)
        #expect(content.contains("search") || content.contains("Search"))
    }

    @Test("Each page has a non-empty summary")
    func allPagesHaveSummaries() {
        for page in ManualPage.allCases {
            #expect(!page.summary.isEmpty, "Page \(page.rawValue) has empty summary")
        }
    }

    @Test("Each page has non-empty content")
    func allPagesHaveContent() {
        for page in ManualPage.allCases {
            #expect(!page.content.isEmpty, "Page \(page.rawValue) has empty content")
        }
    }

    @Test("Index lists all available pages")
    func indexListsAllPages() {
        let index = ManualPage.index
        for page in ManualPage.allCases {
            #expect(index.contains(page.rawValue))
        }
    }
}
