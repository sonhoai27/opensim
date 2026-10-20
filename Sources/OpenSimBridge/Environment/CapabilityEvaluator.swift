import OpenSimCore

public enum CapabilityEvaluator {
    public static func evaluate(
        runtimes: [Runtime],
        frameworks: FrameworkStatus,
        simctlAvailable: Bool
    ) -> BridgeCapabilities {
        _ = frameworks
        let hasWatch = runtimes.contains { $0.platform == .watchOS && $0.isAvailable }
        let hasTV = runtimes.contains { $0.platform == .tvOS && $0.isAvailable }
        let simctl = simctlAvailable
        return BridgeCapabilities(
            render: .unavailable,
            hid: .unavailable,
            accessibility: .unavailable,
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
