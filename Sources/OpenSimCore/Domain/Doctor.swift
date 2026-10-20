import Foundation

public enum Capability: String, Codable, Sendable, CaseIterable {
    case available
    case unavailable
    case unknown
}

public struct BridgeCapabilities: Codable, Sendable, Equatable {
    public var render: Capability
    public var hid: Capability
    public var accessibility: Capability
    public var screenshot: Capability
    public var video: Capability
    public var watch: Capability
    public var tv: Capability

    public init(
        render: Capability,
        hid: Capability,
        accessibility: Capability,
        screenshot: Capability,
        video: Capability,
        watch: Capability,
        tv: Capability
    ) {
        self.render = render
        self.hid = hid
        self.accessibility = accessibility
        self.screenshot = screenshot
        self.video = video
        self.watch = watch
        self.tv = tv
    }
}

public enum DaemonStatus: String, Codable, Sendable, CaseIterable {
    case notInstalled
    case notRunning
    case unhealthy
    case running
}

public struct DaemonHealth: Codable, Sendable, Equatable {
    public var status: DaemonStatus
    public var pid: Int32?
    public var port: Int?
    public var version: String?
    public var tokenPermissionsOK: Bool?

    public init(
        status: DaemonStatus,
        pid: Int32?,
        port: Int?,
        version: String?,
        tokenPermissionsOK: Bool?
    ) {
        self.status = status
        self.pid = pid
        self.port = port
        self.version = version
        self.tokenPermissionsOK = tokenPermissionsOK
    }
}

public struct XcodeInfo: Codable, Sendable, Equatable {
    public var path: String
    public var version: String
    public var build: String
    public var isFullXcode: Bool

    public init(path: String, version: String, build: String, isFullXcode: Bool) {
        self.path = path
        self.version = version
        self.build = build
        self.isFullXcode = isFullXcode
    }
}

public struct FrameworkStatus: Codable, Sendable, Equatable {
    public var coreSimulatorPath: String?
    public var simulatorKitPath: String?
    public var coreSimulatorPresent: Bool
    public var simulatorKitPresent: Bool

    public init(
        coreSimulatorPath: String?,
        simulatorKitPath: String?,
        coreSimulatorPresent: Bool,
        simulatorKitPresent: Bool
    ) {
        self.coreSimulatorPath = coreSimulatorPath
        self.simulatorKitPath = simulatorKitPath
        self.coreSimulatorPresent = coreSimulatorPresent
        self.simulatorKitPresent = simulatorKitPresent
    }
}

public struct PrivateAPIStatus: Codable, Sendable, Equatable {
    public var coreSimulatorLoadable: Bool
    public var simulatorKitLoadable: Bool
    public var simDisplayViewClassFound: Bool
    public var simDeviceLegacyHIDClientClassFound: Bool
    public var simAccessibilityManagerClassFound: Bool
    public var notes: [String: String]

    public init(
        coreSimulatorLoadable: Bool,
        simulatorKitLoadable: Bool,
        simDisplayViewClassFound: Bool,
        simDeviceLegacyHIDClientClassFound: Bool,
        simAccessibilityManagerClassFound: Bool,
        notes: [String: String]
    ) {
        self.coreSimulatorLoadable = coreSimulatorLoadable
        self.simulatorKitLoadable = simulatorKitLoadable
        self.simDisplayViewClassFound = simDisplayViewClassFound
        self.simDeviceLegacyHIDClientClassFound = simDeviceLegacyHIDClientClassFound
        self.simAccessibilityManagerClassFound = simAccessibilityManagerClassFound
        self.notes = notes
    }
}

public struct DoctorReport: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var macOSVersion: String
    public var architecture: String
    public var xcode: XcodeInfo?
    public var frameworks: FrameworkStatus
    public var privateAPI: PrivateAPIStatus
    public var capabilities: BridgeCapabilities
    public var runtime: Capability
    public var daemon: DaemonHealth
    public var diskFreeBytes: Int64
    public var deviceCount: Int
    public var runtimeCount: Int
    public var notes: [String: String]

    public init(
        generatedAt: Date,
        macOSVersion: String,
        architecture: String,
        xcode: XcodeInfo?,
        frameworks: FrameworkStatus,
        privateAPI: PrivateAPIStatus,
        capabilities: BridgeCapabilities,
        runtime: Capability,
        daemon: DaemonHealth,
        diskFreeBytes: Int64,
        deviceCount: Int,
        runtimeCount: Int,
        notes: [String: String]
    ) {
        self.generatedAt = generatedAt
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.xcode = xcode
        self.frameworks = frameworks
        self.privateAPI = privateAPI
        self.capabilities = capabilities
        self.runtime = runtime
        self.daemon = daemon
        self.diskFreeBytes = diskFreeBytes
        self.deviceCount = deviceCount
        self.runtimeCount = runtimeCount
        self.notes = notes
    }
}
