import Foundation
import OpenSimCore
import OpenSimDaemon
import OpenSimProtocol

public struct DaemonCommandBackend: CommandBackend {
    private let client: DaemonClient
    private let catalog: OperationCatalog
    private let providedSession: SessionID?

    public init(client: DaemonClient, catalog: OperationCatalog, providedSession: SessionID?) {
        self.client = client
        self.catalog = catalog
        self.providedSession = providedSession
    }

    public func execute<T: Decodable & Sendable>(
        _ operation: String,
        parameters: [String: String],
        as type: T.Type
    ) async throws -> T {
        guard let metadata = catalog.operation(forMCP: operation) else {
            throw OpenSimError.invalidArgument("Unknown operation: \(operation)")
        }
        let needsSession = metadata.requiresControlLease
            || operation == "session_acquire"
            || operation == "session_release"
        let sessionID: SessionID?
        if needsSession {
            sessionID = try await ensureSession()
        } else {
            sessionID = providedSession
        }

        var leaseID: LeaseID?
        do {
            if metadata.requiresControlLease {
                guard let sessionID else {
                    throw OpenSimError.invalidArgument("A session is required for this operation")
                }
                let devices = try await client.devices()
                let device = try DeviceResolver.resolve(query: parameters["device"], in: devices)
                let lease = try await client.acquireLease(AcquireLeaseRequest(
                    deviceID: device.id,
                    sessionID: sessionID,
                    mode: .control,
                    ttlSeconds: 120
                ))
                leaseID = lease.id
            }
            let result = try await client.operation(OperationRequest(
                operation: operation,
                parameters: parameters,
                sessionID: sessionID,
                leaseID: leaseID
            ))
            await cleanup(sessionID: sessionID, leaseID: leaseID, operation: operation)
            return try OpenSimJSON.decoder().decode(T.self, from: result.data)
        } catch {
            await cleanup(sessionID: sessionID, leaseID: leaseID, operation: operation)
            throw error
        }
    }

    private func ensureSession() async throws -> SessionID {
        if let providedSession {
            return providedSession
        }
        let session = try await client.createSession(clientKind: "cli", clientName: "opensim")
        return session.id
    }

    private func cleanup(sessionID: SessionID?, leaseID: LeaseID?, operation: String) async {
        if let sessionID, let leaseID {
            _ = try? await client.releaseLease(leaseID, sessionID: sessionID)
        }
        let keepsSession = operation == "session_acquire" || operation == "session_release"
        if providedSession == nil, !keepsSession, let sessionID {
            try? await client.closeSession(sessionID)
        }
    }
}
