import XCTest
@testable import OpenSimMCP
@testable import OpenSimCore

final class ToolCatalogAdapterTests: XCTestCase {
    func testAdapterMatchesCatalogExactly() {
        let catalog = OperationCatalog.plan3()
        let tools = ToolCatalogAdapter.tools(from: catalog)
        XCTAssertEqual(Set(tools.map(\.name)), Set(catalog.mcpOperations().map(\.mcpName)))
    }

    func testDestructiveToolRequiresConfirm() throws {
        let tools = ToolCatalogAdapter.tools(from: .plan3())
        let erase = try XCTUnwrap(tools.first { $0.name == "device_erase" })
        let required = erase.inputSchema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        XCTAssertTrue(required.contains("confirm"))
        let confirm = try XCTUnwrap(erase.inputSchema["properties"]?["confirm"])
        XCTAssertEqual(confirm["type"]?.stringValue, "boolean")
    }

    func testTypedDefaultsArePreserved() throws {
        let tools = ToolCatalogAdapter.tools(from: .plan3())
        let acquire = try XCTUnwrap(tools.first { $0.name == "session_acquire" })
        let mode = try XCTUnwrap(acquire.inputSchema["properties"]?["mode"])
        XCTAssertEqual(mode["default"], .string("control"))
        let ttl = try XCTUnwrap(acquire.inputSchema["properties"]?["ttlSeconds"])
        XCTAssertEqual(ttl["default"], .number(300))
    }
}
