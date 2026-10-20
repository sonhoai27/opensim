import Logging
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimBridge
@testable import OpenSimCore

struct EmptyBody: Encodable {}

struct RouteTestHarness {
    let server: RunningDaemonServer
    let token: String
    let services: DaemonServices
    let executor: DaemonStubSimctlExecutor

    static func start(
        executor: DaemonStubSimctlExecutor,
        routeProviders: [any DaemonRouteProvider] = []
    ) async throws -> RouteTestHarness {
        let devices = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        let runtimes = SimctlRuntimeService(executor: executor, timeout: .seconds(5))
        let apps = SimctlAppService(executor: executor, timeout: .seconds(5))
        let logs = SimctlLogService(executor: executor, timeout: .seconds(5))
        let bridge = SimctlBridge(
            devices: devices,
            runtimes: runtimes,
            apps: apps,
            logs: logs,
            crashReports: CrashReportService(devices: devices),
            doctor: DispatcherTestDoctor(),
            capabilityProvider: {
                BridgeCapabilities(
                    render: .unavailable,
                    hid: .unavailable,
                    accessibility: .unavailable,
                    screenshot: .available,
                    video: .available,
                    watch: .unavailable,
                    tv: .unavailable
                )
            }
        )
        let catalog = OperationCatalog.plan3()
        let sessions = SessionManager()
        let leases = LeaseManager(takeoverGrace: 0)
        let events = EventHub()
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-routes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audit = AuditWriter(fileURL: root.appendingPathComponent("audit.jsonl"))
        let dispatcher = OperationDispatcher(
            catalog: catalog,
            executor: BridgeOperationExecutor(bridge: bridge, crashReports: bridge, doctor: bridge, catalog: catalog),
            bridge: bridge,
            sessions: sessions,
            leases: leases,
            audit: audit,
            events: events,
            logger: Logger(label: "test")
        )
        let port = try PortAllocator.freePort()
        let token = "test-token"
        let state = DaemonState(
            pid: 1,
            port: port,
            token: token,
            version: "0.1.0",
            xcodeVersion: "27.1",
            startedAt: Date(timeIntervalSince1970: 1_797_000_000)
        )
        let services = DaemonServices(
            bridge: bridge,
            dispatcher: dispatcher,
            sessions: sessions,
            leases: leases,
            events: events,
            audit: audit,
            state: state,
            capabilities: await bridge.capabilities
        )
        let server = try await DaemonServer.start(
            services: services,
            token: token,
            port: port,
            routeProviders: routeProviders
        )
        return RouteTestHarness(server: server, token: token, services: services, executor: executor)
    }

    func send<T: Decodable>(_ method: String, _ path: String, as type: T.Type) async throws -> (Int, Envelope<T>) {
        try await send(method, path, body: Optional<EmptyBody>.none, as: type)
    }

    func send<Body: Encodable, T: Decodable>(
        _ method: String,
        _ path: String,
        body: Body?,
        as type: T.Type
    ) async throws -> (Int, Envelope<T>) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try OpenSimJSON.encoder(pretty: false).encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, try OpenSimJSON.decoder().decode(Envelope<T>.self, from: data))
    }
}

final class SessionAndOperationRoutesTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    func testLeaseConflictAndObserveFlow() async throws {
        let harness = try await RouteTestHarness.start(executor: DaemonStubSimctlExecutor())
        defer { harness.server.stop() }

        let (_, firstSession) = try await harness.send(
            "POST",
            "/v1/sessions",
            body: CreateSessionRequest(clientKind: "test", clientName: "first"),
            as: Session.self
        )
        let (_, secondSession) = try await harness.send(
            "POST",
            "/v1/sessions",
            body: CreateSessionRequest(clientKind: "test", clientName: "second"),
            as: Session.self
        )

        let (leaseStatus, firstLease) = try await harness.send(
            "POST",
            "/v1/leases",
            body: AcquireLeaseRequest(deviceID: udid, sessionID: try XCTUnwrap(firstSession.data?.id), mode: .control),
            as: Lease.self
        )
        XCTAssertEqual(leaseStatus, 200)
        XCTAssertEqual(firstLease.data?.mode, .control)

        let (conflictStatus, conflict) = try await harness.send(
            "POST",
            "/v1/leases",
            body: AcquireLeaseRequest(deviceID: udid, sessionID: try XCTUnwrap(secondSession.data?.id), mode: .control),
            as: Lease.self
        )
        XCTAssertEqual(conflictStatus, 409)
        XCTAssertEqual(conflict.error?.code, "lease_conflict")

        let (observeStatus, observe) = try await harness.send(
            "POST",
            "/v1/leases",
            body: AcquireLeaseRequest(deviceID: udid, sessionID: try XCTUnwrap(secondSession.data?.id), mode: .observe),
            as: Lease.self
        )
        XCTAssertEqual(observeStatus, 200)
        XCTAssertEqual(observe.data?.mode, .observe)
    }

    func testOperationRoutesListSessions() async throws {
        let harness = try await RouteTestHarness.start(executor: DaemonStubSimctlExecutor())
        defer { harness.server.stop() }
        _ = try await harness.send(
            "POST",
            "/v1/sessions",
            body: CreateSessionRequest(clientKind: "test", clientName: "one"),
            as: Session.self
        )

        let (status, envelope) = try await harness.send(
            "POST",
            "/v1/operations",
            body: OperationRequest(operation: "session_list"),
            as: OperationResult.self
        )
        XCTAssertEqual(status, 200)
        let result = try XCTUnwrap(envelope.data)
        let list = try result.decoded(SessionListResult.self)
        XCTAssertEqual(list.sessions.count, 1)
    }

    func testOperationWithoutLeaseReturnsConflict() async throws {
        let harness = try await RouteTestHarness.start(executor: DaemonStubSimctlExecutor())
        defer { harness.server.stop() }
        let (status, envelope) = try await harness.send(
            "POST",
            "/v1/operations",
            body: OperationRequest(operation: "device_shutdown", parameters: ["device": udid.rawValue]),
            as: OperationResult.self
        )
        XCTAssertEqual(status, 409)
        XCTAssertEqual(envelope.error?.code, "lease_required")
    }
}
