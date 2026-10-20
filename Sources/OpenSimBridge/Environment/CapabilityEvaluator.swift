import OpenSimCore

public enum CapabilityEvaluator {
    public static func evaluate(
        runtimes: [Runtime],
        frameworks: FrameworkStatus,
        simctlAvailable: Bool,
        plan2: Plan2Capabilities? = nil
    ) -> BridgeCapabilities {
        _ = frameworks
        let hasWatch = runtimes.contains { $0.platform == .watchOS && $0.isAvailable }
        let hasTV = runtimes.contains { $0.platform == .tvOS && $0.isAvailable }
        let simctl = simctlAvailable

        let render: Capability
        let hid: Capability
        let accessibility: Capability
        if let plan2 {
            switch plan2.render {
            case .simDisplayView, .ioSurface:
                render = .available
            case .screenshotPolling:
                render = .unknown
            }
            switch plan2.input {
            case .simulatorKit:
                hid = .available
            case .xcuiTest:
                hid = .unknown
            case .unavailable:
                hid = .unavailable
            }
            switch plan2.accessibility {
            case .simAccessibilityManager:
                accessibility = .available
            case .xcuiTest:
                accessibility = .unknown
            case .unavailable:
                accessibility = .unavailable
            }
        } else {
            render = .unavailable
            hid = .unavailable
            accessibility = .unavailable
        }

        return BridgeCapabilities(
            render: render,
            hid: hid,
            accessibility: accessibility,
            screenshot: simctl ? .available : .unknown,
            video: simctl ? .available : .unknown,
            watch: hasWatch ? .available : .unavailable,
            tv: hasTV ? .available : .unavailable
        )
    }

    public static func runtimeCapability(runtimes: [Runtime]) -> Capability {
        runtimes.contains { $0.platform == .iOS && $0.isAvailable } ? .available : .unavailable
    }
}
