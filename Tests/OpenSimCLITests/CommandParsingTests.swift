import ArgumentParser
import XCTest
@testable import OpenSimCLI

final class CommandParsingTests: XCTestCase {
    func testParsesDeviceListAtLeaf() throws {
        let command = try OpenSimCommand.parseAsRoot(["device", "list", "--json"])
        let list = try XCTUnwrap(command as? DeviceListCommand)
        XCTAssertTrue(list.globals.json)
    }

    func testParsesDeviceBootWait() throws {
        let command = try OpenSimCommand.parseAsRoot(["device", "boot", "--device", "iPhone Air", "--wait"])
        let boot = try XCTUnwrap(command as? DeviceBootCommand)
        XCTAssertTrue(boot.wait)
        XCTAssertEqual(boot.globals.device, "iPhone Air")
    }

    func testParsesDestructiveConfirmationFlag() throws {
        let command = try OpenSimCommand.parseAsRoot(["device", "delete", "--yes"])
        let delete = try XCTUnwrap(command as? DeviceDeleteCommand)
        XCTAssertTrue(delete.globals.yes)
    }
}
