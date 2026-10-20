import XCTest
@testable import OpenSimCore

final class CatalogTests: XCTestCase {
    func testPlan1LookupByCLIAndMCP() throws {
        let catalog = OperationCatalog.plan1()
        XCTAssertEqual(try XCTUnwrap(catalog.operation(forCLI: ["device", "list"])).mcpName, "device_list")
        XCTAssertEqual(try XCTUnwrap(catalog.operation(forCLI: ["doctor"])).mcpName, "doctor_report")
        XCTAssertEqual(try XCTUnwrap(catalog.operation(forMCP: "app_launch")).cliPath, ["app", "launch"])
    }

    func testMCPExposureMatchesSpecSubset() {
        let catalog = OperationCatalog.plan1()
        XCTAssertEqual(catalog.mcpOperations().count, 22)
        let names = Set(catalog.mcpOperations().map(\.mcpName))
        XCTAssertTrue(names.contains("device_list"))
        XCTAssertTrue(names.contains("log_tail"))
        XCTAssertTrue(names.contains("doctor_report"))
        XCTAssertFalse(names.contains("runtime_verify"))
        XCTAssertFalse(names.contains("log_crash"))
    }

    func testCatalogHasNoDuplicateCLIPathOrMCPName() {
        let catalog = OperationCatalog.plan1()
        XCTAssertEqual(catalog.validate(), [])
    }

    func testLeaseAndDestructiveMetadata() throws {
        let catalog = OperationCatalog.plan1()
        for operation in catalog.operations.values {
            if operation.requiresControlLease {
                XCTAssertFalse(operation.readOnly)
            }
            if operation.destructive {
                XCTAssertTrue(operation.parameters.contains { $0.name == "confirm" && $0.required })
            }
        }
        let erase = try XCTUnwrap(catalog.operation(forMCP: "device_erase"))
        XCTAssertTrue(erase.destructive)
        XCTAssertTrue(erase.requiresControlLease)
    }
}
