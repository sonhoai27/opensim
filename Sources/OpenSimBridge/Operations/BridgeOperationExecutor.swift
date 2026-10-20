import Foundation
import OpenSimCore

public struct BridgeOperationExecutor: Sendable {
    public let bridge: any SimulatorBridge
    public let crashReports: (any CrashReportReading)?
    public let doctor: (any DoctorReporting)?
    public let catalog: OperationCatalog

    public init(
        bridge: any SimulatorBridge,
        crashReports: (any CrashReportReading)? = nil,
        doctor: (any DoctorReporting)? = nil,
        catalog: OperationCatalog = .plan1()
    ) {
        self.bridge = bridge
        self.crashReports = crashReports
        self.doctor = doctor
        self.catalog = catalog
    }

    public func execute(operation name: String, parameters: [String: String]) async throws -> Data {
        guard let operation = catalog.operation(forMCP: name) else {
            throw OpenSimError.invalidArgument("Unknown operation: \(name)")
        }
        let params = try OperationParameters(parameters).validated(against: operation)
        if operation.destructive, try params.bool("confirm", default: false) == false {
            throw OpenSimError.confirmationRequired(action: operation.mcpName)
        }

        switch name {
        case "device_list":
            var devices = try await bridge.devices.listDevices()
            if let platform = params.optionalString("platform") {
                devices = devices.filter { $0.platform.rawValue.caseInsensitiveCompare(platform) == .orderedSame }
            }
            if let state = params.optionalString("state") {
                let expected = Device.parseState(state)
                devices = devices.filter { $0.state == expected }
            }
            return try encode(devices)

        case "device_get", "device_status":
            let id = try await resolveDevice(params)
            let device = try await bridge.devices.device(id)
            return try encode(device)

        case "device_create":
            let name = try params.string("name")
            let deviceType = try params.string("deviceType")
            let runtime = params.optionalString("runtime").map { RuntimeID($0) }
            let device = try await bridge.devices.createDevice(
                name: name,
                deviceType: deviceType,
                runtime: runtime
            )
            return try encode(device)

        case "device_clone":
            let id = try await resolveDevice(params)
            let name = try params.string("name")
            let device = try await bridge.devices.cloneDevice(id, name: name)
            return try encode(device)

        case "device_boot":
            let id = try await resolveDevice(params)
            let device = try await bridge.devices.boot(id, wait: try params.bool("wait", default: false))
            return try encode(device)

        case "device_shutdown":
            let id = try await resolveDevice(params)
            let device = try await bridge.devices.shutdown(id, wait: try params.bool("wait", default: false))
            return try encode(device)

        case "device_erase":
            let id = try await resolveDevice(params)
            let device = try await bridge.devices.erase(id)
            return try encode(device)

        case "device_delete":
            let id = try await resolveDevice(params)
            try await bridge.devices.delete(id)
            return try encode(OperationAck(ok: true, message: "Deleted device \(id.rawValue)"))

        case "device_rename":
            let id = try await resolveDevice(params)
            let name = try params.string("name")
            let device = try await bridge.devices.rename(id, to: name)
            return try encode(device)

        case "runtime_list":
            var runtimes = try await bridge.runtimes.listRuntimes()
            if let platform = params.optionalString("platform") {
                runtimes = runtimes.filter { $0.platform.rawValue.caseInsensitiveCompare(platform) == .orderedSame }
            }
            return try encode(runtimes)

        case "runtime_install":
            let path = try params.string("path")
            let runtime = try await bridge.runtimes.installRuntime(at: path)
            return try encode(runtime)

        case "runtime_download":
            let platformRaw = try params.string("platform")
            guard let platform = Platform(rawValue: platformRaw) else {
                throw OpenSimError.invalidArgument("platform must be iOS, watchOS, tvOS, or visionOS")
            }
            let version = try params.string("version")
            let runtime = try await bridge.runtimes.downloadRuntime(platform: platform, version: version)
            return try encode(runtime)

        case "runtime_delete":
            let id = try IdentifierValidation.validateRuntimeIdentifier(try params.string("identifier"))
            try await bridge.runtimes.deleteRuntime(id)
            return try encode(OperationAck(ok: true, message: "Deleted runtime \(id.rawValue)"))

        case "runtime_verify":
            let id = try IdentifierValidation.validateRuntimeIdentifier(try params.string("identifier"))
            try await bridge.runtimes.verifyRuntime(id)
            return try encode(OperationAck(ok: true, message: "Verified runtime \(id.rawValue)"))

        case "app_list":
            let device = try await resolveDevice(params)
            let apps = try await bridge.apps.listApps(on: device, filter: params.optionalString("filter"))
            return try encode(apps)

        case "app_install":
            let device = try await resolveDevice(params)
            let path = try params.string("path")
            let app = try await bridge.apps.installApp(on: device, at: path)
            return try encode(app)

        case "app_uninstall":
            let device = try await resolveDevice(params)
            let bundleID = try params.string("bundleID")
            try await bridge.apps.uninstallApp(on: device, bundleID: bundleID)
            return try encode(OperationAck(ok: true, message: "Uninstalled \(bundleID)"))

        case "app_launch":
            let device = try await resolveDevice(params)
            let bundleID = try params.string("bundleID")
            let args = try params.jsonArray("args") ?? []
            let environment = try params.jsonObject("env") ?? [:]
            let pid = try await bridge.apps.launchApp(
                on: device,
                bundleID: bundleID,
                args: args,
                environment: environment
            )
            return try encode(AppLaunchResult(bundleID: bundleID, pid: pid))

        case "app_terminate":
            let device = try await resolveDevice(params)
            let bundleID = try params.string("bundleID")
            try await bridge.apps.terminateApp(on: device, bundleID: bundleID)
            return try encode(OperationAck(ok: true, message: "Terminated \(bundleID)"))

        case "app_info":
            let device = try await resolveDevice(params)
            let info = try await bridge.apps.appInfo(on: device, bundleID: try params.string("bundleID"))
            return try encode(info)

        case "app_container":
            let device = try await resolveDevice(params)
            let bundleID = try params.string("bundleID")
            let kindRaw = params.optionalString("kind") ?? "app"
            guard let kind = ContainerKind(rawValue: kindRaw) else {
                throw OpenSimError.invalidArgument("kind must be app, data, or group")
            }
            let path = try await bridge.apps.containerPath(on: device, bundleID: bundleID, kind: kind)
            return try encode(ContainerPathResult(bundleID: bundleID, kind: kind, path: path))

        case "log_tail":
            let device = try await resolveDevice(params)
            let limit = try params.int("limit", default: 100)
            guard limit > 0 && limit <= 1_000 else {
                throw OpenSimError.invalidArgument("limit must be between 1 and 1000")
            }
            let page = try await bridge.logs.tailLogs(
                on: device,
                cursor: params.optionalString("cursor"),
                limit: limit,
                filter: params.optionalString("filter")
            )
            return try encode(page)

        case "log_crash":
            let device = try await resolveDevice(params)
            guard let crashReports else {
                throw OpenSimError.capabilityUnavailable("crash_reports")
            }
            let limit = try params.int("limit", default: 20)
            let reports = try await crashReports.crashReports(on: device, limit: limit)
            return try encode(reports)

        case "doctor_report":
            guard let doctor else {
                throw OpenSimError.capabilityUnavailable("doctor")
            }
            let report = try await doctor.doctorReport()
            return try encode(report)

        default:
            throw OpenSimError(
                code: .internalError,
                message: "Catalog operation has no executor: \(name)"
            )
        }
    }

    private func resolveDevice(_ params: OperationParameters) async throws -> DeviceID {
        let query = params.optionalString("device")
        let devices = try await bridge.devices.listDevices()
        return try DeviceResolver.resolve(query: query, in: devices).id
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try OpenSimJSON.encoder(pretty: false).encode(value)
    }
}
