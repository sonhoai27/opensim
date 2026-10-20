import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class CapabilityEvaluatorTests: XCTestCase {
    private let frameworks = FrameworkStatus(
        coreSimulatorPath: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework",
        simulatorKitPath: "/Applications/Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework",
        coreSimulatorPresent: true,
        simulatorKitPresent: true
    )

    func testNoRuntimeDisablesPlatformCapabilities() {
        let capabilities = CapabilityEvaluator.evaluate(runtimes: [], frameworks: frameworks, simctlAvailable: true)
        XCTAssertEqual(capabilities.render, .unavailable)
        XCTAssertEqual(capabilities.hid, .unavailable)
        XCTAssertEqual(capabilities.accessibility, .unavailable)
        XCTAssertEqual(capabilities.screenshot, .available)
        XCTAssertEqual(capabilities.video, .available)
        XCTAssertEqual(capabilities.watch, .unavailable)
        XCTAssertEqual(capabilities.tv, .unavailable)
        XCTAssertEqual(CapabilityEvaluator.runtimeCapability(runtimes: []), .unavailable)
    }

    func testWatchRuntimeEnablesWatchCapability() {
        let runtime = Runtime(
            id: RuntimeID("com.apple.CoreSimulator.SimRuntime.watchOS-27-0"),
            name: "watchOS 27.0",
            platform: .watchOS,
            version: "27.0",
            build: "24A434",
            isAvailable: true,
            path: nil
        )
        let capabilities = CapabilityEvaluator.evaluate(runtimes: [runtime], frameworks: frameworks, simctlAvailable: true)
        XCTAssertEqual(capabilities.watch, .available)
        XCTAssertEqual(capabilities.tv, .unavailable)
    }

    func testPlan2BackendsMapToCapabilities() {
        let xcuiTest = Plan2Capabilities(
            render: .ioSurface,
            input: .xcuiTest,
            accessibility: .xcuiTest,
            multiTouch: .unknown,
            hardwareButtons: .unknown,
            notes: [:]
        )
        let fallback = CapabilityEvaluator.evaluate(
            runtimes: [],
            frameworks: frameworks,
            simctlAvailable: true,
            plan2: xcuiTest
        )
        XCTAssertEqual(fallback.render, .available)
        XCTAssertEqual(fallback.hid, .unknown)
        XCTAssertEqual(fallback.accessibility, .unknown)

        let primary = Plan2Capabilities(
            render: .simDisplayView,
            input: .simulatorKit,
            accessibility: .simAccessibilityManager,
            multiTouch: .available,
            hardwareButtons: .available,
            notes: [:]
        )
        let full = CapabilityEvaluator.evaluate(
            runtimes: [],
            frameworks: frameworks,
            simctlAvailable: true,
            plan2: primary
        )
        XCTAssertEqual(full.render, .available)
        XCTAssertEqual(full.hid, .available)
        XCTAssertEqual(full.accessibility, .available)

        let dtuhid = Plan2Capabilities(
            render: .ioSurface,
            input: .dtuhid,
            accessibility: .xcuiTest,
            multiTouch: .unknown,
            hardwareButtons: .unknown,
            notes: [:]
        )
        let dtuhidCapabilities = CapabilityEvaluator.evaluate(
            runtimes: [],
            frameworks: frameworks,
            simctlAvailable: true,
            plan2: dtuhid
        )
        XCTAssertEqual(dtuhidCapabilities.hid, .available)

        let unavailable = Plan2Capabilities(
            render: .screenshotPolling,
            input: .unavailable,
            accessibility: .unavailable,
            multiTouch: .unavailable,
            hardwareButtons: .unavailable,
            notes: [:]
        )
        let polling = CapabilityEvaluator.evaluate(
            runtimes: [],
            frameworks: frameworks,
            simctlAvailable: true,
            plan2: unavailable
        )
        XCTAssertEqual(polling.render, .unknown)
        XCTAssertEqual(polling.hid, .unavailable)
        XCTAssertEqual(polling.accessibility, .unavailable)
    }

    func testMissingSimctlMakesScreenshotUnknown() {
        let capabilities = CapabilityEvaluator.evaluate(runtimes: [], frameworks: frameworks, simctlAvailable: false)
        XCTAssertEqual(capabilities.screenshot, .unknown)
        XCTAssertEqual(capabilities.video, .unknown)
    }
}
