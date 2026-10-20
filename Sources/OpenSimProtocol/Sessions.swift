import Foundation
import OpenSimCore

public struct CreateSessionRequest: Codable, Sendable, Equatable {
    public var clientKind: String
    public var clientName: String

    public init(clientKind: String, clientName: String) {
        self.clientKind = clientKind
        self.clientName = clientName
    }
}

public struct AcquireLeaseRequest: Codable, Sendable, Equatable {
    public var deviceID: DeviceID
    public var sessionID: SessionID
    public var mode: LeaseMode
    public var ttlSeconds: Int?
    public var takeover: Bool?
    public var ownerName: String?

    public init(
        deviceID: DeviceID,
        sessionID: SessionID,
        mode: LeaseMode,
        ttlSeconds: Int? = nil,
        takeover: Bool? = nil,
        ownerName: String? = nil
    ) {
        self.deviceID = deviceID
        self.sessionID = sessionID
        self.mode = mode
        self.ttlSeconds = ttlSeconds
        self.takeover = takeover
        self.ownerName = ownerName
    }
}

public struct HeartbeatRequest: Codable, Sendable, Equatable {
    public var sessionID: SessionID
    public var ttlSeconds: Int?

    public init(sessionID: SessionID, ttlSeconds: Int? = nil) {
        self.sessionID = sessionID
        self.ttlSeconds = ttlSeconds
    }
}

public struct LeaseReleaseResult: Codable, Sendable, Equatable {
    public var leaseID: LeaseID
    public var released: Bool

    public init(leaseID: LeaseID, released: Bool) {
        self.leaseID = leaseID
        self.released = released
    }
}

public struct SessionListResult: Codable, Sendable, Equatable {
    public var sessions: [Session]
    public var leases: [Lease]

    public init(sessions: [Session], leases: [Lease]) {
        self.sessions = sessions
        self.leases = leases
    }
}
