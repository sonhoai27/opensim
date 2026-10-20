import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

actor StubSimctlExecutor: SimctlExecuting {
    private var outputs: [SimctlOutput] = []
    private(set) var commands: [SimctlCommand] = []

    func enqueue(_ output: SimctlOutput) {
        outputs.append(output)
    }

    func run(_ command: SimctlCommand, timeout: Duration) async throws -> SimctlOutput {
        commands.append(command)
        guard !outputs.isEmpty else {
            throw OpenSimError(code: .internalError, message: "stub has no output for \(command.displayString)")
        }
        return outputs.removeFirst()
    }
}

func jsonOutput(_ text: String, status: Int32 = 0) -> SimctlOutput {
    SimctlOutput(status: status, stdout: Data(text.utf8), stderr: Data())
}

let deviceListJSON = """
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"95B3747B-7065-447E-AB1E-53065142C3FC","name":"iPhone Air","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-Air","dataPath":"/tmp/device-data"}]}}
"""

final class SimctlDeviceServiceTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    func testListDevicesParsesRuntimeAndState() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(deviceListJSON))
        let service = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        let devices = try await service.listDevices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].id, udid)
        XCTAssertEqual(devices[0].platform, .iOS)
        XCTAssertEqual(devices[0].state, .booted)
        XCTAssertEqual(devices[0].runtime, RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"))
    }

    func testGetMissingDeviceThrowsNotFound() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(deviceListJSON))
        let service = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        do {
            _ = try await service.device(DeviceID("11111111-1111-1111-1111-111111111111"))
            XCTFail("expected device_not_found")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "device_not_found")
        }
    }

    func testBootWhenAlreadyBootedDoesNotCallBoot() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(deviceListJSON))
        let service = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        let device = try await service.boot(udid, wait: false)
        XCTAssertEqual(device.state, .booted)
        let commands = await executor.commands
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].arguments, ["list", "devices", "-j"])
    }

    func testBootWaitUsesBootStatus() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("""
        {"devices":{"runtime":[{"udid":"95B3747B-7065-447E-AB1E-53065142C3FC","name":"iPhone Air","state":"Shutdown","isAvailable":true}]}}
        """))
        await executor.enqueue(jsonOutput(""))
        await executor.enqueue(jsonOutput("""
        {"devices":{"runtime":[{"udid":"95B3747B-7065-447E-AB1E-53065142C3FC","name":"iPhone Air","state":"Booted","isAvailable":true}]}}
        """))
        let service = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        let device = try await service.boot(udid, wait: true)
        XCTAssertEqual(device.state, .booted)
        let commands = await executor.commands
        XCTAssertEqual(commands.map(\.arguments), [
            ["list", "devices", "-j"],
            ["bootstatus", udid.rawValue, "-b"],
            ["list", "devices", "-j"],
        ])
    }

    func testEraseBootedDeviceReturnsBusy() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(deviceListJSON))
        let service = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        do {
            _ = try await service.erase(udid)
            XCTFail("expected device_busy")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "device_busy")
        }
        let commands = await executor.commands
        XCTAssertEqual(commands.count, 1)
    }

    func testDeleteRunsDeleteCommand() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(""))
        let service = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        try await service.delete(udid)
        let commands = await executor.commands
        XCTAssertEqual(commands[0].arguments, ["delete", udid.rawValue])
    }
}
