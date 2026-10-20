import Foundation
import Hummingbird
import OpenSimCore
import OpenSimProtocol

public enum SessionRoutes {
    public static func register(on router: Router<BasicRequestContext>, services: DaemonServices) {
        router.post("/v1/sessions") { request, _ in
            let body = try await DaemonHTTP.decode(request, as: CreateSessionRequest.self)
            let session = await services.sessions.create(clientKind: body.clientKind, clientName: body.clientName)
            _ = try? await services.events.publish(type: .sessionCreated, payload: SessionChangedPayload(session: session))
            await record(services: services, action: "session.create", target: session.id.rawValue, sessionID: session.id, leaseID: nil)
            return try DaemonHTTP.json(session)
        }

        router.delete("/v1/sessions/:id") { _, context in
            let sessionID = SessionID(try parameter(context, "id", named: "session id"))
            let released = await services.leases.releaseAll(session: sessionID)
            let closed = await services.sessions.close(sessionID)
            if closed {
                _ = try? await services.events.publish(
                    type: .sessionClosed,
                    payload: ["sessionID": sessionID.rawValue]
                )
            }
            await record(services: services, action: "session.close", target: sessionID.rawValue, sessionID: sessionID, leaseID: nil)
            return try DaemonHTTP.json(
                OperationAck(ok: closed, message: "Released \(released.count) leases")
            )
        }

        router.post("/v1/leases") { request, _ in
            let body = try await DaemonHTTP.decode(request, as: AcquireLeaseRequest.self)
            guard let session = await services.sessions.session(body.sessionID) else {
                throw OpenSimError.invalidArgument("Session does not exist: \(body.sessionID.rawValue)")
            }
            let lease = try await services.leases.acquire(
                device: body.deviceID,
                session: body.sessionID,
                mode: body.mode,
                ttlSeconds: body.ttlSeconds,
                ownerName: body.ownerName ?? session.clientName,
                takeover: body.takeover ?? false
            )
            _ = try? await services.events.publish(type: .leaseChanged, payload: LeaseChangedPayload(lease: lease, reason: "acquired"))
            await record(
                services: services,
                action: "lease.acquire",
                target: lease.deviceID.rawValue,
                sessionID: lease.sessionID,
                leaseID: lease.id
            )
            return try DaemonHTTP.json(lease)
        }

        router.post("/v1/leases/:id/heartbeat") { request, context in
            let leaseID = LeaseID(try parameter(context, "id", named: "lease id"))
            let body = try await DaemonHTTP.decode(request, as: HeartbeatRequest.self)
            let lease = try await services.leases.heartbeat(leaseID, session: body.sessionID, ttlSeconds: body.ttlSeconds)
            _ = try? await services.events.publish(type: .leaseChanged, payload: LeaseChangedPayload(lease: lease, reason: "heartbeat"))
            return try DaemonHTTP.json(lease)
        }

        router.delete("/v1/leases/:id") { request, context in
            let leaseID = LeaseID(try parameter(context, "id", named: "lease id"))
            let items = URLComponents(string: "?\(request.uri.query ?? "")")?.queryItems ?? []
            guard let sessionRaw = items.first(where: { $0.name == "sessionID" })?.value else {
                throw OpenSimError.invalidArgument("sessionID query parameter is required")
            }
            let sessionID = SessionID(sessionRaw)
            let released = await services.leases.release(leaseID, session: sessionID)
            if released {
                await record(
                    services: services,
                    action: "lease.release",
                    target: leaseID.rawValue,
                    sessionID: sessionID,
                    leaseID: leaseID
                )
            }
            return try DaemonHTTP.json(LeaseReleaseResult(leaseID: leaseID, released: released))
        }
    }

    private static func parameter(_ context: BasicRequestContext, _ name: String, named label: String) throws -> String {
        guard let value = context.parameters.get(name), !value.isEmpty else {
            throw OpenSimError.invalidArgument("Missing \(label)")
        }
        return value
    }

    private static func record(
        services: DaemonServices,
        action: String,
        target: String,
        sessionID: SessionID?,
        leaseID: LeaseID?
    ) async {
        let event = AuditEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            actor: sessionID?.rawValue ?? "http",
            sessionID: sessionID,
            leaseID: leaseID,
            action: action,
            target: target,
            result: "ok",
            durationMs: 0
        )
        try? await services.audit.append(event)
    }
}
