import Foundation
import OpenSimCore
import OpenSimProtocol

public struct DaemonLauncher: Sendable {
    private let paths: OpenSimPaths
    private let stateStore: DaemonStateStore

    public init(paths: OpenSimPaths = OpenSimPaths()) {
        self.paths = paths
        self.stateStore = DaemonStateStore(paths: paths)
    }

    public func ensureRunning() async throws -> DaemonClient {
        try paths.ensureDirectories()
        if let state = try? stateStore.read(), let client = await healthyClient(state: state) {
            return client
        }
        if ProcessInfo.processInfo.environment["OPENSIM_DAEMON_AUTOSTART"] == "0" {
            throw OpenSimError.daemonUnavailable("Daemon is not running and autostart is disabled")
        }
        let manager = LaunchAgentManager(opensimPath: DaemonLauncher.executablePath(), paths: paths)
        try manager.install()
        try? manager.bootout()
        try manager.bootstrap()
        for _ in 0..<50 {
            if let state = try? stateStore.read(), let client = await healthyClient(state: state) {
                return client
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw OpenSimError.daemonUnavailable("Daemon did not become healthy within 5 seconds")
    }

    private func healthyClient(state: DaemonState) async -> DaemonClient? {
        let client = DaemonClient(state: state)
        guard (try? await client.health()) != nil else {
            return nil
        }
        return client
    }

    static func executablePath() -> String {
        if let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path {
            return path
        }
        return CommandLine.arguments[0]
    }
}
