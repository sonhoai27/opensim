import ArgumentParser
import Foundation
import OpenSimCore

public struct RuntimeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "runtime",
        abstract: "Manage simulator runtimes",
        subcommands: [
            RuntimeListCommand.self,
            RuntimeDownloadCommand.self,
            RuntimeInstallCommand.self,
            RuntimeDeleteCommand.self,
            RuntimeVerifyCommand.self,
        ]
    )

    public init() {}
}

private func runtimeTable(_ runtime: Runtime) -> Table {
    Table(
        headers: ["FIELD", "VALUE"],
        rows: [
            ["identifier", runtime.id.rawValue],
            ["name", runtime.name],
            ["platform", runtime.platform.rawValue],
            ["version", runtime.version],
            ["build", runtime.build],
            ["available", runtime.isAvailable ? "yes" : "no"],
            ["path", runtime.path ?? ""],
        ]
    )
}

private func ackTable(_ ack: OperationAck) -> Table {
    Table(headers: ["RESULT", "MESSAGE"], rows: [[ack.ok ? "ok" : "failed", ack.message ?? ""]])
}

public struct RuntimeListCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "list", abstract: "List runtimes")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Filter by platform")
    public var platform: String?

    public init() {}

    public func run() async throws {
        var values: [String: String] = [:]
        if let platform {
            values["platform"] = platform
        }
        let parameters = values
        _ = try await CLIRuntime.run(globals: globals, table: { runtimes in
            Table(
                headers: ["IDENTIFIER", "NAME", "PLATFORM", "VERSION", "BUILD", "AVAILABLE", "PATH"],
                rows: runtimes.map {
                    [$0.id.rawValue, $0.name, $0.platform.rawValue, $0.version, $0.build, $0.isAvailable ? "yes" : "no", $0.path ?? ""]
                }
            )
        }) { backend in
            try await backend.execute("runtime_list", parameters: parameters, as: [Runtime].self)
        }
    }
}

public struct RuntimeDownloadCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "download", abstract: "Download a runtime version")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Platform: iOS, watchOS, tvOS, or visionOS")
    public var platform: String

    @Option(name: .long, help: "Runtime version, for example 26.4")
    public var version: String

    public init() {}

    public func run() async throws {
        let parameters = ["platform": platform, "version": version]
        _ = try await CLIRuntime.run(globals: globals, table: runtimeTable) { backend in
            try await backend.execute("runtime_download", parameters: parameters, as: Runtime.self)
        }
    }
}

public struct RuntimeInstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "install", abstract: "Install a runtime image")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Path to a .dmg or .simruntime")
    public var path: String

    public init() {}

    public func run() async throws {
        let parameters = ["path": path]
        _ = try await CLIRuntime.run(globals: globals, table: runtimeTable) { backend in
            try await backend.execute("runtime_install", parameters: parameters, as: Runtime.self)
        }
    }
}

public struct RuntimeDeleteCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a runtime")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Runtime identifier")
    public var identifier: String

    public init() {}

    public func run() async throws {
        let parameters = ["identifier": identifier, "confirm": globals.yes ? "true" : "false"]
        _ = try await CLIRuntime.run(globals: globals, table: ackTable) { backend in
            try await backend.execute("runtime_delete", parameters: parameters, as: OperationAck.self)
        }
    }
}

public struct RuntimeVerifyCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "verify", abstract: "Verify a runtime signature")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Runtime identifier")
    public var identifier: String

    public init() {}

    public func run() async throws {
        let parameters = ["identifier": identifier]
        _ = try await CLIRuntime.run(globals: globals, table: ackTable) { backend in
            try await backend.execute("runtime_verify", parameters: parameters, as: OperationAck.self)
        }
    }
}
