import Foundation
import OpenSimCore

public enum EventType: String, Codable, Sendable, CaseIterable {
    case deviceStateChanged = "device.state.changed"
    case sessionCreated = "session.created"
    case sessionClosed = "session.closed"
    case leaseChanged = "lease.changed"
    case leaseRevoked = "lease.revoked"
    case storageScanProgress = "storage.scan.progress"
    case storageScanCompleted = "storage.scan.completed"
    case metricsSample = "metrics.sample"
    case auditAppended = "audit.appended"
    case daemonHealth = "daemon.health"
}

public struct DaemonEvent: Codable, Sendable, Equatable {
    public var id: String
    public var type: EventType
    public var timestamp: Date
    public var data: JSONValue

    public init(id: String, type: EventType, timestamp: Date, data: JSONValue) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.data = data
    }
}

public struct DeviceStateChangedPayload: Codable, Sendable, Equatable {
    public var deviceID: DeviceID
    public var state: DeviceState
    public var previousState: DeviceState

    public init(deviceID: DeviceID, state: DeviceState, previousState: DeviceState) {
        self.deviceID = deviceID
        self.state = state
        self.previousState = previousState
    }
}

public struct SessionChangedPayload: Codable, Sendable, Equatable {
    public var session: Session

    public init(session: Session) {
        self.session = session
    }
}

public struct LeaseChangedPayload: Codable, Sendable, Equatable {
    public var lease: Lease
    public var reason: String

    public init(lease: Lease, reason: String) {
        self.lease = lease
        self.reason = reason
    }
}

public struct AuditAppendedPayload: Codable, Sendable, Equatable {
    public var event: AuditEvent

    public init(event: AuditEvent) {
        self.event = event
    }
}

public struct DaemonHealthPayload: Codable, Sendable, Equatable {
    public var status: String
    public var pid: Int32
    public var port: Int

    public init(status: String, pid: Int32, port: Int) {
        self.status = status
        self.pid = pid
        self.port = port
    }
}
