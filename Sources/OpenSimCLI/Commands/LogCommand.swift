import ArgumentParser
import Foundation
import OpenSimCore

public struct LogCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "Read simulator logs",
        subcommands: [
            LogTailCommand.self,
            LogStreamCommand.self,
            LogCrashCommand.self,
        ]
    )

    public init() {}
}

private func logLine(_ entry: LogEntry) -> String {
    let timestamp = OpenSimDate.string(from: entry.timestamp)
    let process = entry.process ?? "-"
    return "\(timestamp) \(entry.level.rawValue.uppercased()) \(process) \(entry.message)"
}

public struct LogTailCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "tail", abstract: "Read a page of log entries")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Cursor returned by a previous page")
    public var cursor: String?

    @Option(name: .long, help: "Maximum entries in this page")
    public var limit: Int = 100

    @Option(name: .long, help: "NSPredicate filter")
    public var filter: String?

    public init() {}

    public func run() async throws {
        var values = globals.parameters()
        if let cursor {
            values["cursor"] = cursor
        }
        values["limit"] = "\(limit)"
        if let filter {
            values["filter"] = filter
        }
        let parameters = values
        _ = try await CLIRuntime.run(globals: globals, table: { page in
            Table(
                headers: ["TIMESTAMP", "LEVEL", "PROCESS", "MESSAGE"],
                rows: page.entries.map { entry in
                    [OpenSimDate.string(from: entry.timestamp), entry.level.rawValue, entry.process ?? "", entry.message]
                }
            )
        }) { backend in
            try await backend.execute("log_tail", parameters: parameters, as: LogPage.self)
        }
    }
}

public struct LogStreamCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "stream", abstract: "Poll and print new log entries")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "NSPredicate filter")
    public var filter: String?

    @Option(name: .customLong("interval"), help: "Poll interval in milliseconds")
    public var intervalMs: Int = 1_000

    public init() {}

    public func run() async throws {
        guard intervalMs >= 100 && intervalMs <= 60_000 else {
            throw OpenSimError.invalidArgument("interval must be between 100 and 60000 milliseconds")
        }
        try globals.validated()
        let backend = try CLIRuntime.makeBackend(globals)
        let output = OutputRenderer(json: globals.json)
        let deadline = Date().addingTimeInterval(TimeInterval(globals.timeout))
        var cursor: String?
        while Date() < deadline {
            var parameters = globals.parameters()
            parameters["limit"] = "200"
            if let filter {
                parameters["filter"] = filter
            }
            if let cursor {
                parameters["cursor"] = cursor
            }
            let page = try await backend.execute("log_tail", parameters: parameters, as: LogPage.self)
            for entry in page.entries {
                if globals.json {
                    let data = try OpenSimJSON.encoder(pretty: false).encode(entry)
                    output.line(String(decoding: data, as: UTF8.self))
                } else {
                    output.line(logLine(entry))
                }
            }
            if let next = page.nextCursor {
                cursor = next
            }
            try await Task.sleep(for: .milliseconds(intervalMs))
        }
    }
}

public struct LogCrashCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "crash", abstract: "List crash reports")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Maximum reports")
    public var limit: Int = 20

    public init() {}

    public func run() async throws {
        var values = globals.parameters()
        values["limit"] = "\(limit)"
        let parameters = values
        _ = try await CLIRuntime.run(globals: globals, table: { reports in
            Table(
                headers: ["MODIFIED", "PROCESS", "SIZE", "PATH"],
                rows: reports.map {
                    [OpenSimDate.string(from: $0.modifiedAt), $0.processName, "\($0.sizeBytes)", $0.path]
                }
            )
        }) { backend in
            try await backend.execute("log_crash", parameters: parameters, as: [CrashReport].self)
        }
    }
}
