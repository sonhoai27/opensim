import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

struct TestDoctor: DoctorReporting {
    func doctorReport() async throws -> DoctorReport {
        throw OpenSimError(code: .internalError, message: "not used")
    }
}

final class BridgeOperationExecutorTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    private func makeBridge(executor: StubSimctlExecutor) -> SimctlBridge {
        let devices = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        let runtimes = SimctlRuntimeService(executor: executor, timeout: .seconds(5))
        let apps = SimctlAppService(executor: executor, timeout: .seconds(5))
        let logs = SimctlLogService(executor: executor, timeout: .seconds(5))
        let crashes = CrashReportService(devices: devices)
        let doctor = TestDoctor()
        let capabilities = BridgeCapabilities(
            render: .unavailable,
            hid: .unavailable,
            accessibility: .unavailable,
            screenshot: .available,
            video: .available,
            watch: .unavailable,
            tv: .unavailable
        )
        return SimctlBridge(
            devices: devices,
            runtimes: runtimes,
            apps: apps,
            logs: logs,
            crashReports: crashes,
            doctor: doctor,
            capabilityProvider: { capabilities }
        )
    }

    func testDeviceListReturnsJSONArray() async throws {
        let stub = StubSimctlExecutor()
        await stub.enqueue(jsonOutput(deviceListJSON))
        let bridge = makeBridge(executor: stub)
        let executor = BridgeOperationExecutor(bridge: bridge)
        let data = try await executor.execute(operation: "device_list", parameters: [:])
        let devices = try OpenSimJSON.decoder().decode([Device].self, from: data)
        XCTAssertEqual(devices.map(\.id), [udid])
    }

    func testDestructiveOperationRequiresConfirmBeforeTouchingSimctl() async throws {
        let stub = StubSimctlExecutor()
        let bridge = makeBridge(executor: stub)
        let executor = BridgeOperationExecutor(bridge: bridge)
        do {
            _ = try await executor.execute(operation: "device_erase", parameters: ["device": udid.rawValue])
            XCTFail("expected confirmation_required")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "confirmation_required")
        }
        let commands = await stub.commands
        XCTAssertEqual(commands.count, 0)
    }

    func testUnknownParameterIsRejected() async throws {
        let stub = StubSimctlExecutor()
        let bridge = makeBridge(executor: stub)
        let executor = BridgeOperationExecutor(bridge: bridge)
        do {
            _ = try await executor.execute(operation: "device_list", parameters: ["unexpected": "value"])
            XCTFail("expected invalid_argument")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "invalid_argument")
        }
    }

    func testMissingRequiredParameterIsRejected() async throws {
        let stub = StubSimctlExecutor()
        let bridge = makeBridge(executor: stub)
        let executor = BridgeOperationExecutor(bridge: bridge)
        do {
            _ = try await executor.execute(operation: "app_uninstall", parameters: ["device": udid.rawValue, "confirm": "true"])
            XCTFail("expected invalid_argument")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "invalid_argument")
        }
    }
}
