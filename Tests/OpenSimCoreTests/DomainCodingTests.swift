import XCTest
@testable import OpenSimCore

final class DomainCodingTests: XCTestCase {
    func testLogPageRoundTrip() throws {
        let entry = LogEntry(
            timestamp: Date(timeIntervalSince1970: 1_797_000_000.123456),
            level: .error,
            subsystem: "com.apple.UIKit",
            category: "Application",
            process: "Preferences",
            message: "launch failed"
        )
        let page = LogPage(entries: [entry], nextCursor: "cursor-1")
        let data = try JSONEncoder().encode(page)
        let decoded = try JSONDecoder().decode(LogPage.self, from: data)
        XCTAssertEqual(decoded.entries.first?.message, "launch failed")
        XCTAssertEqual(decoded.entries.first?.level, .error)
        XCTAssertEqual(decoded.nextCursor, "cursor-1")
    }

    func testContainerAndVideoEnumsUseStableRawValues() throws {
        XCTAssertEqual(ContainerKind.app.rawValue, "app")
        XCTAssertEqual(ContainerKind.data.rawValue, "data")
        XCTAssertEqual(ContainerKind.group.rawValue, "group")
        XCTAssertEqual(VideoCodec.h264.rawValue, "h264")
        XCTAssertEqual(VideoCodec.hevc.rawValue, "hevc")
        XCTAssertEqual(HardwareButton.volumeUp.rawValue, "volumeUp")
        XCTAssertEqual(LogLevel.fault.rawValue, "fault")
    }

    func testKeyModifiersDefaults() throws {
        let modifiers = KeyModifiers()
        XCTAssertFalse(modifiers.command)
        XCTAssertFalse(modifiers.shift)
        XCTAssertFalse(modifiers.option)
        XCTAssertFalse(modifiers.control)
        let data = try JSONEncoder().encode(modifiers)
        let decoded = try JSONDecoder().decode(KeyModifiers.self, from: data)
        XCTAssertEqual(decoded, modifiers)
    }

    func testDoctorReportRoundTrip() throws {
        let report = DoctorReport(
            generatedAt: Date(timeIntervalSince1970: 1_797_000_000),
            macOSVersion: "27.0.1",
            architecture: "arm64",
            xcode: XcodeInfo(path: "/Applications/Xcode.app/Contents/Developer", version: "27.1", build: "27A9275", isFullXcode: true),
            frameworks: FrameworkStatus(
                coreSimulatorPath: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework",
                simulatorKitPath: "/Applications/Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework",
                coreSimulatorPresent: true,
                simulatorKitPresent: true
            ),
            privateAPI: PrivateAPIStatus(
                coreSimulatorLoadable: true,
                simulatorKitLoadable: true,
                simDisplayViewClassFound: true,
                simDeviceLegacyHIDClientClassFound: true,
                simAccessibilityManagerClassFound: false,
                notes: ["probe": "class check only"]
            ),
            capabilities: BridgeCapabilities(
                render: .unavailable,
                hid: .unavailable,
                accessibility: .unavailable,
                screenshot: .available,
                video: .available,
                watch: .unavailable,
                tv: .unavailable
            ),
            runtime: .available,
            daemon: DaemonHealth(status: .notInstalled, pid: nil, port: nil, version: nil, tokenPermissionsOK: nil),
            diskFreeBytes: 70_000_000_000,
            deviceCount: 6,
            runtimeCount: 1,
            notes: ["bridge": "simctl"]
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(DoctorReport.self, from: data)
        XCTAssertEqual(decoded.xcode?.version, "27.1")
        XCTAssertEqual(decoded.capabilities.screenshot, .available)
        XCTAssertEqual(decoded.daemon.status, .notInstalled)
    }
}
