import ArgumentParser
import Foundation
import OpenSimCore
import OpenSimDaemon
import OpenSimMCP
import OpenSimProtocol

public struct DaemonStatusInfo: Codable, Sendable, Equatable {
    public var pid: Int32?
    public var port: Int?
    public var version: String?
    public var health: String
    public var capabilities: BridgeCapabilities?

    public init(
        pid: Int32?,
        port: Int?,
        version: String?,
        health: String,
        capabilities: BridgeCapabilities?
    ) {
        self.pid = pid
        self.port = port
        self.version = version
        self.health = health
        self.capabilities = capabilities
    }
}

public struct DaemonCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Manage the OpenSim daemon",
        subcommands: [
            DaemonStartCommand.self,
            DaemonStopCommand.self,
            DaemonRestartCommand.self,
            DaemonStatusCommand.self,
            DaemonLogsCommand.self,
            DaemonRunCommand.self,
        ]
    )

    public init() {}
}

private func daemonAckTable(_ ack: OperationAck) -> Table {
    Table(headers: ["RESULT", "MESSAGE"], rows: [[ack.ok ? "ok" : "failed", ack.message ?? ""]])
}

private func daemonStatusTable(_ info: DaemonStatusInfo) -> Table {
    Table(
        headers: ["FIELD", "VALUE"],
        rows: [
            ["health", info.health],
            ["pid", info.pid.map(String.init) ?? ""],
            ["port", info.port.map(String.init) ?? ""],
            ["version", info.version ?? ""],
            ["render", info.capabilities?.render.rawValue ?? ""],
            ["screenshot", info.capabilities?.screenshot.rawValue ?? ""],
        ]
    )
}

private func renderDaemon<T: Codable & Sendable>(
    globals: GlobalOptions,
    table: @escaping @Sendable (T) -> Table,
    body: @Sendable () async throws -> T
) async throws {
    let renderer = OutputRenderer(json: globals.json)
    do {
        let value = try await body()
        try renderer.success(value, table: table(value), durationMs: 0)
    } catch let error as OpenSimError {
        renderer.failure(error, durationMs: 0)
        throw ExitCode(OpenSimExitCode.forError(error.code).rawValue)
    }
}

private func daemonLaunchAgent(paths: OpenSimPaths) -> LaunchAgentManager {
    LaunchAgentManager(opensimPath: opensimExecutablePath(), paths: paths)
}

private func opensimExecutablePath() -> String {
    if let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path {
        return path
    }
    return CommandLine.arguments[0]
}

private func waitForDaemon(paths: OpenSimPaths, timeout: TimeInterval = 5) async throws -> DaemonState {
    let store = DaemonStateStore(paths: paths)
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let state = try? store.read(),
           (try? await DaemonClient(state: state).health()) != nil {
            return state
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    throw OpenSimError.daemonUnavailable("Daemon did not become healthy within 5 seconds")
}

public struct DaemonStartCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "start", abstract: "Start the daemon")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        try await renderDaemon(globals: globals, table: daemonAckTable) {
            let paths = OpenSimPaths()
            try paths.ensureDirectories()
            let store = DaemonStateStore(paths: paths)
            if let state = try? store.read(),
               (try? await DaemonClient(state: state).health()) != nil {
                return OperationAck(ok: true, message: "Daemon already running on port \(state.port)")
            }
            let manager = daemonLaunchAgent(paths: paths)
            try manager.install()
            try? manager.bootout()
            try manager.bootstrap()
            let state = try await waitForDaemon(paths: paths)
            return OperationAck(ok: true, message: "Daemon started on port \(state.port)")
        }
    }
}

public struct DaemonStopCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "stop", abstract: "Stop the daemon")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        try await renderDaemon(globals: globals, table: daemonAckTable) {
            let paths = OpenSimPaths()
            try paths.ensureDirectories()
            let manager = daemonLaunchAgent(paths: paths)
            try? manager.bootout()
            DaemonStateStore(paths: paths).remove()
            return OperationAck(ok: true, message: "Daemon stopped")
        }
    }
}

public struct DaemonRestartCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "restart", abstract: "Restart the daemon")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        try await renderDaemon(globals: globals, table: daemonAckTable) {
            let paths = OpenSimPaths()
            try paths.ensureDirectories()
            let manager = daemonLaunchAgent(paths: paths)
            try manager.install()
            try manager.kickstart()
            _ = try await waitForDaemon(paths: paths)
            return OperationAck(ok: true, message: "Daemon restarted")
        }
    }
}

public struct DaemonStatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "status", abstract: "Show daemon status")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        try await renderDaemon(globals: globals, table: daemonStatusTable) {
            let store = DaemonStateStore(paths: OpenSimPaths())
            guard let state = try? store.read() else {
                throw OpenSimError(
                    code: .daemonUnavailable,
                    message: "Daemon state file was not found",
                    recovery: "Run `opensim daemon start`"
                )
            }
            let health = try await DaemonClient(state: state).health()
            return DaemonStatusInfo(
                pid: state.pid,
                port: state.port,
                version: state.version,
                health: health.status,
                capabilities: health.capabilities
            )
        }
    }
}

public struct DaemonLogsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "logs", abstract: "Print daemon logs")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Number of lines")
    public var limit: Int = 200

    public init() {}

    public func run() async throws {
        let lines = DaemonLogsCommand.tail(OpenSimPaths().daemonLogFile, limit: limit)
        if globals.json {
            try OutputRenderer(json: true).success(lines, table: nil, durationMs: 0)
            return
        }
        for line in lines {
            print(line)
        }
    }

    static func tail(_ url: URL, limit: Int) -> [String] {
        guard limit > 0, let data = try? Data(contentsOf: url) else {
            return []
        }
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(limit)
            .map(String.init)
    }
}

public struct DaemonRunCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the daemon in the foreground"
    )

    @Flag(name: .long, help: "Keep running in the foreground")
    public var foreground: Bool = false

    public init() {}

    public func run() async throws {
        try await DaemonRunner.run(configuration: DaemonRunConfiguration(
            paths: OpenSimPaths(),
            routeProviders: [MCPRouteProvider(catalog: OperationCatalog.plan3())]
        ))
    }
}
