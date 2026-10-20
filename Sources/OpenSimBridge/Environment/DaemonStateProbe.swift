import Darwin
import Foundation
import OpenSimCore

public struct DaemonStateProbe: Sendable {
    private let paths: OpenSimPaths

    public init(paths: OpenSimPaths) {
        self.paths = paths
    }

    public func health() -> DaemonHealth {
        let fileManager = FileManager.default
        let stateURL = paths.daemonStateFile
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return DaemonHealth(status: .notInstalled, pid: nil, port: nil, version: nil, tokenPermissionsOK: nil)
        }
        let attributes = try? fileManager.attributesOfItem(atPath: stateURL.path)
        let permissions = attributes?[.posixPermissions] as? NSNumber
        let permissionsOK = permissions?.intValue == 0o600
        guard let data = try? Data(contentsOf: stateURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pidNumber = object["pid"] as? NSNumber,
              let portNumber = object["port"] as? NSNumber else {
            return DaemonHealth(
                status: .unhealthy,
                pid: nil,
                port: nil,
                version: nil,
                tokenPermissionsOK: permissionsOK
            )
        }
        let pid = pidNumber.int32Value
        let alive = kill(pid, 0) == 0
        return DaemonHealth(
            status: alive ? .running : .notRunning,
            pid: pid,
            port: portNumber.intValue,
            version: object["version"] as? String,
            tokenPermissionsOK: permissionsOK
        )
    }
}
