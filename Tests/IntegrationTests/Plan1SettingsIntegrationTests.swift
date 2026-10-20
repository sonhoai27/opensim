import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class Plan1SettingsIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] == "1",
            "Set OPENSIM_INTEGRATION=1 to run simulator integration tests"
        )
    }

    private func bootedIOSDevice(_ bridge: SimctlBridge) async throws -> Device {
        let devices = try await bridge.devices.listDevices()
        guard let device = devices.first(where: { $0.state == .booted && $0.platform == .iOS }) else {
            throw XCTSkip("No booted iOS simulator")
        }
        return device
    }

    func testSettingsAppFlow() async throws {
        let bridge = try SimctlBridge.live(timeout: .seconds(120))
        let device = try await bootedIOSDevice(bridge)

        let apps = try await bridge.apps.listApps(on: device.id, filter: "Preferences")
        XCTAssertTrue(apps.contains { $0.id == "com.apple.Preferences" })

        let info = try await bridge.apps.appInfo(on: device.id, bundleID: "com.apple.Preferences")
        XCTAssertEqual(info.displayName, "Settings")
        XCTAssertEqual(info.id, "com.apple.Preferences")

        let pid = try await bridge.apps.launchApp(
            on: device.id,
            bundleID: "com.apple.Preferences",
            args: [],
            environment: [:]
        )
        XCTAssertGreaterThan(pid, 0)

        let appPath = try await bridge.apps.containerPath(
            on: device.id,
            bundleID: "com.apple.Preferences",
            kind: .app
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: appPath))

        let page = try await bridge.logs.tailLogs(on: device.id, cursor: nil, limit: 20, filter: nil)
        XCTAssertFalse(page.entries.isEmpty)

        try await bridge.apps.terminateApp(on: device.id, bundleID: "com.apple.Preferences")
    }

    func testTemporaryDeviceLifecycle() async throws {
        let bridge = try SimctlBridge.live(timeout: .seconds(180))
        let runtimes = try await bridge.runtimes.listRuntimes()
        guard let runtime = runtimes.first(where: { $0.platform == .iOS && $0.isAvailable }) else {
            throw XCTSkip("No available iOS runtime")
        }
        let name = "OpenSim IT \(UUID().uuidString.prefix(8))"
        let device = try await bridge.devices.createDevice(
            name: name,
            deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-17e",
            runtime: runtime.id
        )
        do {
            let booted = try await bridge.devices.boot(device.id, wait: true)
            XCTAssertEqual(booted.state, .booted)
            let shutdown = try await bridge.devices.shutdown(device.id, wait: true)
            XCTAssertEqual(shutdown.state, .shutdown)
            let erased = try await bridge.devices.erase(device.id)
            XCTAssertEqual(erased.state, .shutdown)
            try await bridge.devices.delete(device.id)
        } catch {
            try? await bridge.devices.delete(device.id)
            throw error
        }
        let remaining = try await bridge.devices.listDevices()
        XCTAssertFalse(remaining.contains { $0.id == device.id })
    }
}
