import Foundation
import Logging
import OpenSimCore

private final class RotatingFileWriter: @unchecked Sendable {
    private let fileURL: URL
    private let maxBytes: Int
    private let maxFiles: Int
    private let lock = NSLock()

    init(fileURL: URL, maxBytes: Int, maxFiles: Int) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.maxFiles = maxFiles
    }

    func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = Data((line + "\n").utf8)
        if size() + data.count > maxBytes {
            rotate()
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(
                atPath: fileURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func size() -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    private func rotate() {
        let base = fileURL.path
        if maxFiles > 1 {
            for index in stride(from: maxFiles - 1, through: 1, by: -1) {
                let source = "\(base).\(index)"
                let destination = "\(base).\(index + 1)"
                guard FileManager.default.fileExists(atPath: source) else {
                    continue
                }
                try? FileManager.default.removeItem(atPath: destination)
                try? FileManager.default.moveItem(atPath: source, toPath: destination)
            }
        }
        if FileManager.default.fileExists(atPath: base) {
            try? FileManager.default.removeItem(atPath: "\(base).1")
            try? FileManager.default.moveItem(atPath: base, toPath: "\(base).1")
        }
    }
}

public struct RotatingFileLogHandler: LogHandler {
    public var metadata: Logger.Metadata = [:]
    public var logLevel: Logger.Level = .info
    private let label: String
    private let writer: RotatingFileWriter

    public init(label: String, fileURL: URL, maxBytes: Int, maxFiles: Int) {
        self.label = label
        self.writer = RotatingFileWriter(fileURL: fileURL, maxBytes: maxBytes, maxFiles: maxFiles)
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let timestamp = OpenSimDate.string(from: Date())
        writer.write("\(timestamp) \(level) [\(label)] \(message)")
    }
}

public enum DaemonLogger {
    public static let label = "dev.opensim.daemon"

    public static func makeLogger(paths: OpenSimPaths, maxBytes: Int = 10 * 1_024 * 1_024, maxFiles: Int = 5) -> Logger {
        makeLogger(fileURL: paths.daemonLogFile, maxBytes: maxBytes, maxFiles: maxFiles)
    }

    public static func makeLogger(fileURL: URL, maxBytes: Int = 10 * 1_024 * 1_024, maxFiles: Int = 5) -> Logger {
        var logger = Logger(label: DaemonLogger.label) { _ in
            RotatingFileLogHandler(label: DaemonLogger.label, fileURL: fileURL, maxBytes: maxBytes, maxFiles: maxFiles)
        }
        logger.logLevel = .info
        return logger
    }
}
