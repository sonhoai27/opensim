import Foundation
import OpenSimCore

public struct XCUITestAccessibilityService: AccessibilityReading {
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

    public func tree(on device: DeviceID, maxDepth: Int, maxNodes: Int) async throws -> UITree {
        let response = try await runner.run(device: device, bundleID: bundleID, action: .tree)
        guard response.ok, let node = response.node else {
            throw OpenSimError(
                code: .a11yUnavailable,
                message: response.error ?? "XCUITest helper could not read the accessibility tree",
                details: ["bundleID": bundleID, "udid": device.rawValue],
                recovery: "Keep the app in the foreground and retry the helper"
            )
        }
        let element = XCUITestSnapshotMapper.toUIElement(node, path: "0")
        return XCUITestSnapshotMapper.limited(element, maxDepth: maxDepth, maxNodes: maxNodes)
    }

    public func find(on device: DeviceID, selector: ElementSelector) async throws -> [UIElement] {
        let tree = try await tree(on: device, maxDepth: 30, maxNodes: 2_000)
        return UIElementMatcher.find(in: tree.root, selector: selector)
    }
}
