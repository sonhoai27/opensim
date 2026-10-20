import Foundation

public enum LogLevel: String, Codable, Sendable, CaseIterable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault
}

public struct LogEntry: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var level: LogLevel
    public var subsystem: String?
    public var category: String?
    public var process: String?
    public var message: String

    public init(
        timestamp: Date,
        level: LogLevel,
        subsystem: String?,
        category: String?,
        process: String?,
        message: String
    ) {
        self.timestamp = timestamp
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.process = process
        self.message = message
    }
}

public struct LogPage: Codable, Sendable, Equatable {
    public var entries: [LogEntry]
    public var nextCursor: String?

    public init(entries: [LogEntry], nextCursor: String?) {
        self.entries = entries
        self.nextCursor = nextCursor
    }
}
