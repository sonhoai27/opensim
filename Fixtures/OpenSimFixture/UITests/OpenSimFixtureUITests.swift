import XCTest

final class OpenSimFixtureUITests: XCTestCase {
    func testFixtureLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["fixture-primary-button"].exists)
    }
}
