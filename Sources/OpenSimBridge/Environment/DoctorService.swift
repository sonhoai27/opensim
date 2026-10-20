import Foundation
import OpenSimCore

public struct DoctorService: DoctorReporting {
    private let xcode: XcodeInfo
    private let frameworks: FrameworkStatus
    private let privateAPI: PrivateAPIStatus
    private let devices: any DeviceControlling
    private let runtimes: any RuntimeControlling
    private let plan2: Plan2Capabilities?
    private let daemonProbe: DaemonStateProbe

    public init(
        xcode: XcodeInfo,
        frameworks: FrameworkStatus,
        privateAPI: PrivateAPIStatus,
        devices: any DeviceControlling,
        runtimes: any RuntimeControlling,
        paths: OpenSimPaths,
        plan2: Plan2Capabilities? = nil
    ) {
        self.xcode = xcode
        self.frameworks = frameworks
        self.privateAPI = privateAPI
        self.devices = devices
        self.runtimes = runtimes
        self.plan2 = plan2
        self.daemonProbe = DaemonStateProbe(paths: paths)
    }

    public func doctorReport() async throws -> DoctorReport {
        let deviceList = try await devices.listDevices()
        let runtimeList = try await runtimes.listRuntimes()
        let capabilities = CapabilityEvaluator.evaluate(
            runtimes: runtimeList,
            frameworks: frameworks,
            simctlAvailable: true,
            plan2: plan2
        )
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let macOSVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let diskFree = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        var notes = [
            "bridge": "simctl is the preferred path for lifecycle, runtime, app and log",
            "screen": "ScreenControlling is provided by simctl",
            "input": "InputControlling is provided by Plan 2",
            "a11y": "AccessibilityReading is provided by Plan 2",
            "private_api": "Capabilities are probed by class existence only",
        ]
        if let plan2 {
            notes["render_backend"] = plan2.render.rawValue
            notes["input_backend"] = plan2.input.rawValue
            notes["a11y_backend"] = plan2.accessibility.rawValue
            notes["multi_touch"] = plan2.multiTouch.rawValue
            notes["hardware_buttons"] = plan2.hardwareButtons.rawValue
        }
        return DoctorReport(
            generatedAt: Date(),
            macOSVersion: macOSVersion,
            architecture: DoctorService.architecture,
            xcode: xcode,
            frameworks: frameworks,
            privateAPI: privateAPI,
            capabilities: capabilities,
            runtime: CapabilityEvaluator.runtimeCapability(runtimes: runtimeList),
            daemon: daemonProbe.health(),
            diskFreeBytes: Int64(diskFree ?? 0),
            deviceCount: deviceList.count,
            runtimeCount: runtimeList.count,
            notes: notes
        )
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "unknown"
        #endif
    }
}
