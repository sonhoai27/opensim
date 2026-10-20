import Foundation
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class Plan2FixtureIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] == "1",
            "Set OPENSIM_INTEGRATION=1 to run simulator integration tests"
        )
    }

    func testFixtureInputAccessibilityAndScreenshot() async throws {
        setenv("OPENSIM_XCUITEST_BUNDLE_ID", FixtureInstaller.bundleID, 1)
        let bridge = try SimctlBridge.live(timeout: .seconds(180))
        let device = try await bootedOrBootIOSDevice(bridge)
        _ = try await FixtureInstaller.installAndLaunch(bridge: bridge.apps, device: device.id)
        try await Task.sleep(for: .seconds(2))

        guard let screen = bridge.screen else {
            throw XCTSkip("screen service is unavailable")
        }
        guard let accessibility = bridge.accessibility, let input = bridge.input else {
            throw XCTSkip("XCUITest helper is not configured")
        }
        let automation = UIAutomationService(
            screen: screen,
            input: input,
            accessibility: accessibility
        )

        let screens = try await screen.screens(for: device.id)
        let mainScreen = try XCTUnwrap(screens.first(where: { $0.displayClass == 0 }) ?? screens.first)
        let shot = try await screen.screenshot(on: device.id, format: .png, scale: 0.5, quality: nil)
        XCTAssertGreaterThan(shot.width, 0)
        XCTAssertGreaterThan(shot.height, 0)
        XCTAssertEqual(shot.width, Int((Double(mainScreen.width) * 0.5).rounded()))
        XCTAssertTrue(shot.path.map { FileManager.default.fileExists(atPath: $0) } ?? false)

        let tree = try await accessibility.tree(on: device.id, maxDepth: 30, maxNodes: 1_500)
        XCTAssertGreaterThan(tree.nodeCount, 0)
        let button = UIElementMatcher.find(
            in: tree.root,
            selector: ElementSelector(identifier: "fixture-primary-button")
        ).first
        XCTAssertNotNil(button)

        let before = try await label("fixture-counter-label", bridge: bridge, device: device.id)
        let beforeValue = Int(before ?? "0") ?? 0
        let tap = try await automation.tap(
            on: device.id,
            selector: ElementSelector(identifier: "fixture-primary-button"),
            settle: true
        )
        XCTAssertEqual(tap.matchedCount, 1)
        let after = try await waitForLabel(
            "fixture-counter-label",
            equals: String(beforeValue + 1),
            bridge: bridge,
            device: device.id
        )
        XCTAssertEqual(after, String(beforeValue + 1))

        _ = try await automation.tap(
            on: device.id,
            selector: ElementSelector(identifier: "fixture-text-field"),
            settle: false
        )
        try await input.typeText(on: device.id, text: "hello@example.com")
        let typed = try await waitForLabel(
            "fixture-text-value",
            contains: "hello@example.com",
            bridge: bridge,
            device: device.id
        )
        XCTAssertNotNil(typed)

        let gestureTree = try await accessibility.tree(on: device.id, maxDepth: 30, maxNodes: 2_000)
        let longPressElement = try XCTUnwrap(
            UIElementMatcher.find(
                in: gestureTree.root,
                selector: ElementSelector(identifier: "fixture-long-press-target")
            ).first
        )
        let longPressPoint = Point(
            x: longPressElement.frame.x + longPressElement.frame.width / 2,
            y: longPressElement.frame.y + longPressElement.frame.height / 2
        )
        try await input.longPress(on: device.id, at: longPressPoint, durationMs: 700)
        let longPress = try await waitForLabel(
            "fixture-gesture-label",
            equals: "gesture=long-press",
            bridge: bridge,
            device: device.id
        )
        XCTAssertEqual(longPress, "gesture=long-press")

        let swipeElement = try XCTUnwrap(
            UIElementMatcher.find(
                in: gestureTree.root,
                selector: ElementSelector(identifier: "fixture-swipe-area")
            ).first
        )
        let swipeY = swipeElement.frame.y + swipeElement.frame.height / 2
        try await input.swipe(
            on: device.id,
            from: Point(x: swipeElement.frame.x + swipeElement.frame.width * 0.85, y: swipeY),
            to: Point(x: swipeElement.frame.x + swipeElement.frame.width * 0.15, y: swipeY),
            durationMs: 50
        )
        let swipe = try await waitForLabel(
            "fixture-gesture-label",
            equals: "gesture=swipe-left",
            bridge: bridge,
            device: device.id
        )
        XCTAssertEqual(swipe, "gesture=swipe-left")

        var tapStep = UIActStep(type: "tap")
        tapStep.on = ElementSelector(identifier: "fixture-primary-button")
        var waitStep = UIActStep(type: "wait")
        waitStep.ms = 200
        var shotStep = UIActStep(type: "screenshot")
        shotStep.format = .png
        let act = try await automation.act(
            on: device.id,
            steps: [tapStep, waitStep, shotStep],
            stopOnError: true
        )
        XCTAssertEqual(act.steps.count, 3)
        XCTAssertTrue(act.steps.allSatisfy(\.ok))
        XCTAssertNotNil(act.steps.last?.screenshot)

        try await verifyRecording(bridge: bridge, device: device.id)
    }

    func testCapabilityUnavailableWithoutServices() async throws {
        unsetenv("OPENSIM_XCUITEST_BUNDLE_ID")
        let bridge = try SimctlBridge.live(timeout: .seconds(60))
        let executor = BridgeOperationExecutor(
            bridge: bridge,
            catalog: .plan2(),
            automation: nil
        )
        do {
            _ = try await executor.execute(
                operation: "ui_tree",
                parameters: ["device": "iPhone Air"]
            )
            XCTFail("expected capability_unavailable")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "capability_unavailable")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private func bootedOrBootIOSDevice(_ bridge: SimctlBridge) async throws -> Device {
        let devices = try await bridge.devices.listDevices()
        if let booted = devices.first(where: { $0.state == .booted && $0.platform == .iOS }) {
            return booted
        }
        guard let candidate = devices.first(where: { $0.platform == .iOS && $0.isAvailable }) else {
            throw XCTSkip("No available iOS simulator")
        }
        return try await bridge.devices.boot(candidate.id, wait: true)
    }

    private func label(
        _ identifier: String,
        bridge: SimctlBridge,
        device: DeviceID
    ) async throws -> String? {
        guard let accessibility = bridge.accessibility else { return nil }
        let tree = try await accessibility.tree(on: device, maxDepth: 30, maxNodes: 2_000)
        return UIElementMatcher.find(
            in: tree.root,
            selector: ElementSelector(identifier: identifier)
        ).first?.label
    }

    private func waitForLabel(
        _ identifier: String,
        equals expected: String,
        bridge: SimctlBridge,
        device: DeviceID
    ) async throws -> String? {
        try await waitForLabel(identifier, contains: expected, bridge: bridge, device: device)
    }

    private func waitForLabel(
        _ identifier: String,
        contains expected: String,
        bridge: SimctlBridge,
        device: DeviceID
    ) async throws -> String? {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let value = try await label(identifier, bridge: bridge, device: device),
               value.contains(expected) {
                return value
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    private func verifyRecording(bridge: SimctlBridge, device: DeviceID) async throws {
        guard let screen = bridge.screen, let recorder = screen as? any RecordingControlling else {
            throw XCTSkip("recording service is unavailable")
        }
        do {
            let id = try await screen.startRecording(on: device, to: nil, codec: .h264)
            try await Task.sleep(for: .seconds(2))
            let result = try await recorder.stopRecordingResult(id)
            XCTAssertGreaterThan(
                (try? FileManager.default.attributesOfItem(atPath: result.path)[.size] as? NSNumber)?.intValue ?? 0,
                0
            )
        } catch let error as OpenSimError {
            throw XCTSkip("recording unavailable in this environment: \(error.message)")
        }
    }
}
