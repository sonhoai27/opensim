import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

let listAppsPlist = """
{
    "com.apple.Preferences" =     {
        ApplicationType = System;
        CFBundleDisplayName = Settings;
        CFBundleIdentifier = "com.apple.Preferences";
        CFBundleName = Settings;
        CFBundleShortVersionString = "1.0";
        CFBundleVersion = "2027.0.10.401";
        DataContainer = "file:///Users/test/Library/Developer/CoreSimulator/Devices/UDID/data/Containers/Data/Application/DATA/";
        Path = "/Applications/Preferences.app";
    };
}
"""

final class SimctlAppServiceTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    func testListAppsParsesOpenStepPlistAndFilters() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(listAppsPlist))
        await executor.enqueue(jsonOutput(listAppsPlist))
        await executor.enqueue(jsonOutput(listAppsPlist))
        let service = SimctlAppService(executor: executor, timeout: .seconds(5))
        let all = try await service.listApps(on: udid, filter: nil)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, "com.apple.Preferences")
        XCTAssertEqual(all[0].displayName, "Settings")
        XCTAssertEqual(all[0].version, "1.0")
        XCTAssertEqual(all[0].build, "2027.0.10.401")
        XCTAssertEqual(all[0].dataContainer, "/Users/test/Library/Developer/CoreSimulator/Devices/UDID/data/Containers/Data/Application/DATA")
        XCTAssertEqual(all[0].appContainer, "/Applications/Preferences.app")

        let filtered = try await service.listApps(on: udid, filter: "settings")
        XCTAssertEqual(filtered.count, 1)
        let missing = try await service.listApps(on: udid, filter: "Safari")
        XCTAssertEqual(missing.count, 0)
    }

    func testAppInfoParsesSinglePlist() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("""
        {
            CFBundleDisplayName = Settings;
            CFBundleIdentifier = "com.apple.Preferences";
            CFBundleShortVersionString = "1.0";
            CFBundleVersion = "2027.0.10.401";
            DataContainer = "file:///Users/test/data/";
            Path = "/Applications/Preferences.app";
        }
        """))
        let service = SimctlAppService(executor: executor, timeout: .seconds(5))
        let info = try await service.appInfo(on: udid, bundleID: "com.apple.Preferences")
        XCTAssertEqual(info.displayName, "Settings")
        XCTAssertEqual(info.dataContainer, "/Users/test/data")
    }

    func testLaunchParsesPID() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("com.apple.Preferences: 4321\n"))
        let service = SimctlAppService(executor: executor, timeout: .seconds(5))
        let pid = try await service.launchApp(
            on: udid,
            bundleID: "com.apple.Preferences",
            args: [],
            environment: ["OS_ACTIVITY_MODE": "disable"]
        )
        XCTAssertEqual(pid, 4321)
        let commands = await executor.commands
        XCTAssertEqual(commands[0].environment, ["SIMCTL_CHILD_OS_ACTIVITY_MODE": "disable"])
    }

    func testContainerPathRejectsNull() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("(null)\n"))
        let service = SimctlAppService(executor: executor, timeout: .seconds(5))
        do {
            _ = try await service.containerPath(on: udid, bundleID: "com.apple.Preferences", kind: .data)
            XCTFail("expected simctl_failed")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "simctl_failed")
        }
    }

    func testTerminateIsIdempotentWhenNothingRuns() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(SimctlOutput(
            status: 1,
            stdout: Data(),
            stderr: Data("found nothing to terminate\n".utf8)
        ))
        let service = SimctlAppService(executor: executor, timeout: .seconds(5))
        try await service.terminateApp(on: udid, bundleID: "com.apple.Preferences")
    }
}
