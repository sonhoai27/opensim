import XCTest
@testable import OpenSimDaemon
@testable import OpenSimCore

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}

final class LeaseManagerTests: XCTestCase {
    private let device = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")
    private let sessionA = SessionID("session-a")
    private let sessionB = SessionID("session-b")

    func testControlConflictReportsOwnerAndExpiry() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = LeaseManager(defaultTTL: 300, takeoverGrace: 0, now: { clock.now() })
        _ = try await manager.acquire(
            device: device,
            session: sessionA,
            mode: .control,
            ttlSeconds: 300,
            ownerName: "agent-a",
            takeover: false
        )
        do {
            _ = try await manager.acquire(
                device: device,
                session: sessionB,
                mode: .control,
                ttlSeconds: 300,
                ownerName: "agent-b",
                takeover: false
            )
            XCTFail("expected lease_conflict")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "lease_conflict")
            XCTAssertEqual(error.details["owner"], "agent-a")
            XCTAssertEqual(error.retryable, true)
        }
    }

    func testObserveLeasesCoexist() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = LeaseManager(defaultTTL: 300, takeoverGrace: 0, now: { clock.now() })
        let first = try await manager.acquire(device: device, session: sessionA, mode: .observe, ttlSeconds: 300, ownerName: "a", takeover: false)
        let second = try await manager.acquire(device: device, session: sessionB, mode: .observe, ttlSeconds: 300, ownerName: "b", takeover: false)
        XCTAssertNotEqual(first.id, second.id)
        let active = await manager.activeLeases()
        XCTAssertEqual(active.count, 2)
    }

    func testExpiryReleasesLeaseAndValidateReturnsRevoked() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = LeaseManager(defaultTTL: 300, takeoverGrace: 0, now: { clock.now() })
        let lease = try await manager.acquire(device: device, session: sessionA, mode: .control, ttlSeconds: 1, ownerName: "a", takeover: false)
        clock.advance(2)
        let expired = await manager.expireIfNeeded()
        XCTAssertEqual(expired.map(\.id), [lease.id])
        do {
            try await manager.validate(device: device, leaseID: lease.id, session: sessionA)
            XCTFail("expected lease_revoked")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "lease_revoked")
        }
    }

    func testHeartbeatExtendsExpiry() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = LeaseManager(defaultTTL: 300, takeoverGrace: 0, now: { clock.now() })
        let lease = try await manager.acquire(device: device, session: sessionA, mode: .control, ttlSeconds: 10, ownerName: "a", takeover: false)
        clock.advance(5)
        let renewed = try await manager.heartbeat(lease.id, session: sessionA, ttlSeconds: 300)
        XCTAssertGreaterThan(renewed.expiresAt, lease.expiresAt)
        XCTAssertEqual(renewed.expiresAt.timeIntervalSince1970, clock.now().timeIntervalSince1970 + 300, accuracy: 0.001)
    }

    func testTakeoverReplacesControlLease() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = LeaseManager(defaultTTL: 300, takeoverGrace: 0, now: { clock.now() })
        let oldLease = try await manager.acquire(device: device, session: sessionA, mode: .control, ttlSeconds: 300, ownerName: "agent-a", takeover: false)
        let newLease = try await manager.acquire(device: device, session: sessionB, mode: .control, ttlSeconds: 300, ownerName: "app", takeover: true)
        XCTAssertNotEqual(oldLease.id, newLease.id)
        let active = await manager.activeLeases().filter { $0.mode == .control }
        XCTAssertEqual(active.map(\.id), [newLease.id])
    }

    func testReleaseRequiresOwnerSession() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = LeaseManager(defaultTTL: 300, takeoverGrace: 0, now: { clock.now() })
        let lease = try await manager.acquire(device: device, session: sessionA, mode: .control, ttlSeconds: 300, ownerName: "a", takeover: false)
        let wrong = await manager.release(lease.id, session: sessionB)
        XCTAssertFalse(wrong)
        let correct = await manager.release(lease.id, session: sessionA)
        XCTAssertTrue(correct)
    }

    func testSessionManagerCreateAndClose() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = SessionManager(now: { clock.now() }, idGenerator: { SessionID("session-fixed") })
        let session = await manager.create(clientKind: "cli", clientName: "device boot")
        XCTAssertEqual(session.id, SessionID("session-fixed"))
        XCTAssertEqual(session.createdAt, clock.now())
        let closed = await manager.close(session.id)
        XCTAssertTrue(closed)
        let all = await manager.list()
        XCTAssertTrue(all.isEmpty)
    }
}
