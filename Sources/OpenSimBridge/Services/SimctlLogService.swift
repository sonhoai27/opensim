import Foundation
import OpenSimCore

struct SimctlLogPayload: Decodable {
    let timestamp: String
    let messageType: String?
    let subsystem: String?
    let category: String?
    let processImagePath: String?
    let eventMessage: String?
    let formatString: String?
}

struct LogCursor: Codable, Sendable, Equatable {
    var timestampMicros: Int64
    var skip: Int
}

enum LogCursorCodec {
    static func encode(_ cursor: LogCursor) throws -> String {
        let data = try JSONEncoder().encode(cursor)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) throws -> LogCursor {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64),
              let cursor = try? JSONDecoder().decode(LogCursor.self, from: data),
              cursor.skip >= 0 else {
            throw OpenSimError.invalidArgument(
                "Invalid log cursor",
                recovery: "Omit --cursor to start a new page"
            )
        }
        return cursor
    }
}

enum LogTimestamp {
    static func parse(_ text: String) -> Date? {
        let formatter = makeFormatter(format: "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZ")
        if let date = formatter.date(from: text) {
            return date
        }
        let fallback = makeFormatter(format: "yyyy-MM-dd HH:mm:ssZZZZ")
        return fallback.date(from: text)
    }

    static func string(fromMicros micros: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(micros) / 1_000_000)
        let formatter = makeFormatter(format: "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZ")
        return formatter.string(from: date)
    }

    static func micros(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    }

    private static func makeFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}

public struct SimctlLogService: LogControlling {
    private let executor: any SimctlExecuting
    private let timeout: Duration

    public init(executor: any SimctlExecuting, timeout: Duration) {
        self.executor = executor
        self.timeout = timeout
    }

    public func tailLogs(
        on device: DeviceID,
        cursor: String?,
        limit: Int,
        filter: String?
    ) async throws -> LogPage {
        guard limit > 0 && limit <= 1_000 else {
            throw OpenSimError.invalidArgument("limit must be between 1 and 1000")
        }
        if let filter, filter.count > 2_000 {
            throw OpenSimError.invalidArgument("filter is too long")
        }
        let decodedCursor = try cursor.map(LogCursorCodec.decode)

        let command: SimctlCommand
        if let decodedCursor {
            command = SimctlArguments.logShow(
                device: device,
                since: LogTimestamp.string(fromMicros: decodedCursor.timestampMicros),
                last: nil,
                predicate: filter
            )
        } else {
            command = SimctlArguments.logShow(
                device: device,
                since: nil,
                last: "5m",
                predicate: filter
            )
        }
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let entries = try parseEntries(output.stdout)
        return try paginate(entries: entries, cursor: decodedCursor, limit: limit)
    }

    private func parseEntries(_ data: Data) throws -> [LogEntry] {
        let text = String(decoding: data, as: UTF8.self)
        var entries: [LogEntry] = []
        for line in text.split(separator: "\n") {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }
            guard let payload = try? JSONDecoder().decode(SimctlLogPayload.self, from: Data(line.utf8)) else {
                continue
            }
            guard let timestamp = LogTimestamp.parse(payload.timestamp) else {
                continue
            }
            let process = payload.processImagePath.map { path in
                URL(fileURLWithPath: path).lastPathComponent
            }
            entries.append(LogEntry(
                timestamp: timestamp,
                level: level(from: payload.messageType),
                subsystem: emptyToNil(payload.subsystem),
                category: emptyToNil(payload.category),
                process: emptyToNil(process),
                message: payload.eventMessage ?? payload.formatString ?? ""
            ))
        }
        return entries.sorted { LogTimestamp.micros($0.timestamp) < LogTimestamp.micros($1.timestamp) }
    }

    private func paginate(entries: [LogEntry], cursor: LogCursor?, limit: Int) throws -> LogPage {
        var selected: [LogEntry] = []
        var lastIndex: Int?
        var skipped = 0
        let requiredSkip = cursor?.skip ?? 0
        for (index, entry) in entries.enumerated() {
            let micros = LogTimestamp.micros(entry.timestamp)
            if let cursor {
                if micros < cursor.timestampMicros {
                    continue
                }
                if micros == cursor.timestampMicros && skipped < requiredSkip {
                    skipped += 1
                    continue
                }
            }
            selected.append(entry)
            lastIndex = index
            if selected.count == limit {
                break
            }
        }
        guard let lastIndex, let last = selected.last else {
            let nextCursor = cursor.flatMap { try? LogCursorCodec.encode($0) }
            return LogPage(entries: [], nextCursor: nextCursor)
        }
        let lastMicros = LogTimestamp.micros(last.timestamp)
        let returnedAtTimestamp = entries[0..<(lastIndex + 1)].filter {
            LogTimestamp.micros($0.timestamp) == lastMicros
        }.count
        let next = LogCursor(timestampMicros: lastMicros, skip: returnedAtTimestamp)
        return LogPage(entries: selected, nextCursor: try LogCursorCodec.encode(next))
    }

    private func level(from messageType: String?) -> LogLevel {
        switch messageType?.lowercased() {
        case "debug":
            return .debug
        case "info":
            return .info
        case "error":
            return .error
        case "fault":
            return .fault
        case "warning":
            return .warning
        default:
            return .notice
        }
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}
