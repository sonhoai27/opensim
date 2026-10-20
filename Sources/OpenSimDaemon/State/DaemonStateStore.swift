import Foundation
import OpenSimCore
import OpenSimProtocol

public struct DaemonStateStore: Sendable {
    private let paths: OpenSimPaths

    public init(paths: OpenSimPaths) {
        self.paths = paths
    }

    public func write(_ state: DaemonState) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: paths.baseDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.baseDirectory.path)
        let data = try OpenSimJSON.encoder(pretty: true).encode(state)
        try data.write(to: paths.daemonStateFile, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.daemonStateFile.path)
    }

    public func read() throws -> DaemonState {
        let data = try Data(contentsOf: paths.daemonStateFile)
        return try OpenSimJSON.decoder().decode(DaemonState.self, from: data)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: paths.daemonStateFile)
    }
}
