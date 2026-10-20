import Foundation
import OpenSimCore

public struct HealthResponse: Codable, Sendable, Equatable {
    public var status: String
    public var version: String
    public var protocolVersion: Int
    public var pid: Int32
    public var port: Int
    public var startedAt: Date
    public var capabilities: BridgeCapabilities
    public var xcodeVersion: String

    public init(
        status: String,
        version: String,
        protocolVersion: Int,
        pid: Int32,
        port: Int,
        startedAt: Date,
        capabilities: BridgeCapabilities,
        xcodeVersion: String
    ) {
        self.status = status
        self.version = version
        self.protocolVersion = protocolVersion
        self.pid = pid
        self.port = port
        self.startedAt = startedAt
        self.capabilities = capabilities
        self.xcodeVersion = xcodeVersion
    }
}
