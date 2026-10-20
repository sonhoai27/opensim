import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimBridge
@testable import OpenSimCore

final class DaemonClientTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    func testClientHealthSessionLeaseAndDevices() async throws {
        let executor = DaemonStubSimctlExecutor()
        let harness = try await RouteTestHarness.start(executor: executor)
        defer { harness.server.stop() }
        let client = DaemonClient(
            baseURL: URL(string: "http://127.0.0.1:\(harness.server.port)")!,
            token: harness.token
        )
        let health = try await client.health()
        XCTAssertEqual(health.status, "ok")

        let session = try await client.createSession(clientKind: "cli", clientName: "test")
        let lease = try await client.acquireLease(AcquireLeaseRequest(deviceID: udid, sessionID: session.id, mode: .control))
        XCTAssertEqual(lease.mode, .control)
        let renewed = try await client.heartbeatLease(lease.id, sessionID: session.id, ttlSeconds: 600)
        XCTAssertGreaterThanOrEqual(renewed.expiresAt, lease.expiresAt)
        let released = try await client.releaseLease(lease.id, sessionID: session.id)
        XCTAssertTrue(released.released)

        await executor.enqueue(SimctlOutput(
            status: 0,
            stdout: Data("""
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"95B3747B-7065-447E-AB1E-53065142C3FC","name":"iPhone Air","state":"Booted","isAvailable":true}]}}
            """.utf8),
            stderr: Data()
        ))
        let devices = try await client.devices()
        XCTAssertEqual(devices.map(\.name), ["iPhone Air"])
    }

    func testClientSurfacesDaemonErrorCodes() async throws {
        let harness = try await RouteTestHarness.start(executor: DaemonStubSimctlExecutor())
        defer { harness.server.stop() }
        let client = DaemonClient(
            baseURL: URL(string: "http://127.0.0.1:\(harness.server.port)")!,
            token: harness.token
        )
        do {
            _ = try await client.operation(OperationRequest(
                operation: "device_shutdown",
                parameters: ["device": udid.rawValue]
            ))
            XCTFail("expected lease_required")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "lease_required")
        }
    }

    func testClientReadsSSEStream() async throws {
        let harness = try await RouteTestHarness.start(executor: DaemonStubSimctlExecutor())
        defer { harness.server.stop() }
        let published = try await harness.services.events.publish(
            type: .daemonHealth,
            payload: DaemonHealthPayload(status: "ok", pid: 3, port: 4321)
        )
        let client = DaemonClient(
            baseURL: URL(string: "http://127.0.0.1:\(harness.server.port)")!,
            token: harness.token
        )
        var stream = client.events(lastEventID: "0").makeAsyncIterator()
        let received = try await stream.next()
        XCTAssertEqual(received?.id, published.id)
        XCTAssertEqual(received?.type, .daemonHealth)
    }
}
