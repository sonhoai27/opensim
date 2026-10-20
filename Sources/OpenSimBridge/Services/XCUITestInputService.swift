import Foundation
import OpenSimCore

public struct XCUITestInputService: InputControlling {
    private let runner: XCUITestHelperRunner
    private let bundleID: String

    public init?(runner: XCUITestHelperRunner, bundleID: String? = nil) {
        let resolved = bundleID ?? ProcessInfo.processInfo.environment["OPENSIM_XCUITEST_BUNDLE_ID"]
        guard let resolved, !resolved.isEmpty else {
            return nil
        }
        self.runner = runner
        self.bundleID = resolved
    }

    public func tap(on device: DeviceID, at point: Point, settle: Bool) async throws {
        try await perform(device: device, action: XCUITestHelperAction(kind: .tapPoint, point: point))
    }

    public func swipe(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {
        try await perform(
            device: device,
            action: XCUITestHelperAction(kind: .swipe, from: from, to: to, durationMs: durationMs)
        )
    }

    public func longPress(on device: DeviceID, at point: Point, durationMs: Int) async throws {
        try await perform(
            device: device,
            action: XCUITestHelperAction(kind: .longPress, point: point, durationMs: durationMs)
        )
    }

    public func drag(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {
        try await perform(
            device: device,
            action: XCUITestHelperAction(kind: .drag, from: from, to: to, durationMs: durationMs)
        )
    }

    public func pinch(on device: DeviceID, center: Point, scale: Double, durationMs: Int) async throws {
        try await perform(
            device: device,
            action: XCUITestHelperAction(kind: .pinch, point: center, durationMs: durationMs, scale: scale)
        )
    }

    public func rotate(on device: DeviceID, center: Point, angle: Double, durationMs: Int) async throws {
        try await perform(
            device: device,
            action: XCUITestHelperAction(kind: .rotate, point: center, durationMs: durationMs, angle: angle)
        )
    }

    public func scroll(on device: DeviceID, deltaX: Double, deltaY: Double, at point: Point?) async throws {
        try await perform(
            device: device,
            action: XCUITestHelperAction(
                kind: .scroll,
                point: point ?? Point(x: 0, y: 0),
                deltaX: deltaX,
                deltaY: deltaY
            )
        )
    }

    public func typeText(on device: DeviceID, text: String) async throws {
        try await perform(device: device, action: XCUITestHelperAction(kind: .typeText, text: text))
    }

    public func key(on device: DeviceID, key: Key, modifiers: KeyModifiers) async throws {
        try await perform(
            device: device,
            action: XCUITestHelperAction(kind: .key, key: key.name, modifiers: modifiers)
        )
    }

    public func button(on device: DeviceID, button: HardwareButton) async throws {
        guard button == .home else {
            throw OpenSimError.capabilityUnavailable("hardware_button_\(button.rawValue)")
        }
        try await perform(device: device, action: XCUITestHelperAction(kind: .button, button: .home))
    }

    private func perform(device: DeviceID, action: XCUITestHelperAction) async throws {
        let response = try await runner.run(device: device, bundleID: bundleID, action: action)
        guard response.ok else {
            throw OpenSimError(
                code: .inputFailed,
                message: response.error ?? "XCUITest helper failed to perform \(action.kind.rawValue)",
                details: ["bundleID": bundleID, "udid": device.rawValue],
                recovery: "Keep the app in the foreground and retry"
            )
        }
    }
}
