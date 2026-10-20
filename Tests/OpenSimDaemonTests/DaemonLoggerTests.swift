import Logging
import XCTest
@testable import OpenSimDaemon

final class DaemonLoggerTests: XCTestCase {
    private func contents(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func testFileLoggerWritesLines() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("daemon.log")
        let logger = DaemonLogger.makeLogger(fileURL: file, maxBytes: 10 * 1_024 * 1_024)
        logger.info("hello daemon")

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(contents(of: file).contains("hello daemon"))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testFileLoggerRotatesAtMaxBytesAndCapsArchives() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-rotate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("daemon.log")
        let logger = DaemonLogger.makeLogger(fileURL: file, maxBytes: 200, maxFiles: 3)
        for index in 0..<20 {
            logger.info("line \(index) with enough text to force rotation")
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(files.contains("daemon.log"))
        XCTAssertEqual(files.filter { $0.hasPrefix("daemon.log.") }.count, 3)
        XCTAssertTrue(contents(of: file).contains("line 19"))
        XCTAssertFalse(contents(of: file).contains("line 0 "))
    }
}
