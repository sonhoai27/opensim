import Foundation

public struct AuditEvent: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var timestamp: Date
    public var actor: String
    public var sessionID: SessionID?
    public var leaseID: LeaseID?
    public var action: String
    public var target: String
    public var result: String
    public var durationMs: Int

    public init(
        id: String,
        timestamp: Date,
        actor: String,
        sessionID: SessionID?,
        leaseID: LeaseID?,
        action: String,
        target: String,
        result: String,
        durationMs: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actor = actor
        self.sessionID = sessionID
        self.leaseID = leaseID
        self.action = action
        self.target = target
        self.result = result
        self.durationMs = durationMs
    }
}
