import Foundation
import OpenSimCore

public actor AuditWriter {
    private let fileURL: URL
    private let maxBytes: Int
    private let fileManager: FileManager

    public init(fileURL: URL, maxBytes: Int = 50 * 1_024 * 1_024, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.fileManager = fileManager
    }

    public func append(_ event: AuditEvent) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var line = try OpenSimJSON.encoder(pretty: false).encode(event)
        line.append(0x0A)
        if currentSize() + line.count > maxBytes {
            try rotate()
        }
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    private func currentSize() -> Int {
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    private func rotate() throws {
        let base = fileURL.path
        for index in stride(from: 4, through: 1, by: -1) {
            let source = "\(base).\(index)"
            let destination = "\(base).\(index + 1)"
            guard fileManager.fileExists(atPath: source) else {
                continue
            }
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: destination)
            }
            try fileManager.moveItem(atPath: source, toPath: destination)
        }
        if fileManager.fileExists(atPath: base) {
            if fileManager.fileExists(atPath: "\(base).1") {
                try fileManager.removeItem(atPath: "\(base).1")
            }
            try fileManager.moveItem(atPath: base, toPath: "\(base).1")
        }
    }
}
