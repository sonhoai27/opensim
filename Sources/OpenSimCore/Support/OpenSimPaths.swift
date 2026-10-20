import Foundation

public struct OpenSimPaths: Sendable {
    public let baseDirectory: URL

    public init(baseDirectory: URL = OpenSimPaths.defaultBaseDirectory) {
        self.baseDirectory = baseDirectory
    }

    public static var defaultBaseDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["OPENSIM_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("OpenSim", isDirectory: true)
    }

    public var daemonStateFile: URL {
        baseDirectory.appendingPathComponent("daemon.json")
    }

    public var lockFile: URL {
        baseDirectory.appendingPathComponent("daemon.lock")
    }

    public var auditFile: URL {
        baseDirectory.appendingPathComponent("audit.jsonl")
    }

    public var logDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("OpenSim", isDirectory: true)
    }

    public var daemonLogFile: URL {
        logDirectory.appendingPathComponent("daemon.log")
    }

    public func ensureDirectories() throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
