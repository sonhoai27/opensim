import Foundation
import OpenSimCore

public enum RenderBackend: String, Codable, Sendable, CaseIterable {
    case simDisplayView
    case ioSurface
    case screenshotPolling
}

public enum InputBackend: String, Codable, Sendable, CaseIterable {
    case simulatorKit
    case xcuiTest
    case unavailable
}

public enum AccessibilityBackend: String, Codable, Sendable, CaseIterable {
    case simAccessibilityManager
    case xcuiTest
    case unavailable
}

public struct Plan2Capabilities: Codable, Sendable, Equatable {
    public var render: RenderBackend
    public var input: InputBackend
    public var accessibility: AccessibilityBackend
    public var multiTouch: Capability
    public var hardwareButtons: Capability
    public var notes: [String: String]

    public init(
        render: RenderBackend,
        input: InputBackend,
        accessibility: AccessibilityBackend,
        multiTouch: Capability,
        hardwareButtons: Capability,
        notes: [String: String]
    ) {
        self.render = render
        self.input = input
        self.accessibility = accessibility
        self.multiTouch = multiTouch
        self.hardwareButtons = hardwareButtons
        self.notes = notes
    }
}

public enum Plan2CapabilityGate {
    public static let accessibilitySelectors = [
        "rootElement",
        "accessibilityElement",
        "accessibilityTree",
        "snapshot",
        "elements",
        "elementAtPoint:",
    ]

    public static func evaluate(
        checker: (any SimulatorKitClassChecking)?,
        helperConfigured: Bool
    ) -> Plan2Capabilities {
        let core = checker?.hasClass("SimServiceContext") == true
        let displays = core
            && checker?.hasClass("SimDisplayView") == true
            && checker?.responds("SimDisplayView", "setDevice:") == true
            && checker?.responds("SimDisplayView", "connectedScreen") == true
            && checker?.responds("SimDisplayView", "pixelSize") == true
        // The screen proxy forwards framebufferSurface dynamically, so only the
        // SimDeviceScreen.screen selector can be verified without instantiating it.
        let surfaces = core
            && checker?.hasClass("SimDeviceScreen") == true
            && checker?.responds("SimDeviceScreen", "screen") == true
        let render: RenderBackend = displays ? .simDisplayView : (surfaces ? .ioSurface : .screenshotPolling)
        let input: InputBackend = displays ? .simulatorKit : (helperConfigured ? .xcuiTest : .unavailable)
        let manager = checker?.hasClass("SimAccessibilityManager") == true
            && accessibilitySelectors.contains {
                checker?.responds("SimAccessibilityManager", $0) == true
            }
        let accessibility: AccessibilityBackend = manager
            ? .simAccessibilityManager
            : (helperConfigured ? .xcuiTest : .unavailable)
        let sends = checker?.sendSelectors(className: "SimDeviceLegacyHIDClient") ?? []
        let symbols = checker?.indigoSymbols() ?? []
        return Plan2Capabilities(
            render: render,
            input: input,
            accessibility: accessibility,
            multiTouch: symbols.isEmpty ? .unavailable : .unknown,
            hardwareButtons: sends.isEmpty ? .unavailable : .unknown,
            notes: [
                "render": render.rawValue,
                "input": input.rawValue,
                "accessibility": accessibility.rawValue,
                "indigoSymbolCount": String(symbols.count),
                "legacyHIDSendSelectors": sends.joined(separator: ","),
            ]
        )
    }
}
