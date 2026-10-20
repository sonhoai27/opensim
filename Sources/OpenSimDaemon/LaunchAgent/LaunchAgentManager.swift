import Darwin
import Foundation
import OpenSimCore

public struct LaunchAgentManager: Sendable {
    public static let label = "dev.opensim.daemon"
    public let plistURL: URL
    public let opensimPath: String
    public let paths: OpenSimPaths

    public init(
        plistURL: URL = LaunchAgentManager.defaultPlistURL(),
        opensimPath: String,
        paths: OpenSimPaths
    ) {
        self.plistURL = plistURL
        self.opensimPath = opensimPath
        self.paths = paths
    }

    public static func defaultPlistURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(LaunchAgentManager.label).plist")
    }

    public func install() throws {
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let plist: [String: Any] = [
            "Label": LaunchAgentManager.label,
            "ProgramArguments": [opensimPath, "daemon", "run", "--foreground"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Background",
            "ThrottleInterval": 5,
            "StandardOutPath": paths.logDirectory.appendingPathComponent("daemon.out.log").path,
            "StandardErrorPath": paths.logDirectory.appendingPathComponent("daemon.err.log").path,
            "EnvironmentVariables": ["OPENSIM_HOME": paths.baseDirectory.path],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistURL.path)
    }

    public func bootstrap() throws {
        try expectSuccess(
            runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path]),
            action: "launchctl bootstrap failed"
        )
    }

    public func bootout() throws {
        try expectSuccess(
            runLaunchctl(["bootout", "gui/\(getuid())/\(LaunchAgentManager.label)"]),
            action: "launchctl bootout failed"
        )
    }

    public func kickstart() throws {
        try expectSuccess(
            runLaunchctl(["kickstart", "-k", "gui/\(getuid())/\(LaunchAgentManager.label)"]),
            action: "launchctl kickstart failed"
        )
    }

    public func isLoaded() -> Bool {
        (try? runLaunchctl(["print", "gui/\(getuid())/\(LaunchAgentManager.label)"])) == 0
    }

    private func expectSuccess(_ status: Int32, action: String) throws {
        guard status != 0 else {
            return
        }
        throw OpenSimError(
            code: .daemonUnavailable,
            message: action,
            details: ["status": "\(status)"],
            recovery: "Run `launchctl print gui/\(getuid())/\(LaunchAgentManager.label)`"
        )
    }

    private func runLaunchctl(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        _ = output.fileHandleForReading.readDataToEndOfFile()
        _ = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
