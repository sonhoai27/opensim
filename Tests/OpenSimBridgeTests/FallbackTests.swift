import AppKit
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class StubScreenService: ScreenControlling, @unchecked Sendable {
    private var results: [Result<Screenshot, Error>]

    init(results: [Result<Screenshot, Error>]) {
        self.results = results
    }

    func screens(for device: DeviceID) async throws -> [ScreenInfo] { [] }

    func screenshot(
        on device: DeviceID,
        format: ScreenshotFormat,
        scale: Double,
        quality: Int?
    ) async throws -> Screenshot {
        guard !results.isEmpty else {
            throw OpenSimError(code: .inputFailed, message: "no stub frame")
        }
        return try results.removeFirst().get()
    }

    func startRecording(on device: DeviceID, to path: String?, codec: VideoCodec) async throws -> RecordingID {
        RecordingID("stub")
    }

    func stopRecording(_ id: RecordingID) async throws -> String { "/tmp/stub.mov" }
}

struct SurfaceChecker: SimulatorKitClassChecking {
    var classes: Set<String> = []
    var selectors: Set<String> = []

    func hasClass(_ name: String) -> Bool { classes.contains(name) }
    func responds(_ className: String, _ selector: String) -> Bool { selectors.contains("\(className).\(selector)") }
    func indigoSymbols() -> [String] { [] }
    func sendSelectors(className: String) -> [String] { [] }
}

final class FallbackTests: XCTestCase {
    func testIOSurfaceSupport() {
        var checker = SurfaceChecker()
        checker.classes = ["SimServiceContext", "SimDeviceScreen"]
        checker.selectors = ["SimDeviceScreen.screen"]
        XCTAssertTrue(IOSurfaceDisplaySurface.isSupported(checker: checker))

        checker.selectors = []
        XCTAssertFalse(IOSurfaceDisplaySurface.isSupported(checker: checker))

        var missingDeviceClass = SurfaceChecker()
        missingDeviceClass.classes = ["SimServiceContext"]
        missingDeviceClass.selectors = ["SimDeviceScreen.screen"]
        XCTAssertFalse(IOSurfaceDisplaySurface.isSupported(checker: missingDeviceClass))
    }

    func testSnapshotMapper() {
        let node = HelperNode(
            role: "button",
            identifier: "fixture-primary-button",
            label: "Primary Action",
            value: nil,
            x: 10,
            y: 20,
            width: 100,
            height: 44,
            enabled: true,
            selected: false,
            children: [
                HelperNode(
                    role: "staticText",
                    identifier: nil,
                    label: "Primary Action",
                    value: nil,
                    x: 10,
                    y: 20,
                    width: 100,
                    height: 44,
                    enabled: true,
                    selected: false,
                    children: []
                ),
            ]
        )
        let element = XCUITestSnapshotMapper.toUIElement(node, path: "0")
        XCTAssertEqual(element.id, "xct-0")
        XCTAssertEqual(element.identifier, "fixture-primary-button")
        XCTAssertEqual(element.frame, Rect(x: 10, y: 20, width: 100, height: 44))
        XCTAssertEqual(element.children[0].id, "xct-0.0")
        let tree = XCUITestSnapshotMapper.limited(element, maxDepth: 0, maxNodes: 5)
        XCTAssertTrue(tree.truncated)
        XCTAssertEqual(tree.nodeCount, 1)
        XCTAssertTrue(tree.root.children.isEmpty)
    }

    func testSnapshotMapperLimitsNodes() {
        let child = HelperNode(
            role: "staticText",
            identifier: "child",
            label: nil,
            value: nil,
            x: 0,
            y: 0,
            width: 10,
            height: 10,
            enabled: true,
            selected: false,
            children: []
        )
        let root = HelperNode(
            role: "window",
            identifier: nil,
            label: nil,
            value: nil,
            x: 0,
            y: 0,
            width: 100,
            height: 100,
            enabled: true,
            selected: false,
            children: [child, child]
        )
        let element = XCUITestSnapshotMapper.toUIElement(root, path: "0")
        let tree = XCUITestSnapshotMapper.limited(element, maxDepth: 5, maxNodes: 2)
        XCTAssertEqual(tree.nodeCount, 2)
        XCTAssertTrue(tree.truncated)
        XCTAssertEqual(tree.root.children.count, 1)
    }

    @MainActor
    func testScreenshotPollingSurfaceLoadsFrames() async throws {
        let service = StubScreenService(
            results: [.success(Screenshot(
                path: nil,
                data: Self.onePixelPNG,
                format: .png,
                width: 1,
                height: 1,
                scale: 1,
                capturedAt: Date()
            ))]
        )
        let surface = ScreenshotPollingSurface(
            device: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            screens: service
        )
        try await surface.connect()
        XCTAssertEqual(surface.pixelSize, CGSize(width: 1, height: 1))
        XCTAssertNotNil((surface.view as? NSImageView)?.image)
        surface.disconnect()
    }

    @MainActor
    func testScreenshotPollingStopsAfterThreeFailures() async throws {
        let service = StubScreenService(
            results: [
                .success(Screenshot(
                    path: nil,
                    data: Self.onePixelPNG,
                    format: .png,
                    width: 1,
                    height: 1,
                    scale: 1,
                    capturedAt: Date()
                )),
                .failure(OpenSimError(code: .simctlFailed, message: "frame failed")),
                .failure(OpenSimError(code: .simctlFailed, message: "frame failed")),
                .failure(OpenSimError(code: .simctlFailed, message: "frame failed")),
            ]
        )
        let surface = ScreenshotPollingSurface(
            device: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            screens: service
        )
        var received: OpenSimError?
        surface.onError = { received = $0 }
        try await surface.connect()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(received?.code, "capability_unavailable")
    }

    private static let onePixelPNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!

    func testXCUITestHelperTreeAndTap() async throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_GATE"] == "1" else {
            throw XCTSkip("set OPENSIM_GATE=1 to run the XCUITest helper")
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Fixtures/OpenSimFixture", isDirectory: true)
        let build = try runProcess(root.appendingPathComponent("build.sh").path, arguments: [], directory: root)
        XCTAssertEqual(build.status, 0, build.output)
        guard let appPath = build.output
            .split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { $0.hasSuffix(".app") }) else {
            XCTFail("build.sh did not print the app path")
            return
        }

        let executor = ProcessSimctlExecutor()
        let devices = SimctlDeviceService(executor: executor, timeout: .seconds(30))
        guard let booted = try await devices.listDevices().first(where: { $0.state == .booted }) else {
            throw XCTSkip("no booted simulator")
        }
        let install = try await executor.run(
            SimctlArguments.installApp(booted.id, path: appPath),
            timeout: .seconds(120)
        )
        XCTAssertEqual(install.status, 0, String(decoding: install.stderr, as: UTF8.self))
        let launch = try await executor.run(
            SimctlArguments.launchApp(booted.id, bundleID: "dev.opensim.fixture", args: [], environment: [:]),
            timeout: .seconds(60)
        )
        XCTAssertEqual(launch.status, 0, String(decoding: launch.stderr, as: UTF8.self))
        try await Task.sleep(for: .seconds(2))

        XCTAssertTrue(XCUITestHelperRunner.isConfigured)
        let runner = XCUITestHelperRunner()
        let response = try await runner.run(
            device: booted.id,
            bundleID: "dev.opensim.fixture",
            action: .tree
        )
        XCTAssertTrue(response.ok, response.error ?? "")
        let node = try XCTUnwrap(response.node)
        let rootElement = XCUITestSnapshotMapper.toUIElement(node, path: "0")
        let matches = UIElementMatcher.find(
            in: rootElement,
            selector: ElementSelector(identifier: "fixture-primary-button")
        )
        XCTAssertFalse(matches.isEmpty)

        let tap = try await runner.run(
            device: booted.id,
            bundleID: "dev.opensim.fixture",
            action: XCUITestHelperAction(kind: .tapIdentifier, identifier: "fixture-primary-button")
        )
        XCTAssertTrue(tap.ok, tap.error ?? "")
    }

    private func runProcess(
        _ executable: String,
        arguments: [String],
        directory: URL?
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: out + err, as: UTF8.self))
    }

    @MainActor
    func testIOSurfaceConnectsToBootedDevice() async throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_GATE"] == "1" else {
            throw XCTSkip("set OPENSIM_GATE=1 to connect to a booted simulator")
        }
        let service = SimctlDeviceService(executor: ProcessSimctlExecutor(), timeout: .seconds(30))
        guard let booted = try await service.listDevices().first(where: { $0.state == .booted }) else {
            throw XCTSkip("no booted simulator")
        }
        let surface = IOSurfaceDisplaySurface(device: booted.id)
        try await surface.connect()
        defer { surface.disconnect() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(surface.pixelSize.width, 0)
        XCTAssertGreaterThan(surface.pixelSize.height, 0)
        XCTAssertNotNil(surface.view.layer?.contents)
    }
}
