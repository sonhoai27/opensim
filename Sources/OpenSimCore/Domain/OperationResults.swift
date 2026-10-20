import Foundation

public struct OperationAck: Codable, Sendable, Equatable {
    public var ok: Bool
    public var message: String?

    public init(ok: Bool, message: String? = nil) {
        self.ok = ok
        self.message = message
    }
}

public struct AppLaunchResult: Codable, Sendable, Equatable {
    public var bundleID: String
    public var pid: Int32

    public init(bundleID: String, pid: Int32) {
        self.bundleID = bundleID
        self.pid = pid
    }
}

public struct ContainerPathResult: Codable, Sendable, Equatable {
    public var bundleID: String
    public var kind: ContainerKind
    public var path: String

    public init(bundleID: String, kind: ContainerKind, path: String) {
        self.bundleID = bundleID
        self.kind = kind
        self.path = path
    }
}
