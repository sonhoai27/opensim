import ArgumentParser
import Foundation
import OpenSimCore

public struct AppCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Manage applications on a device",
        subcommands: [
            AppListCommand.self,
            AppInstallCommand.self,
            AppUninstallCommand.self,
            AppLaunchCommand.self,
            AppTerminateCommand.self,
            AppInfoCommand.self,
            AppContainerCommand.self,
        ]
    )

    public init() {}
}

private func appTable(_ app: AppInfo) -> Table {
    Table(
        headers: ["FIELD", "VALUE"],
        rows: [
            ["bundleID", app.id],
            ["displayName", app.displayName ?? ""],
            ["version", app.version ?? ""],
            ["build", app.build ?? ""],
            ["dataContainer", app.dataContainer ?? ""],
            ["appContainer", app.appContainer ?? ""],
        ]
    )
}

private func ackTable(_ ack: OperationAck) -> Table {
    Table(headers: ["RESULT", "MESSAGE"], rows: [[ack.ok ? "ok" : "failed", ack.message ?? ""]])
}

private func parseEnvironment(_ pairs: [String]) throws -> [String: String] {
    var result: [String: String] = [:]
    for pair in pairs {
        guard let separator = pair.firstIndex(of: "=") else {
            throw OpenSimError.invalidArgument("--env must use KEY=VALUE")
        }
        let key = String(pair[..<separator])
        let value = String(pair[pair.index(after: separator)..<pair.endIndex])
        guard !key.isEmpty else {
            throw OpenSimError.invalidArgument("--env key must not be empty")
        }
        result[key] = value
    }
    return result
}

public struct AppListCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "list", abstract: "List installed apps")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Case-insensitive bundle or display name filter")
    public var filter: String?

    public init() {}

    public func run() async throws {
        var values = globals.parameters()
        if let filter {
            values["filter"] = filter
        }
        let parameters = values
        _ = try await CLIRuntime.run(globals: globals, table: { apps in
            Table(
                headers: ["BUNDLE_ID", "NAME", "VERSION", "BUILD", "DATA", "APP"],
                rows: apps.map {
                    [$0.id, $0.displayName ?? "", $0.version ?? "", $0.build ?? "", $0.dataContainer ?? "", $0.appContainer ?? ""]
                }
            )
        }) { backend in
            try await backend.execute("app_list", parameters: parameters, as: [AppInfo].self)
        }
    }
}

public struct AppInstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "install", abstract: "Install an app bundle")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Path to an .app directory")
    public var path: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["path": path])
        _ = try await CLIRuntime.run(globals: globals, table: appTable) { backend in
            try await backend.execute("app_install", parameters: parameters, as: AppInfo.self)
        }
    }
}

public struct AppUninstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Uninstall an app")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Bundle identifier")
    public var bundleID: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters([
            "bundleID": bundleID,
            "confirm": globals.yes ? "true" : "false",
        ])
        _ = try await CLIRuntime.run(globals: globals, table: ackTable) { backend in
            try await backend.execute("app_uninstall", parameters: parameters, as: OperationAck.self)
        }
    }
}

public struct AppLaunchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "launch", abstract: "Launch an app")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Bundle identifier")
    public var bundleID: String

    @Option(name: .customLong("arg"), help: "Launch argument; repeat for multiple values")
    public var arguments: [String] = []

    @Option(name: .customLong("env"), help: "Environment entry KEY=VALUE; repeat for multiple values")
    public var environment: [String] = []

    public init() {}

    public func run() async throws {
        var values = globals.parameters(["bundleID": bundleID])
        if !arguments.isEmpty {
            let data = try JSONEncoder().encode(arguments)
            values["args"] = String(decoding: data, as: UTF8.self)
        }
        let parsedEnvironment = try parseEnvironment(environment)
        if !parsedEnvironment.isEmpty {
            let data = try JSONEncoder().encode(parsedEnvironment)
            values["env"] = String(decoding: data, as: UTF8.self)
        }
        let parameters = values
        _ = try await CLIRuntime.run(globals: globals, table: { result in
            Table(headers: ["BUNDLE_ID", "PID"], rows: [[result.bundleID, "\(result.pid)"]])
        }) { backend in
            try await backend.execute("app_launch", parameters: parameters, as: AppLaunchResult.self)
        }
    }
}

public struct AppTerminateCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "terminate", abstract: "Terminate an app")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Bundle identifier")
    public var bundleID: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["bundleID": bundleID])
        _ = try await CLIRuntime.run(globals: globals, table: ackTable) { backend in
            try await backend.execute("app_terminate", parameters: parameters, as: OperationAck.self)
        }
    }
}

public struct AppInfoCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "info", abstract: "Show app metadata")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Bundle identifier")
    public var bundleID: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["bundleID": bundleID])
        _ = try await CLIRuntime.run(globals: globals, table: appTable) { backend in
            try await backend.execute("app_info", parameters: parameters, as: AppInfo.self)
        }
    }
}

public struct AppContainerCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "container", abstract: "Resolve an app container path")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Bundle identifier")
    public var bundleID: String

    @Option(name: .long, help: "Container kind: app, data, group")
    public var kind: String = "app"

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["bundleID": bundleID, "kind": kind])
        _ = try await CLIRuntime.run(globals: globals, table: { result in
            Table(headers: ["BUNDLE_ID", "KIND", "PATH"], rows: [[result.bundleID, result.kind.rawValue, result.path]])
        }) { backend in
            try await backend.execute("app_container", parameters: parameters, as: ContainerPathResult.self)
        }
    }
}
