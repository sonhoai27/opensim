import Foundation
import Logging
import OpenSimBridge
import OpenSimCore
import OpenSimProtocol

public struct OperationDispatcher: Sendable {
    public let catalog: OperationCatalog
    public let executor: BridgeOperationExecutor
    public let bridge: any SimulatorBridge
    public let sessions: SessionManager
    public let leases: LeaseManager
    public let audit: AuditWriter
    public let events: EventHub
    public let logger: Logger

    public init(
        catalog: OperationCatalog,
        executor: BridgeOperationExecutor,
        bridge: any SimulatorBridge,
        sessions: SessionManager,
        leases: LeaseManager,
        audit: AuditWriter,
        events: EventHub,
        logger: Logger
    ) {
        self.catalog = catalog
        self.executor = executor
        self.bridge = bridge
        self.sessions = sessions
        self.leases = leases
        self.audit = audit
        self.events = events
        self.logger = logger
    }

    public func dispatch(_ request: OperationRequest) async throws -> OperationResult {
        if request.dryRun == true {
            throw OpenSimError.invalidArgument("dryRun is not supported in Plan 3")
        }
        guard let operation = catalog.operation(forMCP: request.operation) else {
            throw OpenSimError.invalidArgument("Unknown operation: \(request.operation)")
        }
        let parameters = try OperationParameters(request.parameters).validated(against: operation)

        switch operation.mcpName {
        case "session_list":
            return try await handleSessionList(request: request, operation: operation)
        case "session_acquire":
            return try await handleSessionAcquire(request: request, operation: operation, parameters: parameters)
        case "session_release":
            return try await handleSessionRelease(request: request, operation: operation, parameters: parameters)
        default:
            break
        }

        if let service = operation.requiredService, !bridge.supports(service) {
            throw OpenSimError.capabilityUnavailable(service.rawValue)
        }
        if operation.destructive, try parameters.bool("confirm", default: false) == false {
            throw OpenSimError.confirmationRequired(action: operation.mcpName)
        }

        var deviceID: DeviceID?
        var lease: Lease?
        if operation.requiresControlLease {
            guard let sessionID = request.sessionID else {
                throw OpenSimError(
                    code: .leaseRequired,
                    message: "A session and control lease are required",
                    details: ["operation": operation.mcpName],
                    recovery: "Create a session and acquire a control lease",
                    retryable: false
                )
            }
            let resolved = try await resolveDevice(parameters)
            deviceID = resolved
            try await leases.validate(device: resolved, leaseID: request.leaseID, session: sessionID)
            if let leaseID = request.leaseID {
                lease = await leases.activeLeases().first { $0.id == leaseID }
            }
        }

        let started = Date()
        do {
            let data = try await executor.execute(operation: operation.mcpName, parameters: request.parameters)
            let auditEvent = await record(
                operation: operation,
                request: request,
                deviceID: deviceID,
                lease: lease,
                result: "ok",
                started: started
            )
            if let auditEvent {
                _ = try? await events.publish(type: .auditAppended, payload: AuditAppendedPayload(event: auditEvent))
            }
            return OperationResult(
                operation: operation.mcpName,
                data: data,
                auditID: auditEvent?.id
            )
        } catch let error as OpenSimError {
            _ = await record(
                operation: operation,
                request: request,
                deviceID: deviceID,
                lease: lease,
                result: "error:\(error.code)",
                started: started
            )
            throw error
        } catch {
            _ = await record(
                operation: operation,
                request: request,
                deviceID: deviceID,
                lease: lease,
                result: "error:internal",
                started: started
            )
            throw OpenSimError(code: .internalError, message: String(describing: error))
        }
    }

    private func handleSessionList(
        request: OperationRequest,
        operation: OpenSimCore.Operation
    ) async throws -> OperationResult {
        let sessions = await self.sessions.list()
        let leases = await self.leases.activeLeases()
        let result = SessionListResult(sessions: sessions, leases: leases)
        let data = try OpenSimJSON.encoder(pretty: false).encode(result)
        let auditEvent = await record(
            operation: operation,
            request: request,
            deviceID: nil,
            lease: nil,
            result: "ok",
            started: Date()
        )
        return OperationResult(operation: operation.mcpName, data: data, auditID: auditEvent?.id)
    }

    private func handleSessionAcquire(
        request: OperationRequest,
        operation: OpenSimCore.Operation,
        parameters: OperationParameters
    ) async throws -> OperationResult {
        guard let sessionID = request.sessionID else {
            throw OpenSimError.invalidArgument("session_acquire requires sessionID")
        }
        guard let session = await sessions.session(sessionID) else {
            throw OpenSimError.invalidArgument("Session does not exist: \(sessionID.rawValue)")
        }
        let device = try await resolveDevice(parameters)
        let modeRaw = parameters.optionalString("mode") ?? LeaseMode.control.rawValue
        guard let mode = LeaseMode(rawValue: modeRaw) else {
            throw OpenSimError.invalidArgument("mode must be control or observe")
        }
        let ttl = try parameters.int("ttlSeconds", default: 300)
        let lease = try await leases.acquire(
            device: device,
            session: sessionID,
            mode: mode,
            ttlSeconds: ttl,
            ownerName: session.clientName,
            takeover: false
        )
        _ = try? await events.publish(type: .leaseChanged, payload: LeaseChangedPayload(lease: lease, reason: "acquired"))
        let data = try OpenSimJSON.encoder(pretty: false).encode(lease)
        let auditEvent = await record(
            operation: operation,
            request: request,
            deviceID: device,
            lease: lease,
            result: "ok",
            started: Date()
        )
        return OperationResult(operation: operation.mcpName, data: data, auditID: auditEvent?.id)
    }

    private func handleSessionRelease(
        request: OperationRequest,
        operation: OpenSimCore.Operation,
        parameters: OperationParameters
    ) async throws -> OperationResult {
        guard let sessionID = request.sessionID else {
            throw OpenSimError.invalidArgument("session_release requires sessionID")
        }
        let leaseID = LeaseID(try parameters.string("leaseID"))
        let released = await leases.release(leaseID, session: sessionID)
        let ack = OperationAck(
            ok: released,
            message: released ? "Lease released" : "Lease not found or not owned by this session"
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(ack)
        let auditEvent = await record(
            operation: operation,
            request: request,
            deviceID: nil,
            lease: nil,
            result: released ? "ok" : "error:lease_revoked",
            started: Date()
        )
        return OperationResult(operation: operation.mcpName, data: data, auditID: auditEvent?.id)
    }

    private func resolveDevice(_ parameters: OperationParameters) async throws -> DeviceID {
        let query = parameters.optionalString("device")
        let devices = try await bridge.devices.listDevices()
        return try DeviceResolver.resolve(query: query, in: devices).id
    }

    private func record(
        operation: OpenSimCore.Operation,
        request: OperationRequest,
        deviceID: DeviceID?,
        lease: Lease?,
        result: String,
        started: Date
    ) async -> AuditEvent? {
        let event = AuditEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            actor: request.sessionID?.rawValue ?? "cli",
            sessionID: request.sessionID,
            leaseID: lease?.id ?? request.leaseID,
            action: operation.mcpName,
            target: deviceID?.rawValue ?? request.parameters["device"] ?? operation.mcpName,
            result: result,
            durationMs: Int(Date().timeIntervalSince(started) * 1_000)
        )
        do {
            try await audit.append(event)
            return event
        } catch {
            logger.error("Audit append failed: \(String(describing: error))")
            return nil
        }
    }
}
