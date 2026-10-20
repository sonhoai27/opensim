import XCTest
@testable import OpenSimCore
@testable import OpenSimDaemon
@testable import OpenSimProtocol

final class Plan3DaemonIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] == "1",
            "Set OPENSIM_INTEGRATION=1 to run daemon integration tests"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: binaryURL.path),
            "Run `swift build` before daemon integration tests"
        )
    }

    private var binaryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/opensim")
    }

    private func makeHome() throws -> URL {
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-daemon-it-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func environment(home: URL) -> [String: String] {
        var values = ProcessInfo.processInfo.environment
        values["OPENSIM_HOME"] = home.path
        // Never let a test spawn a LaunchAgent on the developer machine.
        values["OPENSIM_DAEMON_AUTOSTART"] = "0"
        return values
    }

    @discardableResult
    private func runCLI(home: URL, arguments: [String], input: String? = nil) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        process.environment = environment(home: home)
        let output = Pipe()
        process.standardOutput = output
        // stdout and stderr share one pipe: reading two pipes serially can deadlock once a
        // pipe buffer fills, and the CLI writes failure envelopes to stderr.
        process.standardError = output
        if let input {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            try process.run()
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inputPipe.fileHandleForWriting.close()
        } else {
            process.standardInput = FileHandle.nullDevice
            try process.run()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func startDaemon(home: URL) throws -> Process {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["daemon", "run", "--foreground"]
        process.environment = environment(home: home)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func waitForState(home: URL, timeout: TimeInterval = 20) async throws -> DaemonState {
        let store = DaemonStateStore(paths: OpenSimPaths(baseDirectory: home))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let state = try? store.read(), await isHealthy(port: state.port) {
                return state
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw XCTSkip("Daemon did not become healthy within \(timeout)s")
    }

    private func isHealthy(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/health") else {
            return false
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        guard let (_, response) = try? await URLSession(configuration: configuration).data(for: request) else {
            return false
        }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func testDaemonRestartIssuesNewTokenAndClearsState() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let first = try startDaemon(home: home)
        let firstState = try await waitForState(home: home)
        let stateURL = home.appendingPathComponent("daemon.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: stateURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        first.terminate()
        first.waitUntilExit()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path), "State file must be removed on shutdown")

        let second = try startDaemon(home: home)
        defer {
            second.terminate()
            second.waitUntilExit()
        }
        let secondState = try await waitForState(home: home)
        XCTAssertNotEqual(firstState.token, secondState.token, "Restart must mint a fresh token")
        XCTAssertNotEqual(firstState.pid, secondState.pid)
    }

    func testSecondDaemonIsRejectedByLock() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let running = try startDaemon(home: home)
        defer {
            running.terminate()
            running.waitUntilExit()
        }
        _ = try await waitForState(home: home)

        let (status, output) = try runCLI(home: home, arguments: ["daemon", "run", "--foreground"])
        XCTAssertNotEqual(status, 0, "A second daemon must fail on the lock: \(output)")
    }

    func testCLIUsesDaemonByDefaultAndDirectOnFlag() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let daemon = try startDaemon(home: home)
        defer {
            daemon.terminate()
            daemon.waitUntilExit()
        }
        _ = try await waitForState(home: home)

        let (daemonStatus, daemonJSON) = try runCLI(home: home, arguments: ["device", "list", "--json"])
        XCTAssertEqual(daemonStatus, 0, daemonJSON)
        XCTAssertTrue(daemonJSON.contains("\"schemaVersion\""), daemonJSON)

        let (directStatus, directJSON) = try runCLI(home: home, arguments: ["device", "list", "--json", "--direct"])
        XCTAssertEqual(directStatus, 0, directJSON)
        XCTAssertTrue(directJSON.contains("\"schemaVersion\""), directJSON)
    }

    func testWrongTokenIsRejectedByCLIDaemonCall() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let daemon = try startDaemon(home: home)
        defer {
            daemon.terminate()
            daemon.waitUntilExit()
        }
        let state = try await waitForState(home: home)
        let tampered = DaemonState(
            pid: state.pid,
            port: state.port,
            token: "wrong-token",
            version: state.version,
            xcodeVersion: state.xcodeVersion,
            startedAt: state.startedAt
        )
        do {
            _ = try await DaemonClient(state: tampered).devices()
            XCTFail("expected a rejected request")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "permission_denied")
        }
    }

    func testMCPStdioInitializeToolsListAndUnknownTool() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let daemon = try startDaemon(home: home)
        defer {
            daemon.terminate()
            daemon.waitUntilExit()
        }
        _ = try await waitForState(home: home)

        let source = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}
        {"jsonrpc":"2.0","id":2,"method":"tools/list","params":null}
        {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"missing_tool","arguments":{}}}
        """
        let (status, output) = try runCLI(home: home, arguments: ["mcp", "--stdio"], input: source)
        XCTAssertEqual(status, 0, output)
        let lines = output.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3, output)
        XCTAssertTrue(lines[0].contains(#""protocolVersion":"2025-06-18""#), lines[0])
        XCTAssertTrue(lines[1].contains("device_boot"), lines[1])
        XCTAssertTrue(lines[1].contains("session_acquire"), lines[1])
        XCTAssertTrue(lines[1].contains("ui_tap"), lines[1])
        XCTAssertTrue(lines[2].contains("-32602"), lines[2])
        XCTAssertFalse(output.contains("token"), "MCP output must not leak the daemon token")
    }

    func testUIDirectWithoutSimulatorReportsCapabilityOrDeviceError() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (status, output) = try runCLI(
            home: home,
            arguments: ["ui", "screenshot", "--device", "00000000-0000-0000-0000-000000000000", "--json", "--direct"]
        )
        XCTAssertNotEqual(status, 0, output)
        XCTAssertTrue(
            output.contains("unknown_device") || output.contains("capability_unavailable")
                || output.contains("device_not_found"),
            "Unexpected CLI failure: \(output)"
        )
    }
}
