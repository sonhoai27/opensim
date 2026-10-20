import ArgumentParser
import Foundation
import OpenSimCore

public struct DeviceCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "device",
        abstract: "Manage simulator devices",
        subcommands: [
            DeviceListCommand.self,
            DeviceGetCommand.self,
            DeviceCreateCommand.self,
            DeviceCloneCommand.self,
            DeviceBootCommand.self,
            DeviceShutdownCommand.self,
            DeviceEraseCommand.self,
            DeviceDeleteCommand.self,
            DeviceRenameCommand.self,
            DeviceStatusCommand.self,
        ]
    )

    public init() {}
}

private func deviceTable(_ device: Device) -> Table {
    Table(
        headers: ["FIELD", "VALUE"],
        rows: [
            ["udid", device.id.rawValue],
            ["name", device.name],
            ["platform", device.platform.rawValue],
            ["deviceType", device.deviceType],
            ["runtime", device.runtime.rawValue],
            ["state", device.state.rawValue],
            ["available", device.isAvailable ? "yes" : "no"],
            ["dataPath", device.dataPath ?? ""],
        ]
    )
}

public struct DeviceListCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "list", abstract: "List devices")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Filter by platform")
    public var platform: String?

    @Option(name: .long, help: "Filter by state")
    public var state: String?

    public init() {}

    public func run() async throws {
        var values: [String: String] = [:]
        if let platform {
            values["platform"] = platform
        }
        if let state {
            values["state"] = state
        }
        let parameters = values
        _ = try await CLIRuntime.run(globals: globals, table: { devices in
            Table(
                headers: ["UDID", "NAME", "PLATFORM", "RUNTIME", "STATE", "AVAILABLE"],
                rows: devices.map {
                    [$0.id.rawValue, $0.name, $0.platform.rawValue, $0.runtime.rawValue, $0.state.rawValue, $0.isAvailable ? "yes" : "no"]
                }
            )
        }) { backend in
            try await backend.execute("device_list", parameters: parameters, as: [Device].self)
        }
    }
}

public struct DeviceGetCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "get", abstract: "Get one device")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters()
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_get", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceCreateCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a device")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Device name")
    public var name: String

    @Option(name: .long, help: "Device type identifier")
    public var type: String

    @Option(name: .long, help: "Runtime identifier")
    public var runtime: String?

    public init() {}

    public func run() async throws {
        var values = ["name": name, "deviceType": type]
        if let runtime {
            values["runtime"] = runtime
        }
        let parameters = values
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_create", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceCloneCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "clone", abstract: "Clone a device")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "New device name")
    public var name: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["name": name])
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_clone", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceBootCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "boot", abstract: "Boot a device")

    @OptionGroup public var globals: GlobalOptions

    @Flag(name: .long, help: "Wait until the device is booted")
    public var wait: Bool = false

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["wait": wait ? "true" : "false"])
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_boot", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceShutdownCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "shutdown", abstract: "Shut down a device")

    @OptionGroup public var globals: GlobalOptions

    @Flag(name: .long, help: "Wait until the device is shut down")
    public var wait: Bool = false

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["wait": wait ? "true" : "false"])
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_shutdown", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceEraseCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "erase", abstract: "Erase a device")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["confirm": globals.yes ? "true" : "false"])
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_erase", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceDeleteCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a device")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["confirm": globals.yes ? "true" : "false"])
        _ = try await CLIRuntime.run(globals: globals, table: { ack in
            Table(headers: ["RESULT", "MESSAGE"], rows: [[ack.ok ? "ok" : "failed", ack.message ?? ""]])
        }) { backend in
            try await backend.execute("device_delete", parameters: parameters, as: OperationAck.self)
        }
    }
}

public struct DeviceRenameCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "rename", abstract: "Rename a device")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "New device name")
    public var name: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["name": name])
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_rename", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceStatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "status", abstract: "Show device status")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters()
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_status", parameters: parameters, as: Device.self)
        }
    }
}
