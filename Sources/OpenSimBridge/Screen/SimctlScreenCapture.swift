import Foundation
import OpenSimCore

public protocol ScreenDeviceReading: Sendable {
    func device(_ id: DeviceID) async throws -> Device
}

extension SimctlDeviceService: ScreenDeviceReading {}

public struct SimctlScreenCapture: Sendable {
    private let executor: any SimctlExecuting
    private let devices: any ScreenDeviceReading
    private let profiles: any ScreenProfileProviding
    private let paths: OpenSimPaths
    private let timeout: Duration
    private let processor: ScreenshotProcessor

    public init(
        executor: any SimctlExecuting,
        devices: any ScreenDeviceReading,
        profiles: any ScreenProfileProviding,
        paths: OpenSimPaths = OpenSimPaths(),
        timeout: Duration,
        processor: ScreenshotProcessor = ScreenshotProcessor()
    ) {
        self.executor = executor
        self.devices = devices
        self.profiles = profiles
        self.paths = paths
        self.timeout = timeout
        self.processor = processor
    }

    public func screens(for device: DeviceID) async throws -> [ScreenInfo] {
        let command = SimctlArguments.ioEnumerate(device)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let descriptors = ScreenEnumerateParser.parse(String(decoding: output.stdout, as: UTF8.self))
        guard !descriptors.isEmpty else {
            throw OpenSimError(
                code: .capabilityUnavailable,
                message: "Device has no display ports",
                details: ["udid": device.rawValue],
                recovery: "Boot the device and retry"
            )
        }
        let deviceInfo = try await devices.device(device)
        let profile = try await profiles.profile(for: deviceInfo.deviceType)
        return descriptors.enumerated().map { index, descriptor in
            ScreenInfo(
                id: UInt32(index + 1),
                width: descriptor.width,
                height: descriptor.height,
                scale: index == 0 ? profile.scale : 1,
                rotation: index == 0 ? profile.orientation : 0,
                displayClass: descriptor.displayClass
            )
        }
    }

    public func screenshot(
        on device: DeviceID,
        format: ScreenshotFormat,
        scale: Double,
        quality: Int?,
        out: String? = nil
    ) async throws -> Screenshot {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-screenshot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporary) }

        let command = SimctlArguments.ioScreenshot(device, path: temporary.path)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)

        let rendered = try processor.render(source: temporary, format: format, scale: scale, quality: quality)
        let destination: URL
        if let out {
            let validated = try PathPolicy.validateOutputPath(out, allowedExtensions: [format.rawValue])
            destination = URL(fileURLWithPath: validated)
        } else {
            try paths.ensureMediaDirectories()
            destination = paths.screenshotsDirectory
                .appendingPathComponent("shot-\(UUID().uuidString).\(format.rawValue)")
        }
        try rendered.data.write(to: destination, options: .atomic)
        return Screenshot(
            path: destination.path,
            data: nil,
            format: format,
            width: rendered.width,
            height: rendered.height,
            scale: scale,
            capturedAt: Date()
        )
    }
}
