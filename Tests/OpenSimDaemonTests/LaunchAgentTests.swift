import XCTest
@testable import OpenSimDaemon
@testable import OpenSimCore

final class LaunchAgentTests: XCTestCase {
    func testPlistContainsDaemonArgumentsAndEnvironment() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = OpenSimPaths(baseDirectory: root)
        let plistURL = root.appendingPathComponent("dev.opensim.daemon.plist")
        let manager = LaunchAgentManager(
            plistURL: plistURL,
            opensimPath: "/usr/local/bin/opensim",
            paths: paths
        )
        try manager.install()
        let data = try Data(contentsOf: plistURL)
        let object = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(object["Label"] as? String, "dev.opensim.daemon")
        XCTAssertEqual(object["ProgramArguments"] as? [String], ["/usr/local/bin/opensim", "daemon", "run", "--foreground"])
        XCTAssertEqual(object["RunAtLoad"] as? Bool, true)
        let environment = object["EnvironmentVariables"] as? [String: String]
        XCTAssertEqual(environment?["OPENSIM_HOME"], root.path)
    }

    func testDefaultPlistURLPointsAtUserLaunchAgents() {
        let url = LaunchAgentManager.defaultPlistURL()
        XCTAssertTrue(url.path.hasSuffix("/Library/LaunchAgents/dev.opensim.daemon.plist"))
    }
}
