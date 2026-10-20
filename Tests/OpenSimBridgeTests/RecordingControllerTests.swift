import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class RecordingControllerTests: XCTestCase {
    func testStartStopAndBusy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let handle = FakeRecordingHandle()
        let controller = SimctlRecordingController(
            launcher: FakeRecordingLauncher(handle: handle),
            store: RecordingStateStore(directory: root),
            paths: OpenSimPaths(baseDirectory: root),
            now: { Date(timeIntervalSince1970: 10) }
        )
        let device = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")
        let path = root.appendingPathComponent("a.mov")
        let id = try await controller.start(on: device, to: path.path, codec: .h264)

        do {
            _ = try await controller.start(on: device, to: path.path, codec: .h264)
            XCTFail("expected device_busy while a recording is active")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "device_busy")
        }

        let info = try await controller.info(id)
        XCTAssertEqual(info.path, path.path)
        XCTAssertEqual(info.deviceID, device)
        let stateFile = root.appendingPathComponent("\(id.rawValue).json")
        let attributes = try FileManager.default.attributesOfItem(atPath: stateFile.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try Data("video".utf8).write(to: path)
        handle.finish()
        let result = try await controller.stop(id)
        XCTAssertEqual(result.path, path.path)
        XCTAssertTrue(handle.didReceiveInterrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateFile.path))
    }

    func testStopUnknownRecordingThrows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = SimctlRecordingController(
            launcher: FakeRecordingLauncher(handle: FakeRecordingHandle()),
            store: RecordingStateStore(directory: root),
            paths: OpenSimPaths(baseDirectory: root)
        )
        do {
            _ = try await controller.stop(RecordingID("missing"))
            XCTFail("expected invalid_argument")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "invalid_argument")
        }
    }
}

final class FakeRecordingHandle: RecordingProcessHandle, @unchecked Sendable {
    let processIdentifier: Int32 = 42_424
    private(set) var didReceiveInterrupt = false
    private var finished = false

    func sendInterrupt() throws { didReceiveInterrupt = true }
    func waitForExit(timeout: Duration) async -> Bool { finished }
    func isRunning() -> Bool { !finished }
    func finish() { finished = true }
}

struct FakeRecordingLauncher: RecordingProcessLaunching {
    let handle: FakeRecordingHandle

    func launch(arguments: [String], path: String) async throws -> any RecordingProcessHandle {
        handle
    }
}
