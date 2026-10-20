import Foundation
import OpenSimCore

public actor LeaseManager {
    private var leases: [LeaseID: Lease] = [:]
    private let defaultTTL: TimeInterval
    private let takeoverGrace: TimeInterval
    private let now: @Sendable () -> Date
    private let idGenerator: @Sendable () -> LeaseID

    public init(
        defaultTTL: TimeInterval = 300,
        takeoverGrace: TimeInterval = 3,
        now: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> LeaseID = { LeaseID(UUID().uuidString) }
    ) {
        self.defaultTTL = defaultTTL
        self.takeoverGrace = takeoverGrace
        self.now = now
        self.idGenerator = idGenerator
    }

    public func acquire(
        device: DeviceID,
        session: SessionID,
        mode: LeaseMode,
        ttlSeconds: Int?,
        ownerName: String,
        takeover: Bool
    ) async throws -> Lease {
        _ = expireIfNeeded()
        let ttl = validatedTTL(ttlSeconds)

        if mode == .control {
            if let holder = controlLease(device: device) {
                if holder.sessionID == session {
                    return renew(holder, ttl: ttl)
                }
                guard takeover else {
                    throw conflictError(holder)
                }
                if takeoverGrace > 0 {
                    try await Task.sleep(for: .milliseconds(Int64(takeoverGrace * 1_000)))
                }
                _ = expireIfNeeded()
                if let current = controlLease(device: device), current.sessionID != session {
                    leases.removeValue(forKey: current.id)
                }
            }
        }

        let timestamp = now()
        let lease = Lease(
            id: idGenerator(),
            deviceID: device,
            sessionID: session,
            mode: mode,
            ownerName: ownerName,
            acquiredAt: timestamp,
            expiresAt: timestamp.addingTimeInterval(ttl)
        )
        leases[lease.id] = lease
        return lease
    }

    public func heartbeat(_ id: LeaseID, session: SessionID, ttlSeconds: Int?) throws -> Lease {
        _ = expireIfNeeded()
        guard var lease = leases[id] else {
            throw revokedError(id)
        }
        guard lease.sessionID == session else {
            throw conflictError(lease)
        }
        lease.expiresAt = now().addingTimeInterval(validatedTTL(ttlSeconds))
        leases[id] = lease
        return lease
    }

    public func release(_ id: LeaseID, session: SessionID) -> Bool {
        guard let lease = leases[id], lease.sessionID == session else {
            return false
        }
        leases.removeValue(forKey: id)
        return true
    }

    public func releaseAll(session: SessionID) -> [Lease] {
        let owned = leases.values.filter { $0.sessionID == session }
        for lease in owned {
            leases.removeValue(forKey: lease.id)
        }
        return owned
    }

    public func validate(device: DeviceID, leaseID: LeaseID?, session: SessionID) throws {
        _ = expireIfNeeded()
        guard let leaseID else {
            throw OpenSimError(
                code: .leaseRequired,
                message: "A control lease is required for this operation",
                details: ["device": device.rawValue],
                recovery: "Run `opensim session acquire --device <udid> --mode control`",
                retryable: false
            )
        }
        guard let lease = leases[leaseID] else {
            throw revokedError(leaseID)
        }
        guard lease.sessionID == session else {
            throw conflictError(lease)
        }
        guard lease.deviceID == device else {
            throw OpenSimError(
                code: .leaseConflict,
                message: "Lease belongs to another device",
                details: ["leaseDevice": lease.deviceID.rawValue, "requestedDevice": device.rawValue],
                recovery: "Acquire a lease for the requested device",
                retryable: false
            )
        }
        guard lease.mode == .control else {
            throw OpenSimError(
                code: .leaseRequired,
                message: "Control mode is required for write operations",
                details: ["mode": lease.mode.rawValue],
                recovery: "Acquire a control lease",
                retryable: false
            )
        }
    }

    public func expireIfNeeded() -> [Lease] {
        let timestamp = now()
        let expired = leases.values.filter { $0.expiresAt <= timestamp }
        for lease in expired {
            leases.removeValue(forKey: lease.id)
        }
        return expired.sorted { $0.expiresAt < $1.expiresAt }
    }

    public func activeLeases() -> [Lease] {
        _ = expireIfNeeded()
        return leases.values.sorted { $0.acquiredAt < $1.acquiredAt }
    }

    public func leases(for session: SessionID) -> [Lease] {
        _ = expireIfNeeded()
        return leases.values.filter { $0.sessionID == session }
    }

    private func controlLease(device: DeviceID) -> Lease? {
        leases.values.first { $0.deviceID == device && $0.mode == .control }
    }

    private func renew(_ lease: Lease, ttl: TimeInterval) -> Lease {
        var updated = lease
        updated.expiresAt = now().addingTimeInterval(ttl)
        leases[lease.id] = updated
        return updated
    }

    private func validatedTTL(_ ttlSeconds: Int?) -> TimeInterval {
        let requested = TimeInterval(ttlSeconds ?? Int(defaultTTL))
        return min(max(requested, 1), 3_600)
    }

    private func revokedError(_ id: LeaseID) -> OpenSimError {
        OpenSimError(
            code: .leaseRevoked,
            message: "Lease no longer exists",
            details: ["leaseID": id.rawValue],
            recovery: "Acquire a new lease",
            retryable: true
        )
    }

    private func conflictError(_ lease: Lease) -> OpenSimError {
        OpenSimError(
            code: .leaseConflict,
            message: "Device is controlled by another session",
            details: [
                "owner": lease.ownerName,
                "mode": lease.mode.rawValue,
                "expiresAt": OpenSimDate.string(from: lease.expiresAt),
                "leaseID": lease.id.rawValue,
            ],
            recovery: "Take control or wait for the lease to expire",
            retryable: true
        )
    }
}
