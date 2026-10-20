import ArgumentParser
import XCTest
@testable import OpenSimCLI
@testable import OpenSimCore

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

    func testParsesRuntimeListPlatform() throws {
        let command = try OpenSimCommand.parseAsRoot(["runtime", "list", "--platform", "iOS"])
        let list = try XCTUnwrap(command as? RuntimeListCommand)
        XCTAssertEqual(list.platform, "iOS")
    }

    func testParsesAppLaunchEnvironment() throws {
        let command = try OpenSimCommand.parseAsRoot([
            "app", "launch", "com.apple.Preferences",
            "--device", "iPhone Air",
            "--env", "OS_ACTIVITY_MODE=disable",
        ])
        let launch = try XCTUnwrap(command as? AppLaunchCommand)
        XCTAssertEqual(launch.bundleID, "com.apple.Preferences")
        XCTAssertEqual(launch.environment, ["OS_ACTIVITY_MODE=disable"])
    }

    func testParsesAppContainerKind() throws {
        let command = try OpenSimCommand.parseAsRoot(["app", "container", "com.apple.Preferences", "--kind", "data"])
        let container = try XCTUnwrap(command as? AppContainerCommand)
        XCTAssertEqual(container.kind, "data")
    }

    func testParsesLogTailLimitAndCursor() throws {
        let command = try OpenSimCommand.parseAsRoot(["log", "tail", "--limit", "25", "--cursor", "abc"])
        let tail = try XCTUnwrap(command as? LogTailCommand)
        XCTAssertEqual(tail.limit, 25)
        XCTAssertEqual(tail.cursor, "abc")
    }

    func testRootHasAllCommandGroups() {
        let names = OpenSimCommand.configuration.subcommands.map { $0.configuration.commandName }
        XCTAssertEqual(
            Set(names),
            Set(["device", "runtime", "app", "ui", "log", "doctor", "daemon", "session"])
        )
    }

    func testParsesDirectAndSessionOptions() throws {
        let command = try OpenSimCommand.parseAsRoot([
            "device", "list", "--direct", "--session", "session-1",
        ])
        let list = try XCTUnwrap(command as? DeviceListCommand)
        XCTAssertTrue(list.globals.direct)
        XCTAssertEqual(list.globals.session, "session-1")
    }

    func testParsesDaemonStatus() throws {
        let command = try OpenSimCommand.parseAsRoot(["daemon", "status"])
        XCTAssertNotNil(command as? DaemonStatusCommand)
    }

    func testParsesSessionAcquireModeAndTTL() throws {
        let command = try OpenSimCommand.parseAsRoot([
            "session", "acquire", "--device", "UDID-1", "--mode", "observe", "--ttl", "60",
        ])
        let acquire = try XCTUnwrap(command as? SessionAcquireCommand)
        XCTAssertEqual(acquire.mode, "observe")
        XCTAssertEqual(acquire.ttl, 60)
        XCTAssertEqual(acquire.globals.parameters(["mode": "observe", "ttlSeconds": "60"])["device"], "UDID-1")
    }

    func testInvalidTimeoutIsRejectedByRuntimeValidation() {
        var globals = GlobalOptions()
        globals.timeout = 0
        XCTAssertThrowsError(try globals.validated()) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, "invalid_argument")
        }
    }

    func testParsesRuntimeDownload() throws {
        let command = try OpenSimCommand.parseAsRoot([
            "runtime", "download", "--platform", "iOS", "--version", "26.4",
        ])
        let download = try XCTUnwrap(command as? RuntimeDownloadCommand)
        XCTAssertEqual(download.platform, "iOS")
        XCTAssertEqual(download.version, "26.4")
    }
}
