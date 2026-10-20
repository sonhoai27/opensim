import ArgumentParser
import Foundation
import OpenSimCore
import OpenSimProtocol

public struct SessionCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Manage daemon sessions and leases",
        subcommands: [
            SessionListCommand.self,
            SessionAcquireCommand.self,
            SessionReleaseCommand.self,
        ]
    )

    public init() {}
}

public struct SessionListCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "list", abstract: "List sessions and leases")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        _ = try await CLIRuntime.run(globals: globals, table: { result in
            let sessionRows = result.sessions.map {
                ["session", $0.id.rawValue, $0.clientKind, $0.clientName]
            }
            let leaseRows = result.leases.map {
                ["lease", $0.id.rawValue, $0.mode.rawValue, "\($0.deviceID.rawValue) \($0.ownerName)"]
            }
            return Table(headers: ["KIND", "ID", "TYPE", "DETAIL"], rows: sessionRows + leaseRows)
        }) { backend in
            try await backend.execute("session_list", parameters: [:], as: SessionListResult.self)
        }
    }
}

public struct SessionAcquireCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "acquire", abstract: "Acquire a lease")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Lease mode: control or observe")
    public var mode: String = "control"

    @Option(name: .long, help: "Lease TTL in seconds")
    public var ttl: Int = 300

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters([
            "mode": mode,
            "ttlSeconds": "\(ttl)",
        ])
        _ = try await CLIRuntime.run(globals: globals, table: { lease in
            Table(
                headers: ["LEASE_ID", "DEVICE", "MODE", "OWNER", "EXPIRES_AT"],
                rows: [[
                    lease.id.rawValue,
                    lease.deviceID.rawValue,
                    lease.mode.rawValue,
                    lease.ownerName,
                    OpenSimDate.string(from: lease.expiresAt),
                ]]
            )
        }) { backend in
            try await backend.execute("session_acquire", parameters: parameters, as: Lease.self)
        }
    }
}

public struct SessionReleaseCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "release", abstract: "Release a lease")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Lease identifier")
    public var leaseID: String

    public init() {}

    public func run() async throws {
        guard globals.session != nil else {
            throw OpenSimError.invalidArgument(
                "session release requires --session",
                recovery: "Pass the session that owns the lease"
            )
        }
        let lease = leaseID
        _ = try await CLIRuntime.run(globals: globals, table: { ack in
            Table(headers: ["RESULT", "MESSAGE"], rows: [[ack.ok ? "ok" : "failed", ack.message ?? ""]])
        }) { backend in
            try await backend.execute("session_release", parameters: ["leaseID": lease], as: OperationAck.self)
        }
    }
}
