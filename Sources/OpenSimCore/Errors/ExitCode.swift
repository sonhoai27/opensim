public enum OpenSimExitCode: Int32, Sendable, CaseIterable {
    case success = 0
    case usage = 2
    case notFound = 3
    case conflict = 4
    case unsupported = 5
    case permission = 6
    case confirmationRequired = 7
    case internalError = 10

    public static func forError(_ code: String) -> OpenSimExitCode {
        switch code {
        case ErrorCode.invalidArgument.rawValue:
            return .usage
        case ErrorCode.deviceNotFound.rawValue,
             ErrorCode.avdNotFound.rawValue,
             ErrorCode.androidImageUnavailable.rawValue:
            return .notFound
        case ErrorCode.deviceNotBooted.rawValue,
             ErrorCode.deviceBusy.rawValue,
             ErrorCode.deviceNameConflict.rawValue,
             ErrorCode.runtimeInUse.rawValue,
             ErrorCode.leaseRequired.rawValue,
             ErrorCode.leaseConflict.rawValue,
             ErrorCode.leaseRevoked.rawValue,
             ErrorCode.storageInUse.rawValue:
            return .conflict
        case ErrorCode.unsupportedXcode.rawValue,
             ErrorCode.privateApiUnavailable.rawValue,
             ErrorCode.a11yUnavailable.rawValue,
             ErrorCode.capabilityUnavailable.rawValue,
             ErrorCode.runtimeVersionUnavailable.rawValue,
             ErrorCode.androidSDKNotFound.rawValue,
             ErrorCode.grpcUnavailable.rawValue:
            return .unsupported
        case ErrorCode.emulatorFailed.rawValue,
             ErrorCode.adbFailed.rawValue:
            return .internalError
        case ErrorCode.xcodeNotFound.rawValue,
             ErrorCode.permissionDenied.rawValue:
            return .permission
        case ErrorCode.confirmationRequired.rawValue:
            return .confirmationRequired
        default:
            return .internalError
        }
    }
}
