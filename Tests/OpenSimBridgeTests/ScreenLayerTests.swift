import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class ScreenLayerTests: XCTestCase {
    func testEnumerateParsesDisplays() {
        let text = """
        Port:
            UUID: A
            Class: Unknown
            Port Identifier: com.apple.display.captureservice

        Port:
            UUID: B
            Class: Display
            Port Identifier: com.apple.framebuffer.display
            Power state: On
            Display class: 0
            Default width: 1260
            Default height: 2736
        """
        let values = ScreenEnumerateParser.parse(text)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0].uuid, "B")
        XCTAssertEqual(values[0].width, 1260)
        XCTAssertEqual(values[0].height, 2736)
        XCTAssertEqual(values[0].displayClass, 0)
    }

    func testIOArgumentsAndOutputPath() throws {
        let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")
        XCTAssertEqual(SimctlArguments.ioEnumerate(udid).arguments, ["io", udid.rawValue, "enumerate"])
        XCTAssertEqual(
            SimctlArguments.ioScreenshot(udid, path: "/tmp/a.png").arguments,
            ["io", udid.rawValue, "screenshot", "--type=png", "/tmp/a.png"]
        )
        XCTAssertEqual(
            SimctlArguments.ioRecordVideo(udid, path: "/tmp/a.mov", codec: .h264).arguments,
            ["io", udid.rawValue, "recordVideo", "--codec=h264", "--force", "/tmp/a.mov"]
        )
        XCTAssertNoThrow(try PathPolicy.validateOutputPath("/tmp/a.png", allowedExtensions: ["png", "jpeg"]))
        XCTAssertThrowsError(try PathPolicy.validateOutputPath("a.png", allowedExtensions: ["png"]))
        XCTAssertThrowsError(try PathPolicy.validateOutputPath("/tmp/a.png", allowedExtensions: ["mov"]))
        XCTAssertThrowsError(try PathPolicy.validateOutputPath("/tmp/missing-dir/a.png", allowedExtensions: ["png"]))
    }

    func testDeviceTypeProfileReadsCapabilities() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-screen-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Fake.simdevicetype", isDirectory: true)
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let capabilities: [String: Any] = [
            "capabilities": [
                "ScreenDimensionsCapability": [
                    "main-screen-scale": 3,
                    "main-screen-orientation": 90,
                    "main-screen-width": 1260,
                    "main-screen-height": 2736,
                ],
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: capabilities, format: .xml, options: 0)
        try data.write(to: resources.appendingPathComponent("capabilities.plist"))

        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("""
        {"devicetypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.Fake","bundlePath":"\(bundle.path)"}]}
        """))
        let provider = SimctlDeviceTypeProfileProvider(executor: executor, timeout: .seconds(5))
        let profile = try await provider.profile(for: "com.apple.CoreSimulator.SimDeviceType.Fake")
        XCTAssertEqual(profile.scale, 3)
        XCTAssertEqual(profile.orientation, 90)
        XCTAssertEqual(profile.width, 1260)
        XCTAssertEqual(profile.height, 2736)
        let commands = await executor.commands
        XCTAssertEqual(commands[0].arguments, ["list", "devicetypes", "-j"])
    }

    func testScreenshotProcessorScalesAndEncodes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-shot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.png")
        try writePNG(width: 2, height: 1, to: source)

        let processor = ScreenshotProcessor()
        let png = try processor.render(source: source, format: .png, scale: 2, quality: nil)
        XCTAssertEqual(png.width, 4)
        XCTAssertEqual(png.height, 2)
        XCTAssertEqual(Array(png.data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        let jpeg = try processor.render(source: source, format: .jpeg, scale: 1, quality: 50)
        XCTAssertEqual(Array(jpeg.data.prefix(2)), [0xFF, 0xD8])
        XCTAssertThrowsError(try processor.render(source: source, format: .png, scale: 0, quality: nil))
        XCTAssertThrowsError(try processor.render(source: source, format: .png, scale: 1, quality: 50))
        XCTAssertThrowsError(try processor.render(source: source, format: .jpeg, scale: 1, quality: 101))
    }

    func testEnsureMediaDirectoriesUsesPrivatePermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-paths-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = OpenSimPaths(baseDirectory: root)
        try paths.ensureMediaDirectories()
        for directory in [paths.screenshotsDirectory, paths.recordingsDirectory, paths.recordingStateDirectory] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        }
    }

    private func writePNG(width: Int, height: Int, to url: URL) throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
