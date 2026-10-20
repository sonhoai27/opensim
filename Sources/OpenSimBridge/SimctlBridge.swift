import CoreGraphics
import Foundation
import OpenSimCore

public protocol SimulatorScreenDisplaying: Sendable {
    @MainActor func makeDisplaySurface(for device: DeviceID) throws -> any DisplaySurface
}

public struct SimctlBridge: SimulatorBridge, DoctorReporting, CrashReportReading, SimulatorScreenDisplaying {
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
    private let displaySurfaceFactory: (@MainActor @Sendable (DeviceID) throws -> any DisplaySurface)?

    public init(
        devices: any DeviceControlling,
        runtimes: any RuntimeControlling,
        apps: any AppControlling,
        logs: any LogControlling,
        crashReports: any CrashReportReading,
        doctor: any DoctorReporting,
        screen: (any ScreenControlling)? = nil,
        input: (any InputControlling)? = nil,
        accessibility: (any AccessibilityReading)? = nil,
        displaySurfaceFactory: (@MainActor @Sendable (DeviceID) throws -> any DisplaySurface)? = nil,
        capabilityProvider: @escaping @Sendable () async -> BridgeCapabilities
    ) {
        self.devices = devices
        self.runtimes = runtimes
        self.apps = apps
        self.logs = logs
        self.screen = screen
        self.input = input
        self.accessibility = accessibility
        self.displaySurfaceFactory = displaySurfaceFactory
        self.crashService = crashReports
        self.doctorService = doctor
        self.capabilityProvider = capabilityProvider
    }

    @MainActor
    public func makeDisplaySurface(for device: DeviceID) throws -> any DisplaySurface {
        guard let displaySurfaceFactory else {
            throw OpenSimError.capabilityUnavailable("render")
        }
        return try displaySurfaceFactory(device)
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
        let gate = Plan2CapabilityGate.evaluate(
            checker: SimulatorKitLoader.live(),
            helperConfigured: XCUITestHelperRunner.isConfigured
        )
        let capture = SimctlScreenCapture(
            executor: executor,
            devices: devices,
            profiles: SimctlDeviceTypeProfileProvider(executor: executor, timeout: timeout),
            paths: paths,
            timeout: timeout
        )
        let recording = SimctlRecordingController(
            launcher: ProcessRecordingLauncher(),
            store: RecordingStateStore(directory: paths.recordingStateDirectory),
            paths: paths
        )
        let framebuffer: FramebufferScreenshotter?
        if gate.render == .ioSurface || gate.render == .simDisplayView {
            framebuffer = FramebufferScreenshotter(paths: paths)
        } else {
            framebuffer = nil
        }
        let screenService = SimctlScreenService(
            capture: capture,
            recorder: recording,
            framebuffer: framebuffer
        )
        let helperRunner = XCUITestHelperRunner()
        let bundleID = ProcessInfo.processInfo.environment["OPENSIM_XCUITEST_BUNDLE_ID"]
        let inputService: (any InputControlling)?
        if gate.input == .xcuiTest {
            inputService = XCUITestInputService(runner: helperRunner, bundleID: bundleID)
        } else {
            inputService = nil
        }
        let accessibilityService: (any AccessibilityReading)?
        if gate.accessibility == .xcuiTest {
            accessibilityService = XCUITestAccessibilityService(runner: helperRunner, bundleID: bundleID)
        } else {
            accessibilityService = nil
        }
        let screenScaleProvider: @Sendable (DeviceID) async -> CGFloat = { device in
            let screens = try? await screenService.screens(for: device)
            return screens?.first?.scale ?? 1
        }
        let displaySurfaceFactory: @MainActor @Sendable (DeviceID) throws -> any DisplaySurface = { device in
            switch gate.render {
            case .simDisplayView, .ioSurface:
                return IOSurfaceDisplaySurface(device: device, screenScaleProvider: screenScaleProvider)
            case .screenshotPolling:
                return ScreenshotPollingSurface(
                    device: device,
                    screens: screenService,
                    screenScaleProvider: screenScaleProvider
                )
            }
        }
        let doctor = DoctorService(
            xcode: xcode,
            frameworks: frameworks,
            privateAPI: privateAPI,
            devices: devices,
            runtimes: runtimes,
            paths: paths,
            plan2: gate
        )
        let runtimesForCapabilities: any RuntimeControlling = runtimes
        let capabilityProvider: @Sendable () async -> BridgeCapabilities = {
            let list = (try? await runtimesForCapabilities.listRuntimes()) ?? []
            return CapabilityEvaluator.evaluate(
                runtimes: list,
                frameworks: frameworks,
                simctlAvailable: true,
                plan2: gate
            )
        }
        return SimctlBridge(
            devices: devices,
            runtimes: runtimes,
            apps: apps,
            logs: logs,
            crashReports: crashes,
            doctor: doctor,
            screen: screenService,
            input: inputService,
            accessibility: accessibilityService,
            displaySurfaceFactory: displaySurfaceFactory,
            capabilityProvider: capabilityProvider
        )
    }
}
