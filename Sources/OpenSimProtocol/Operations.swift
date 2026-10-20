import Foundation
import OpenSimCore

public struct OperationRequest: Codable, Sendable, Equatable {
    public var operation: String
    public var parameters: [String: String]
    public var sessionID: SessionID?
    public var leaseID: LeaseID?
    public var dryRun: Bool?

    public init(
        operation: String,
        parameters: [String: String] = [:],
        sessionID: SessionID? = nil,
        leaseID: LeaseID? = nil,
        dryRun: Bool? = nil
    ) {
        self.operation = operation
        self.parameters = parameters
        self.sessionID = sessionID
        self.leaseID = leaseID
        self.dryRun = dryRun
    }
}

public struct OperationResult: Codable, Sendable, Equatable {
    public var operation: String
    public var data: Data
    public var auditID: String?

    public init(operation: String, data: Data, auditID: String? = nil) {
        self.operation = operation
        self.data = data
        self.auditID = auditID
    }
}

public extension OperationResult {
    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try OpenSimJSON.decoder().decode(type, from: data)
    }
}
