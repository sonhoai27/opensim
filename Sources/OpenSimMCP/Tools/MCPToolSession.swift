import Foundation
import OpenSimCore
import OpenSimDaemon
import OpenSimProtocol

public actor MCPToolSession: MCPToolCalling {
    private let client: DaemonClient
    private let catalog: OperationCatalog
    private let clientName: String
    private var sessionID: SessionID?
    private var leases: [DeviceID: Lease] = [:]
    private var heartbeatTask: Task<Void, Never>?

    public init(client: DaemonClient, catalog: OperationCatalog, clientName: String = "opensim-mcp") {
        self.client = client
        self.catalog = catalog
        self.clientName = clientName
    }

    public func call(tool: OpenSimCore.Operation, arguments: JSONValue) async throws -> JSONValue {
        let parameters = try Self.parameters(from: arguments)
        let session = try await ensureSession()
        var leaseID: LeaseID?
        if tool.requiresControlLease {
            let devices = try await client.devices()
            let device = try DeviceResolver.resolve(query: parameters["device"], in: devices)
            let lease = try await ensureLease(device: device.id, session: session)
            leaseID = lease.id
        }
        let result = try await client.operation(OperationRequest(
            operation: tool.mcpName,
            parameters: parameters,
            sessionID: session,
            leaseID: leaseID
        ))
        return try JSONDecoder().decode(JSONValue.self, from: result.data)
    }

    public func close() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        for lease in leases.values {
            _ = try? await client.releaseLease(lease.id, sessionID: lease.sessionID)
        }
        leases.removeAll()
        if let sessionID {
            try? await client.closeSession(sessionID)
        }
        sessionID = nil
    }

    private func ensureSession() async throws -> SessionID {
        if let sessionID {
            return sessionID
        }
        let session = try await client.createSession(clientKind: "mcp", clientName: clientName)
        self.sessionID = session.id
        return session.id
    }

    private func ensureLease(device: DeviceID, session: SessionID) async throws -> Lease {
        if let lease = leases[device], lease.expiresAt > Date().addingTimeInterval(60) {
            return lease
        }
        let lease = try await client.acquireLease(AcquireLeaseRequest(
            deviceID: device,
            sessionID: session,
            mode: .control,
            ttlSeconds: 300
        ))
        leases[device] = lease
        startHeartbeatIfNeeded()
        return lease
    }

    private func startHeartbeatIfNeeded() {
        guard heartbeatTask == nil else {
            return
        }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.heartbeatLeases()
            }
        }
    }

    private func heartbeatLeases() async {
        for (device, lease) in Array(leases) {
            do {
                let renewed = try await client.heartbeatLease(
                    lease.id,
                    sessionID: lease.sessionID,
                    ttlSeconds: 300
                )
                leases[device] = renewed
            } catch {
                leases.removeValue(forKey: device)
            }
        }
    }

    private static func parameters(from arguments: JSONValue) throws -> [String: String] {
        guard let object = arguments.objectValue else {
            throw OpenSimError.invalidArgument("Tool arguments must be a JSON object")
        }
        var result: [String: String] = [:]
        for (key, value) in object {
            switch value {
            case .null:
                continue
            case .string(let text):
                result[key] = text
            case .bool(let flag):
                result[key] = flag ? "true" : "false"
            case .number(let number):
                result[key] = number.rounded() == number ? String(Int(number)) : String(number)
            case .array, .object:
                let data = try JSONEncoder().encode(value)
                result[key] = String(decoding: data, as: UTF8.self)
            }
        }
        return result
    }
}
