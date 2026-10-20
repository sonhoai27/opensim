import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimCore

final class StateAndPortTests: XCTestCase {
    func testTokenLengthAndAlphabet() throws {
        let token = try TokenGenerator.make()
        XCTAssertEqual(token.count, 43)
        XCTAssertFalse(token.contains("+"))
        XCTAssertFalse(token.contains("/"))
        XCTAssertFalse(token.contains("="))
    }

    func testStateStoreWritesSecureFileAndRoundTrips() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-state-\(UUID().uuidString)", isDirectory: true)
        let paths = OpenSimPaths(baseDirectory: root)
        let store = DaemonStateStore(paths: paths)
        let state = DaemonState(
            pid: 42,
            port: 1234,
            token: "token",
            version: "0.1.0",
            xcodeVersion: "27.1",
            startedAt: Date(timeIntervalSince1970: 1_797_000_000)
        )
        try store.write(state)
        XCTAssertEqual(try store.read(), state)
        let attributes = try FileManager.default.attributesOfItem(atPath: paths.daemonStateFile.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        store.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.daemonStateFile.path))
        try? FileManager.default.removeItem(at: root)
    }

    func testProcessLockRejectsSecondOwner() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-lock-\(UUID().uuidString)", isDirectory: true)
        let paths = OpenSimPaths(baseDirectory: root)
        try paths.ensureDirectories()
        let first = try ProcessLock(path: paths.lockFile)
        XCTAssertThrowsError(try ProcessLock(path: paths.lockFile))
        first.release()
        let second = try ProcessLock(path: paths.lockFile)
        second.release()
        try? FileManager.default.removeItem(at: root)
    }

    func testPortAllocatorReturnsLoopbackPort() throws {
        let port = try PortAllocator.freePort()
        XCTAssertGreaterThan(port, 1024)
        XCTAssertLessThan(port, 65_536)
    }
}
