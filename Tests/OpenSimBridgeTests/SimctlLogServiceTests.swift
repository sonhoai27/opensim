import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

private let logLines = """
{"timestamp":"2026-10-20 10:00:00.000001+0700","messageType":"Default","subsystem":"com.apple.UIKit","category":"Application","processImagePath":"/Applications/Preferences.app/Preferences","eventMessage":"first"}
{"timestamp":"2026-10-20 10:00:00.000002+0700","messageType":"Info","subsystem":"com.apple.UIKit","category":"Application","processImagePath":"/Applications/Preferences.app/Preferences","eventMessage":"second"}
{"timestamp":"2026-10-20 10:00:00.000003+0700","messageType":"Error","subsystem":"com.apple.UIKit","category":"Application","processImagePath":"/Applications/Preferences.app/Preferences","eventMessage":"third"}
{"timestamp":"2026-10-20 10:00:00.000004+0700","messageType":"Fault","subsystem":"com.apple.UIKit","category":"Application","processImagePath":"/Applications/Preferences.app/Preferences","eventMessage":"fourth"}
{"timestamp":"2026-10-20 10:00:00.000005+0700","messageType":"Debug","subsystem":"com.apple.UIKit","category":"Application","processImagePath":"/Applications/Preferences.app/Preferences","eventMessage":"fifth"}
"""

final class SimctlLogServiceTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    func testFirstPageUsesLastFiveMinutes() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(logLines))
        let service = SimctlLogService(executor: executor, timeout: .seconds(5))
        let page = try await service.tailLogs(on: udid, cursor: nil, limit: 2, filter: "subsystem == \"com.apple.UIKit\"")
        XCTAssertEqual(page.entries.map(\.message), ["first", "second"])
        XCTAssertEqual(page.entries.map(\.level), [.notice, .info])
        XCTAssertNotNil(page.nextCursor)
        let commands = await executor.commands
        XCTAssertTrue(commands[0].arguments.contains("--last"))
        XCTAssertTrue(commands[0].arguments.contains("5m"))
    }

    func testSecondPageSkipsReturnedEntries() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(logLines))
        await executor.enqueue(jsonOutput(logLines))
        let service = SimctlLogService(executor: executor, timeout: .seconds(5))
        let first = try await service.tailLogs(on: udid, cursor: nil, limit: 2, filter: nil)
        let second = try await service.tailLogs(on: udid, cursor: first.nextCursor, limit: 2, filter: nil)
        XCTAssertEqual(second.entries.map(\.message), ["third", "fourth"])
        let commands = await executor.commands
        XCTAssertTrue(commands[1].arguments.contains("--start"))
        XCTAssertFalse(commands[1].arguments.contains("--last"))
    }

    func testInvalidCursorIsRejectedBeforeRunningSimctl() async throws {
        let executor = StubSimctlExecutor()
        let service = SimctlLogService(executor: executor, timeout: .seconds(5))
        do {
            _ = try await service.tailLogs(on: udid, cursor: "not-a-cursor", limit: 2, filter: nil)
            XCTFail("expected invalid_argument")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "invalid_argument")
        }
        let commands = await executor.commands
        XCTAssertEqual(commands.count, 0)
    }

    func testCrashReportScannerSortsNewestFirst() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-crash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Preferences-2026-10-19-100000.ips")
        let new = root.appendingPathComponent("Safari-2026-10-20-100000.ips")
        try Data("old".utf8).write(to: old)
        try Data("new-data".utf8).write(to: new)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: new.path)

        let reports = try CrashReportScanner.scan(directory: root, limit: 10)
        XCTAssertEqual(reports.map(\.processName), ["Safari", "Preferences"])
        XCTAssertEqual(reports[0].sizeBytes, 8)
    }
}
