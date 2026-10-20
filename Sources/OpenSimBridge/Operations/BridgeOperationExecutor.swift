import Foundation
import OpenSimCore

public struct BridgeOperationExecutor: Sendable {
    public let bridge: any SimulatorBridge
    public let crashReports: (any CrashReportReading)?
    public let doctor: (any DoctorReporting)?
    public let catalog: OperationCatalog
    public let automation: UIAutomationService?

    public init(
        bridge: any SimulatorBridge,
        crashReports: (any CrashReportReading)? = nil,
        doctor: (any DoctorReporting)? = nil,
        catalog: OperationCatalog = .plan1(),
        automation: UIAutomationService? = nil
    ) {
        self.bridge = bridge
        self.crashReports = crashReports
        self.doctor = doctor
        self.catalog = catalog
        self.automation = automation
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

        case "screen_info":
            guard let screen = bridge.screen else {
                throw OpenSimError.capabilityUnavailable("screen")
            }
            let device = try await resolveDevice(params)
            return try encode(try await screen.screens(for: device))

        case "screen_screenshot":
            guard let screen = bridge.screen else {
                throw OpenSimError.capabilityUnavailable("screen")
            }
            let device = try await resolveDevice(params)
            let formatRaw = params.optionalString("format") ?? "png"
            guard let format = ScreenshotFormat(rawValue: formatRaw) else {
                throw OpenSimError.invalidArgument("format must be png or jpeg")
            }
            let scale = try params.double("scale", default: 1.0)
            guard scale >= 0.1 && scale <= 4.0 else {
                throw OpenSimError.invalidArgument("scale must be between 0.1 and 4.0")
            }
            let quality = try params.optionalInt("quality")
            let out = params.optionalString("out")
            if let out, let writer = screen as? any ScreenshotOutWriting {
                return try encode(
                    try await writer.screenshot(
                        on: device,
                        format: format,
                        scale: scale,
                        quality: quality,
                        out: out
                    )
                )
            }
            return try encode(
                try await screen.screenshot(
                    on: device,
                    format: format,
                    scale: scale,
                    quality: quality
                )
            )

        case "screen_record_start":
            guard let screen = bridge.screen else {
                throw OpenSimError.capabilityUnavailable("screen")
            }
            let device = try await resolveDevice(params)
            let codecRaw = params.optionalString("codec") ?? "h264"
            guard let codec = VideoCodec(rawValue: codecRaw) else {
                throw OpenSimError.invalidArgument("codec must be h264 or hevc")
            }
            let id = try await screen.startRecording(
                on: device,
                to: params.optionalString("out"),
                codec: codec
            )
            return try encode(RecordingStartResult(id: id))

        case "screen_record_stop":
            guard let screen = bridge.screen else {
                throw OpenSimError.capabilityUnavailable("screen")
            }
            let id = RecordingID(try params.string("recordingID"))
            if let recorder = screen as? any RecordingControlling {
                return try encode(try await recorder.stopRecordingResult(id))
            }
            let path = try await screen.stopRecording(id)
            return try encode(RecordingStopResult(id: id, path: path, durationMs: 0))

        case "ui_tree":
            guard let accessibility = bridge.accessibility else {
                throw OpenSimError.capabilityUnavailable("accessibility")
            }
            let device = try await resolveDevice(params)
            let maxDepth = try params.int("maxDepth", default: 30)
            let maxNodes = try params.int("maxNodes", default: 1_500)
            guard maxDepth >= 0, maxNodes > 0 else {
                throw OpenSimError.invalidArgument("maxDepth must be >= 0 and maxNodes must be > 0")
            }
            return try encode(
                try await accessibility.tree(on: device, maxDepth: maxDepth, maxNodes: maxNodes)
            )

        case "ui_find":
            guard let accessibility = bridge.accessibility else {
                throw OpenSimError.capabilityUnavailable("accessibility")
            }
            let device = try await resolveDevice(params)
            guard let selector = try selector(from: params, key: "selector") else {
                throw OpenSimError.invalidArgument("Missing required parameter selector")
            }
            return try encode(try await accessibility.find(on: device, selector: selector))

        case "ui_tap":
            let device = try await resolveDevice(params)
            let settle = try params.bool("settle", default: false)
            if let selector = try selector(from: params, key: "on") {
                guard let automation else {
                    throw OpenSimError.capabilityUnavailable("automation")
                }
                return try encode(
                    try await automation.tap(on: device, selector: selector, settle: settle)
                )
            }
            guard let input = bridge.input else {
                throw OpenSimError.capabilityUnavailable("input")
            }
            let point = try PointParser.parse(
                x: params.optionalString("x"),
                y: params.optionalString("y")
            )
            try await input.tap(on: device, at: point, settle: settle)
            return try encode(
                UIActionResult(action: "tap", point: point, matchedCount: 0, settleMs: 0)
            )

        case "ui_swipe":
            guard let input = bridge.input else {
                throw OpenSimError.capabilityUnavailable("input")
            }
            let device = try await resolveDevice(params)
            let from = try requiredPoint(from: params, key: "from")
            let to = try requiredPoint(from: params, key: "to")
            let duration = try params.int("durationMs", default: 300)
            try await input.swipe(on: device, from: from, to: to, durationMs: duration)
            return try encode(UIActionResult(action: "swipe", point: from, matchedCount: 0))

        case "ui_long_press":
            guard let input = bridge.input else {
                throw OpenSimError.capabilityUnavailable("input")
            }
            let device = try await resolveDevice(params)
            let point = try PointParser.parse(
                x: params.optionalString("x"),
                y: params.optionalString("y")
            )
            let duration = try params.int("durationMs", default: 800)
            try await input.longPress(on: device, at: point, durationMs: duration)
            return try encode(UIActionResult(action: "long-press", point: point, matchedCount: 0))

        case "ui_drag":
            guard let input = bridge.input else {
                throw OpenSimError.capabilityUnavailable("input")
            }
            let device = try await resolveDevice(params)
            let from = try requiredPoint(from: params, key: "from")
            let to = try requiredPoint(from: params, key: "to")
            let duration = try params.int("durationMs", default: 300)
            try await input.drag(on: device, from: from, to: to, durationMs: duration)
            return try encode(UIActionResult(action: "drag", point: from, matchedCount: 0))

        case "ui_pinch":
            guard let input = bridge.input else {
                throw OpenSimError.capabilityUnavailable("input")
            }
            let device = try await resolveDevice(params)
            let center = try requiredPoint(from: params, key: "center")
            let scale = try params.double("scale", default: nil)
            let duration = try params.int("durationMs", default: 300)
            try await input.pinch(on: device, center: center, scale: scale, durationMs: duration)
            return try encode(UIActionResult(action: "pinch", point: center, matchedCount: 0))

        case "ui_rotate":
            guard let input = bridge.input else {
                throw OpenSimError.capabilityUnavailable("input")
            }
            let device = try await resolveDevice(params)
            let center = try requiredPoint(from: params, key: "center")
            let angle = try params.double("angle", default: nil)
            let duration = try params.int("durationMs", default: 300)
            try await input.rotate(on: device, center: center, angle: angle, durationMs: duration)
            return try encode(UIActionResult(action: "rotate", point: center, matchedCount: 0))

        case "ui_scroll":
            guard let input = bridge.input else {
                throw OpenSimError.capabilityUnavailable("input")
            }
            let device = try await resolveDevice(params)
            let deltaX = try params.double("deltaX", default: 0)
            let deltaY = try params.double("deltaY", default: 0)
            let at = try point(from: params, key: "at")
            try await input.scroll(on: device, deltaX: deltaX, deltaY: deltaY, at: at)
            return try encode(UIActionResult(action: "scroll", point: at, matchedCount: 0))

        case "ui_type":
            guard let input = bridge.input else {
                throw OpenSimError.capabilityUnavailable("input")
            }
            let device = try await resolveDevice(params)
            try await input.typeText(on: device, text: try params.string("text"))
            return try encode(UIActionResult(action: "type", matchedCount: 0))

        case "ui_key":
            guard let input = bridge.input else {
                throw OpenSimError.capabilityUnavailable("input")
            }
            let device = try await resolveDevice(params)
            let key = Key(name: try params.string("key"))
            let modifiers = try decodeOptional(KeyModifiers.self, from: params.optionalString("modifiers"), name: "modifiers") ?? KeyModifiers()
            try await input.key(on: device, key: key, modifiers: modifiers)
            return try encode(UIActionResult(action: "key", matchedCount: 0))

        case "ui_button":
            guard let input = bridge.input else {
                throw OpenSimError.capabilityUnavailable("input")
            }
            let device = try await resolveDevice(params)
            let raw = try params.string("button")
            guard let button = HardwareButton(rawValue: raw) else {
                throw OpenSimError.invalidArgument("Unknown hardware button: \(raw)")
            }
            try await input.button(on: device, button: button)
            return try encode(UIActionResult(action: "button", matchedCount: 0))

        case "ui_wait":
            guard let automation else {
                throw OpenSimError.capabilityUnavailable("automation")
            }
            let device = try await resolveDevice(params)
            let selector = try selector(from: params, key: "selector")
            let idleMs = try params.int("idleMs", default: 250)
            let timeoutMs = try params.int("timeoutMs", default: 5_000)
            guard idleMs >= 0, timeoutMs >= 0 else {
                throw OpenSimError.invalidArgument("idleMs and timeoutMs must be >= 0")
            }
            return try encode(
                try await automation.wait(
                    on: device,
                    selector: selector,
                    idleMs: idleMs,
                    timeoutMs: timeoutMs
                )
            )

        case "ui_act":
            guard let automation else {
                throw OpenSimError.capabilityUnavailable("automation")
            }
            let device = try await resolveDevice(params)
            let rawSteps = try params.string("steps")
            let steps = try decode([UIActStep].self, from: rawSteps, name: "steps")
            let stopOnError = try params.bool("stopOnError", default: true)
            return try encode(
                try await automation.act(on: device, steps: steps, stopOnError: stopOnError)
            )

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

    private func selector(
        from params: OperationParameters,
        key: String
    ) throws -> ElementSelector? {
        guard let raw = params.optionalString(key) else {
            return nil
        }
        if raw.hasPrefix("{") {
            return try decode(ElementSelector.self, from: raw, name: key)
        }
        return try SelectorParser.parse(raw)
    }

    private func point(from params: OperationParameters, key: String) throws -> Point? {
        guard let raw = params.optionalString(key) else {
            return nil
        }
        if raw.hasPrefix("{") {
            return try decode(Point.self, from: raw, name: key)
        }
        return try PointParser.parse(raw, label: key)
    }

    private func requiredPoint(from params: OperationParameters, key: String) throws -> Point {
        guard let value = try point(from: params, key: key) else {
            throw OpenSimError.invalidArgument("Missing required parameter \(key)")
        }
        return value
    }

    private func decode<T: Decodable>(_ type: T.Type, from text: String, name: String) throws -> T {
        guard let data = text.data(using: .utf8) else {
            throw OpenSimError.invalidArgument("Parameter \(name) must be UTF-8 JSON")
        }
        do {
            return try OpenSimJSON.decoder().decode(type, from: data)
        } catch {
            throw OpenSimError.invalidArgument(
                "Parameter \(name) must be valid JSON",
                details: ["error": String(describing: error)]
            )
        }
    }

    private func decodeOptional<T: Decodable>(
        _ type: T.Type,
        from text: String?,
        name: String
    ) throws -> T? {
        guard let text else { return nil }
        return try decode(type, from: text, name: name)
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
