import Foundation
import OpenSimCore

public struct SimctlDeviceService: DeviceControlling {
    private let executor: any SimctlExecuting
    private let timeout: Duration

    public init(executor: any SimctlExecuting, timeout: Duration) {
        self.executor = executor
        self.timeout = timeout
    }

    public func listDevices() async throws -> [Device] {
        let command = SimctlArguments.listDevicesJSON()
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let payload = try OpenSimJSON.decoder().decode(SimctlDeviceListPayload.self, from: output.stdout)
        var devices: [Device] = []
        for (runtimeIdentifier, entries) in payload.devices {
            for entry in entries {
                devices.append(map(entry, runtimeIdentifier: runtimeIdentifier))
            }
        }
        return devices.sorted {
            if $0.name == $1.name {
                return $0.id.rawValue < $1.id.rawValue
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func device(_ id: DeviceID) async throws -> Device {
        let devices = try await listDevices()
        guard let match = devices.first(where: { $0.id == id }) else {
            throw OpenSimError.deviceNotFound(id)
        }
        return match
    }

    public func createDevice(name: String, deviceType: String, runtime: RuntimeID?) async throws -> Device {
        try IdentifierValidation.validateName(name, field: "name")
        try IdentifierValidation.validateName(deviceType, field: "deviceType")
        let command = SimctlArguments.createDevice(name: name, deviceType: deviceType, runtime: runtime)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let text = String(decoding: output.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let newID = text.split(separator: "\n").last.map(String.init), IdentifierValidation.isUDID(newID) else {
            throw OpenSimError(
                code: .simctlFailed,
                message: "simctl create did not return a UDID",
                details: ["stdout": text],
                recovery: "Check `xcrun simctl list devices` and delete the partial device"
            )
        }
        return try await device(DeviceID(newID))
    }

    public func cloneDevice(_ id: DeviceID, name: String) async throws -> Device {
        try IdentifierValidation.validateName(name, field: "name")
        _ = try await device(id)
        let command = SimctlArguments.cloneDevice(id, name: name)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let text = String(decoding: output.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let newID = text.split(separator: "\n").last.map(String.init), IdentifierValidation.isUDID(newID) else {
            throw OpenSimError(
                code: .simctlFailed,
                message: "simctl clone did not return a UDID",
                details: ["stdout": text]
            )
        }
        return try await device(DeviceID(newID))
    }

    public func boot(_ id: DeviceID, wait: Bool) async throws -> Device {
        let current = try await device(id)
        if current.state == .booted {
            return current
        }
        if current.state == .booting {
            return wait ? try await waitForState(id, .booted) : current
        }
        if wait {
            let command = SimctlArguments.bootStatus(id)
            let output = try await executor.run(command, timeout: timeout)
            try SimctlErrorMapper.requireSuccess(command: command, output: output)
            return try await waitForState(id, .booted)
        }
        let command = SimctlArguments.boot(id)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        return try await device(id)
    }

    public func shutdown(_ id: DeviceID, wait: Bool) async throws -> Device {
        let current = try await device(id)
        if current.state == .shutdown {
            return current
        }
        let command = SimctlArguments.shutdown(id)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        if wait {
            return try await waitForState(id, .shutdown)
        }
        return try await device(id)
    }

    public func erase(_ id: DeviceID) async throws -> Device {
        let current = try await device(id)
        guard current.state == .shutdown else {
            throw OpenSimError(
                code: .deviceBusy,
                message: "Device must be shut down before erase",
                details: ["udid": id.rawValue, "state": current.state.rawValue],
                recovery: "Run `opensim device shutdown --device \(id.rawValue) --wait` first"
            )
        }
        let command = SimctlArguments.erase(id)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        return try await device(id)
    }

    public func delete(_ id: DeviceID) async throws {
        let command = SimctlArguments.delete(id)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
    }

    public func rename(_ id: DeviceID, to name: String) async throws -> Device {
        try IdentifierValidation.validateName(name, field: "name")
        _ = try await device(id)
        let command = SimctlArguments.rename(id, to: name)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        return try await device(id)
    }

    public func pair(watch: DeviceID, phone: DeviceID) async throws {
        _ = try await device(watch)
        _ = try await device(phone)
        let command = SimctlArguments.pair(watch: watch, phone: phone)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
    }

    private func map(_ entry: SimctlDevicePayload, runtimeIdentifier: String) -> Device {
        Device(
            id: DeviceID(entry.udid),
            name: entry.name,
            platform: Device.platform(forRuntimeIdentifier: runtimeIdentifier),
            deviceType: entry.deviceTypeIdentifier ?? "",
            runtime: RuntimeID(runtimeIdentifier),
            state: Device.parseState(entry.state),
            isAvailable: entry.isAvailable ?? true,
            dataPath: entry.dataPath,
            lastBootedAt: entry.lastBootedAt
        )
    }

    private func waitForState(_ id: DeviceID, _ expected: DeviceState) async throws -> Device {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let current = try await device(id)
            if current.state == expected {
                return current
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw OpenSimError(
            code: .deviceBusy,
            message: "Timed out waiting for device \(id.rawValue) to become \(expected.rawValue)",
            details: ["udid": id.rawValue, "expectedState": expected.rawValue],
            recovery: "Increase --timeout and retry",
            retryable: true
        )
    }
}
