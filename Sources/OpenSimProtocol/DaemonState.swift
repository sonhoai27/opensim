import Foundation

public struct DaemonState: Codable, Sendable, Equatable {
    public var pid: Int32
    public var port: Int
    public var token: String
    public var version: String
    public var xcodeVersion: String
    public var startedAt: Date

    public init(
        pid: Int32,
        port: Int,
        token: String,
        version: String,
        xcodeVersion: String,
        startedAt: Date
    ) {
        self.pid = pid
        self.port = port
        self.token = token
        self.version = version
        self.xcodeVersion = xcodeVersion
        self.startedAt = startedAt
    }
}
