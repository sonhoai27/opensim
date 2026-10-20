import Foundation
import OpenSimCore

public struct DeviceActionRequest: Codable, Sendable, Equatable {
    public var action: String
    public var wait: Bool?
    public var name: String?
    public var confirm: Bool?
    public var sessionID: SessionID?
    public var leaseID: LeaseID?

    public init(
        action: String,
        wait: Bool? = nil,
        name: String? = nil,
        confirm: Bool? = nil,
        sessionID: SessionID? = nil,
        leaseID: LeaseID? = nil
    ) {
        self.action = action
        self.wait = wait
        self.name = name
        self.confirm = confirm
        self.sessionID = sessionID
        self.leaseID = leaseID
    }
}

public struct DeviceActionResponse: Codable, Sendable, Equatable {
    public var action: String
    public var device: Device?
    public var ack: OperationAck?

    public init(action: String, device: Device?, ack: OperationAck?) {
        self.action = action
        self.device = device
        self.ack = ack
    }
}
