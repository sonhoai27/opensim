import Foundation
import OpenSimCore

public struct SimctlCommand: Sendable, Equatable {
    public var arguments: [String]
    public var environment: [String: String]

    public init(arguments: [String], environment: [String: String] = [:]) {
        self.arguments = arguments
        self.environment = environment
    }

    public var displayString: String {
        (["simctl"] + arguments).joined(separator: " ")
    }
}

public enum SimctlArguments {
    public static func listDevicesJSON() -> SimctlCommand {
        SimctlCommand(arguments: ["list", "devices", "-j"])
    }

    public static func listRuntimesJSON() -> SimctlCommand {
        SimctlCommand(arguments: ["list", "runtimes", "-j"])
    }

    public static func createDevice(name: String, deviceType: String, runtime: RuntimeID?) -> SimctlCommand {
        var arguments = ["create", name, deviceType]
        if let runtime {
            arguments.append(runtime.rawValue)
        }
        return SimctlCommand(arguments: arguments)
    }

    public static func cloneDevice(_ device: DeviceID, name: String) -> SimctlCommand {
        SimctlCommand(arguments: ["clone", device.rawValue, name])
    }

    public static func boot(_ device: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["boot", device.rawValue])
    }

    public static func bootStatus(_ device: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["bootstatus", device.rawValue, "-b"])
    }

    public static func shutdown(_ device: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["shutdown", device.rawValue])
    }

    public static func erase(_ device: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["erase", device.rawValue])
    }

    public static func delete(_ device: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["delete", device.rawValue])
    }

    public static func rename(_ device: DeviceID, to name: String) -> SimctlCommand {
        SimctlCommand(arguments: ["rename", device.rawValue, name])
    }

    public static func pair(watch: DeviceID, phone: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["pair", watch.rawValue, phone.rawValue])
    }

    public static func runtimeAdd(path: String) -> SimctlCommand {
        SimctlCommand(arguments: ["runtime", "add", path])
    }

    public static func runtimeDelete(identifier: RuntimeID) -> SimctlCommand {
        SimctlCommand(arguments: ["runtime", "delete", identifier.rawValue])
    }

    public static func runtimeVerify(identifier: RuntimeID) -> SimctlCommand {
        SimctlCommand(arguments: ["runtime", "verify", identifier.rawValue])
    }

    public static func listApps(_ device: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["listapps", device.rawValue])
    }

    public static func appInfo(_ device: DeviceID, bundleID: String) -> SimctlCommand {
        SimctlCommand(arguments: ["appinfo", device.rawValue, bundleID])
    }

    public static func installApp(_ device: DeviceID, path: String) -> SimctlCommand {
        SimctlCommand(arguments: ["install", device.rawValue, path])
    }

    public static func uninstallApp(_ device: DeviceID, bundleID: String) -> SimctlCommand {
        SimctlCommand(arguments: ["uninstall", device.rawValue, bundleID])
    }

    public static func launchApp(
        _ device: DeviceID,
        bundleID: String,
        args: [String],
        environment: [String: String]
    ) -> SimctlCommand {
        let childEnvironment = Dictionary(
            uniqueKeysWithValues: environment.map { key, value in ("SIMCTL_CHILD_\(key)", value) }
        )
        return SimctlCommand(
            arguments: ["launch", device.rawValue, bundleID] + args,
            environment: childEnvironment
        )
    }

    public static func terminateApp(_ device: DeviceID, bundleID: String) -> SimctlCommand {
        SimctlCommand(arguments: ["terminate", device.rawValue, bundleID])
    }

    public static func getAppContainer(_ device: DeviceID, bundleID: String, kind: ContainerKind) -> SimctlCommand {
        let container: String
        switch kind {
        case .app:
            container = "app"
        case .data:
            container = "data"
        case .group:
            container = "groups"
        }
        return SimctlCommand(arguments: ["get_app_container", device.rawValue, bundleID, container])
    }

    public static func logShow(device: DeviceID, since: String?, last: String?, predicate: String?) -> SimctlCommand {
        var arguments = ["spawn", device.rawValue, "log", "show", "--style", "ndjson", "--info", "--debug"]
        if let since {
            arguments.append(contentsOf: ["--start", since])
        } else if let last {
            arguments.append(contentsOf: ["--last", last])
        }
        if let predicate {
            arguments.append(contentsOf: ["--predicate", predicate])
        }
        return SimctlCommand(arguments: arguments)
    }
}
