import Foundation

public enum Platform: String, Codable, Sendable, CaseIterable {
    case iOS
    case watchOS
    case tvOS
    case visionOS
    case android
    case unknown
}

public enum DeviceState: String, Codable, Sendable, CaseIterable {
    case shutdown
    case booting
    case booted
    case shuttingDown
    case erasing
    case deleting
    case unknown
}

public struct Device: Codable, Sendable, Identifiable, Equatable {
    public let id: DeviceID
    public var name: String
    public var platform: Platform
    public var deviceType: String
    public var runtime: RuntimeID
    public var state: DeviceState
    public var isAvailable: Bool
    public var dataPath: String?
    public var lastBootedAt: Date?

    public init(
        id: DeviceID,
        name: String,
        platform: Platform,
        deviceType: String,
        runtime: RuntimeID,
        state: DeviceState,
        isAvailable: Bool,
        dataPath: String?,
        lastBootedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.deviceType = deviceType
        self.runtime = runtime
        self.state = state
        self.isAvailable = isAvailable
        self.dataPath = dataPath
        self.lastBootedAt = lastBootedAt
    }

    public static func parseState(_ raw: String) -> DeviceState {
        let normalized = raw
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
        switch normalized {
        case "shutdown":
            return .shutdown
        case "booting":
            return .booting
        case "booted":
            return .booted
        case "shuttingdown":
            return .shuttingDown
        case "erasing":
            return .erasing
        case "deleting":
            return .deleting
        default:
            return .unknown
        }
    }

    public static func platform(forRuntimeIdentifier identifier: String) -> Platform {
        if identifier.contains(".iOS-") || identifier.hasSuffix(".iOS") {
            return .iOS
        }
        if identifier.contains(".watchOS-") || identifier.hasSuffix(".watchOS") {
            return .watchOS
        }
        if identifier.contains(".tvOS-") || identifier.hasSuffix(".tvOS") {
            return .tvOS
        }
        if identifier.contains(".visionOS-") || identifier.contains(".xrOS-") {
            return .visionOS
        }
        if identifier.contains("system-images;android-") || identifier.contains(".android-") {
            return .android
        }
        return .unknown
    }
}
