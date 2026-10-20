import XCTest
@testable import OpenSimCore

final class Plan2CatalogTests: XCTestCase {
    func testPlan1IsUnchanged() {
        XCTAssertEqual(OperationCatalog.plan1().mcpOperations().count, 23)
    }

    func testPlan2AddsEveryUIOperation() throws {
        let catalog = OperationCatalog.plan2()
        XCTAssertEqual(catalog.validate(), [])
        XCTAssertEqual(try XCTUnwrap(catalog.operation(forCLI: ["ui", "tap"])).mcpName, "ui_tap")
        XCTAssertEqual(try XCTUnwrap(catalog.operation(forMCP: "screen_screenshot")).cliPath, ["ui", "screenshot"])
        XCTAssertTrue(try XCTUnwrap(catalog.operation(forMCP: "ui_tree")).readOnly)
        XCTAssertTrue(try XCTUnwrap(catalog.operation(forMCP: "ui_tap")).requiresControlLease)
    }

    func testActionStepRoundTrips() throws {
        let step = UIActStep(type: "tap", on: ElementSelector(identifier: "fixture-primary-button"))
        let data = try OpenSimJSON.encoder(pretty: false).encode(step)
        XCTAssertEqual(try OpenSimJSON.decoder().decode(UIActStep.self, from: data), step)
    }
}
