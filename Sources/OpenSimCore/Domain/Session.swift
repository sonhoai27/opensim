import Foundation

public enum LeaseMode: String, Codable, Sendable, CaseIterable {
    case control
    case observe
}

public struct Session: Codable, Sendable, Identifiable, Equatable {
    public let id: SessionID
    public var clientKind: String
    public var clientName: String
    public var createdAt: Date
    public var lastSeenAt: Date

    public init(id: SessionID, clientKind: String, clientName: String, createdAt: Date, lastSeenAt: Date) {
        self.id = id
        self.clientKind = clientKind
        self.clientName = clientName
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}

public struct Lease: Codable, Sendable, Identifiable, Equatable {
    public let id: LeaseID
    public var deviceID: DeviceID
    public var sessionID: SessionID
    public var mode: LeaseMode
    public var ownerName: String
    public var acquiredAt: Date
    public var expiresAt: Date

    public init(
        id: LeaseID,
        deviceID: DeviceID,
        sessionID: SessionID,
        mode: LeaseMode,
        ownerName: String,
        acquiredAt: Date,
        expiresAt: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.sessionID = sessionID
        self.mode = mode
        self.ownerName = ownerName
        self.acquiredAt = acquiredAt
        self.expiresAt = expiresAt
    }
}
