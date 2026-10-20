import Foundation

public struct OpenSimError: Error, Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    public var details: [String: String]
    public var recovery: String?
    public var retryable: Bool

    public init(
        code: String,
        message: String,
        details: [String: String] = [:],
        recovery: String? = nil,
        retryable: Bool = false
    ) {
        self.code = code
        self.message = message
        self.details = details
        self.recovery = recovery
        self.retryable = retryable
    }

    public init(
        code: ErrorCode,
        message: String,
        details: [String: String] = [:],
        recovery: String? = nil,
        retryable: Bool = false
    ) {
        self.init(
            code: code.rawValue,
            message: message,
            details: details,
            recovery: recovery,
            retryable: retryable
        )
    }

    public static func invalidArgument(
        _ message: String,
        details: [String: String] = [:],
        recovery: String? = nil
    ) -> OpenSimError {
        OpenSimError(
            code: .invalidArgument,
            message: message,
            details: details,
            recovery: recovery,
            retryable: false
        )
    }

    public static func deviceNotFound(_ id: DeviceID) -> OpenSimError {
        OpenSimError(
            code: .deviceNotFound,
            message: "Device \(id.rawValue) was not found",
            details: ["udid": id.rawValue],
            recovery: "Run `opensim device list` to see available devices",
            retryable: false
        )
    }

    public static func confirmationRequired(action: String) -> OpenSimError {
        OpenSimError(
            code: .confirmationRequired,
            message: "Operation \(action) requires confirmation",
            details: ["action": action],
            recovery: "Re-run the command with --yes",
            retryable: false
        )
    }

    public static func capabilityUnavailable(_ capability: String) -> OpenSimError {
        OpenSimError(
            code: .capabilityUnavailable,
            message: "Capability \(capability) is not available in this build",
            details: ["capability": capability],
            recovery: "Run `opensim doctor` and install the plan that provides this service",
            retryable: false
        )
    }

    public static func simctlFailed(_ output: SimctlFailureParts) -> OpenSimError {
        OpenSimError(
            code: .simctlFailed,
            message: output.message,
            details: output.details,
            recovery: "Run `xcrun simctl help` and check the device state",
            retryable: false
        )
    }

    public static func daemonUnavailable(_ message: String) -> OpenSimError {
        OpenSimError(
            code: .daemonUnavailable,
            message: message,
            recovery: "Run `opensim daemon start` and check `opensim daemon status`",
            retryable: true
        )
    }
}

public struct SimctlFailureParts: Sendable, Equatable {
    public var message: String
    public var details: [String: String]

    public init(message: String, details: [String: String]) {
        self.message = message
        self.details = details
    }
}
