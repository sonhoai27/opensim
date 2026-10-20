import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class SimctlCommandTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    func testListCommands() {
        XCTAssertEqual(SimctlArguments.listDevicesJSON().arguments, ["list", "devices", "-j"])
        XCTAssertEqual(SimctlArguments.listRuntimesJSON().arguments, ["list", "runtimes", "-j"])
        XCTAssertEqual(SimctlArguments.listApps(udid).arguments, ["listapps", udid.rawValue])
    }

    func testDeviceLifecycleCommands() {
        XCTAssertEqual(
            SimctlArguments.createDevice(name: "OpenSim IT", deviceType: "iPhone-Air", runtime: RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-27-0")).arguments,
            ["create", "OpenSim IT", "iPhone-Air", "com.apple.CoreSimulator.SimRuntime.iOS-27-0"]
        )
        XCTAssertEqual(SimctlArguments.createDevice(name: "OpenSim IT", deviceType: "iPhone-Air", runtime: nil).arguments, ["create", "OpenSim IT", "iPhone-Air"])
        XCTAssertEqual(SimctlArguments.boot(udid).arguments, ["boot", udid.rawValue])
        XCTAssertEqual(SimctlArguments.bootStatus(udid).arguments, ["bootstatus", udid.rawValue, "-b"])
        XCTAssertEqual(SimctlArguments.erase(udid).arguments, ["erase", udid.rawValue])
        XCTAssertEqual(SimctlArguments.delete(udid).arguments, ["delete", udid.rawValue])
        XCTAssertEqual(SimctlArguments.rename(udid, to: "New Name").arguments, ["rename", udid.rawValue, "New Name"])
    }

    func testRuntimeCommandsUseRuntimeAdd() {
        XCTAssertEqual(SimctlArguments.runtimeAdd(path: "/tmp/iOS.dmg").arguments, ["runtime", "add", "/tmp/iOS.dmg"])
        XCTAssertEqual(SimctlArguments.runtimeDelete(identifier: RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-27-0")).arguments, ["runtime", "delete", "com.apple.CoreSimulator.SimRuntime.iOS-27-0"])
        XCTAssertEqual(SimctlArguments.runtimeVerify(identifier: RuntimeID("runtime-1")).arguments, ["runtime", "verify", "runtime-1"])
    }

    func testAppCommandsAndEnvironmentPrefix() {
        let launch = SimctlArguments.launchApp(
            udid,
            bundleID: "com.apple.Preferences",
            args: ["-AppleLanguages", "(en)"],
            environment: ["OS_ACTIVITY_MODE": "disable"]
        )
        XCTAssertEqual(
            launch.arguments,
            ["launch", udid.rawValue, "com.apple.Preferences", "-AppleLanguages", "(en)"]
        )
        XCTAssertEqual(launch.environment, ["SIMCTL_CHILD_OS_ACTIVITY_MODE": "disable"])
        XCTAssertEqual(
            SimctlArguments.getAppContainer(udid, bundleID: "com.apple.Preferences", kind: .group).arguments,
            ["get_app_container", udid.rawValue, "com.apple.Preferences", "groups"]
        )
    }

    func testLogShowArguments() {
        XCTAssertEqual(
            SimctlArguments.logShow(device: udid, since: nil, last: "5m", predicate: "subsystem == \"com.apple.UIKit\"").arguments,
            ["spawn", udid.rawValue, "log", "show", "--style", "ndjson", "--info", "--debug", "--last", "5m", "--predicate", "subsystem == \"com.apple.UIKit\""]
        )
        XCTAssertEqual(
            SimctlArguments.logShow(device: udid, since: "2026-10-20 10:00:00.000000+0700", last: nil, predicate: nil).arguments,
            ["spawn", udid.rawValue, "log", "show", "--style", "ndjson", "--info", "--debug", "--start", "2026-10-20 10:00:00.000000+0700"]
        )
    }

    func testErrorMapperMapsKnownFailures() {
        let command = SimctlArguments.boot(udid)
        let invalid = SimctlOutput(status: 148, stdout: Data(), stderr: Data("Invalid device: \(udid.rawValue)\n".utf8))
        XCTAssertEqual(SimctlErrorMapper.error(for: command, output: invalid).code, "device_not_found")

        let busy = SimctlOutput(status: 149, stdout: Data(), stderr: Data("Unable to boot device in current state: Booted\n".utf8))
        XCTAssertEqual(SimctlErrorMapper.error(for: command, output: busy).code, "device_busy")

        let stopped = SimctlOutput(status: 149, stdout: Data(), stderr: Data("Unable to lookup in current state: Shutdown\n".utf8))
        XCTAssertEqual(SimctlErrorMapper.error(for: command, output: stopped).code, "device_not_booted")

        let generic = SimctlOutput(status: 1, stdout: Data(), stderr: Data("unknown failure\n".utf8))
        let mapped = SimctlErrorMapper.error(for: command, output: generic)
        XCTAssertEqual(mapped.code, "simctl_failed")
        XCTAssertEqual(mapped.details["exitStatus"], "1")
    }
}
