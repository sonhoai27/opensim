import Logging
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimBridge
@testable import OpenSimCore

actor DaemonStubSimctlExecutor: SimctlExecuting {
    private var outputs: [SimctlOutput] = []

    func enqueue(_ output: SimctlOutput) {
        outputs.append(output)
    }

    func run(_ command: SimctlCommand, timeout: Duration) async throws -> SimctlOutput {
        guard !outputs.isEmpty else {
            throw OpenSimError(code: .internalError, message: "stub has no output")
        }
        return outputs.removeFirst()
    }
}

struct DispatcherTestDoctor: DoctorReporting {
    func doctorReport() async throws -> DoctorReport {
        throw OpenSimError(code: .internalError, message: "not used")
    }
}

final class OperationDispatcherTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    private func makeServices(catalog: OperationCatalog) -> (OperationDispatcher, SessionManager, LeaseManager, EventHub) {
        let executor = DaemonStubSimctlExecutor()
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
        let sessions = SessionManager()
        let leases = LeaseManager(takeoverGrace: 0)
        let events = EventHub()
        let auditURL = URL(fileURLWithPath: "/tmp/opensim-dispatch-\(UUID().uuidString).jsonl")
        let dispatcher = OperationDispatcher(
            catalog: catalog,
            executor: BridgeOperationExecutor(bridge: bridge, crashReports: bridge, doctor: bridge, catalog: catalog),
            bridge: bridge,
            sessions: sessions,
            leases: leases,
            audit: AuditWriter(fileURL: auditURL),
            events: events,
            logger: Logger(label: "test")
        )
        return (dispatcher, sessions, leases, events)
    }

    func testWriteWithoutSessionReturnsLeaseRequired() async throws {
        let (dispatcher, _, _, _) = makeServices(catalog: OperationCatalog.plan3())
        do {
            _ = try await dispatcher.dispatch(OperationRequest(
                operation: "device_shutdown",
                parameters: ["device": udid.rawValue, "wait": "false"]
            ))
            XCTFail("expected lease_required")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "lease_required")
        }
    }

    func testDestructiveWithoutConfirmReturnsConfirmationRequired() async throws {
        let (dispatcher, sessions, _, _) = makeServices(catalog: OperationCatalog.plan3())
        let session = await sessions.create(clientKind: "test", clientName: "test")
        do {
            _ = try await dispatcher.dispatch(OperationRequest(
                operation: "device_erase",
                parameters: ["device": udid.rawValue, "confirm": "false"],
                sessionID: session.id
            ))
            XCTFail("expected confirmation_required")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "confirmation_required")
        }
    }

    func testOptionalServiceReturnsCapabilityUnavailable() async throws {
        let extra = Operation(
            cliPath: ["test", "capability"],
            mcpName: "test_capability",
            summary: "Capability probe",
            requiresControlLease: false,
            destructive: false,
            readOnly: false,
            parameters: [OperationParameter(name: "device", type: "string", required: true)],
            requiredService: .screen
        )
        var catalog = OperationCatalog.plan3()
        catalog.register(extra)
        let (dispatcher, _, _, _) = makeServices(catalog: catalog)
        do {
            _ = try await dispatcher.dispatch(OperationRequest(
                operation: "test_capability",
                parameters: ["device": udid.rawValue]
            ))
            XCTFail("expected capability_unavailable")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "capability_unavailable")
            XCTAssertEqual(error.details["capability"], "screen")
        }
    }

    func testSessionListRequiresNoLease() async throws {
        let (dispatcher, sessions, _, _) = makeServices(catalog: OperationCatalog.plan3())
        _ = await sessions.create(clientKind: "cli", clientName: "test")
        let result = try await dispatcher.dispatch(OperationRequest(operation: "session_list"))
        let list = try result.decoded(SessionListResult.self)
        XCTAssertEqual(list.sessions.count, 1)
    }
}
