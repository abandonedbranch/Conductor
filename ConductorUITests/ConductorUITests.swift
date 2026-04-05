import XCTest

final class ConductorUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    func testAppLaunches() throws {
        XCTAssertTrue(app.staticTexts["Conductor"].exists)
    }
}
