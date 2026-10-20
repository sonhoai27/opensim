import Foundation
import OpenSimCore

public struct SimctlBridge: SimulatorBridge, DoctorReporting, CrashReportReading {
    public let devices: any DeviceControlling
    public let runtimes: any RuntimeControlling
    public let apps: any AppControlling
    public let logs: any LogControlling
    public let screen: (any ScreenControlling)?
    public let input: (any InputControlling)?
    public let accessibility: (any AccessibilityReading)?

    private let crashService: any CrashReportReading
    private let doctorService: any DoctorReporting
    private let capabilityProvider: @Sendable () async -> BridgeCapabilities

    public init(
        devices: any DeviceControlling,
        runtimes: any RuntimeControlling,
        apps: any AppControlling,
        logs: any LogControlling,
        crashReports: any CrashReportReading,
        doctor: any DoctorReporting,
        capabilityProvider: @escaping @Sendable () async -> BridgeCapabilities
    ) {
        self.devices = devices
        self.runtimes = runtimes
        self.apps = apps
        self.logs = logs
        self.screen = nil
        self.input = nil
        self.accessibility = nil
        self.crashService = crashReports
        self.doctorService = doctor
        self.capabilityProvider = capabilityProvider
    }

    public var capabilities: BridgeCapabilities {
        get async {
            await capabilityProvider()
        }
    }

    public func doctorReport() async throws -> DoctorReport {
        try await doctorService.doctorReport()
    }

    public func crashReports(on device: DeviceID, limit: Int) async throws -> [CrashReport] {
        try await crashService.crashReports(on: device, limit: limit)
    }

    public static func live(timeout: Duration = .seconds(60)) throws -> SimctlBridge {
        let locator = XcodeLocator()
        let developerDir = try locator.developerDir()
        let xcode = try locator.version(developerDir: developerDir)
        let frameworks = FrameworkLocator.status(developerDir: developerDir)
        let privateAPI = PrivateFrameworkProbe.probe(frameworks: frameworks)
        let executor = ProcessSimctlExecutor()
        let devices = SimctlDeviceService(executor: executor, timeout: timeout)
        let runtimes = SimctlRuntimeService(executor: executor, timeout: timeout)
        let apps = SimctlAppService(executor: executor, timeout: timeout)
        let logs = SimctlLogService(executor: executor, timeout: timeout)
        let crashes = CrashReportService(devices: devices)
        let paths = OpenSimPaths()
        let doctor = DoctorService(
            xcode: xcode,
            frameworks: frameworks,
            privateAPI: privateAPI,
            devices: devices,
            runtimes: runtimes,
            paths: paths
        )
        let runtimesForCapabilities: any RuntimeControlling = runtimes
        let capabilityProvider: @Sendable () async -> BridgeCapabilities = {
            let list = (try? await runtimesForCapabilities.listRuntimes()) ?? []
            return CapabilityEvaluator.evaluate(
                runtimes: list,
                frameworks: frameworks,
                simctlAvailable: true
            )
        }
        return SimctlBridge(
            devices: devices,
            runtimes: runtimes,
            apps: apps,
            logs: logs,
            crashReports: crashes,
            doctor: doctor,
            capabilityProvider: capabilityProvider
        )
    }
}
