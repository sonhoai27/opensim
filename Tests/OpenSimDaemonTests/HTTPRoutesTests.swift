import Logging
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimBridge
@testable import OpenSimCore

final class HTTPRoutesTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    private func makeServer(executor: DaemonStubSimctlExecutor, token: String) async throws -> RunningDaemonServer {
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
            .appendingPathComponent("opensim-http-\(UUID().uuidString)", isDirectory: true)
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
        return try await DaemonServer.start(services: services, token: token, port: port)
    }

    func testHealthNeedsNoTokenAndDevicesNeedsToken() async throws {
        let token = "test-token"
        let executor = DaemonStubSimctlExecutor()
        let server = try await makeServer(executor: executor, token: token)
        defer { server.stop() }
        let base = URL(string: "http://127.0.0.1:\(server.port)")!

        let health = try await URLSession.shared.data(from: base.appendingPathComponent("v1/health"))
        XCTAssertEqual((health.1 as? HTTPURLResponse)?.statusCode, 200)
        let healthEnvelope = try OpenSimJSON.decoder().decode(Envelope<HealthResponse>.self, from: health.0)
        XCTAssertTrue(healthEnvelope.ok)
        XCTAssertEqual(healthEnvelope.data?.protocolVersion, 1)

        let unauthorized = try await URLSession.shared.data(from: base.appendingPathComponent("v1/devices"))
        XCTAssertEqual((unauthorized.1 as? HTTPURLResponse)?.statusCode, 401)

        await executor.enqueue(SimctlOutput(
            status: 0,
            stdout: Data("""
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"95B3747B-7065-447E-AB1E-53065142C3FC","name":"iPhone Air","state":"Booted","isAvailable":true}]}}
            """.utf8),
            stderr: Data()
        ))
        var request = URLRequest(url: base.appendingPathComponent("v1/devices"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let authorized = try await URLSession.shared.data(for: request)
        XCTAssertEqual((authorized.1 as? HTTPURLResponse)?.statusCode, 200)
        let devicesEnvelope = try OpenSimJSON.decoder().decode(Envelope<[Device]>.self, from: authorized.0)
        XCTAssertEqual(devicesEnvelope.data?.map(\.id), [udid])
    }

    func testWrongTokenIsRejected() async throws {
        let server = try await makeServer(executor: DaemonStubSimctlExecutor(), token: "right-token")
        defer { server.stop() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/v1/devices")!)
        request.setValue("Bearer wrong-token", forHTTPHeaderField: "Authorization")
        let response = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response.1 as? HTTPURLResponse)?.statusCode, 401)
        let envelope = try OpenSimJSON.decoder().decode(Envelope<EmptyPayload>.self, from: response.0)
        XCTAssertFalse(envelope.ok)
        XCTAssertEqual(envelope.error?.code, "permission_denied")
    }
}
