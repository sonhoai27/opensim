import Foundation
import OpenSimCore

public struct SimctlScreenService: ScreenControlling, RecordingControlling, ScreenshotOutWriting {
    private let capture: SimctlScreenCapture
    private let recorder: SimctlRecordingController
    private let framebuffer: FramebufferScreenshotter?

    public init(
        capture: SimctlScreenCapture,
        recorder: SimctlRecordingController,
        framebuffer: FramebufferScreenshotter? = nil
    ) {
        self.capture = capture
        self.recorder = recorder
        self.framebuffer = framebuffer
    }

    public func screens(for device: DeviceID) async throws -> [ScreenInfo] {
        try await capture.screens(for: device)
    }

    public func screenshot(
        on device: DeviceID,
        format: ScreenshotFormat,
        scale: Double,
        quality: Int?
    ) async throws -> Screenshot {
        if let framebuffer {
            do {
                return try framebuffer.screenshot(
                    on: device,
                    format: format,
                    scale: scale,
                    quality: quality,
                    out: nil
                )
            } catch let error as OpenSimError where error.code == ErrorCode.privateApiUnavailable.rawValue {
                // Fall back to simctl when the private framebuffer path is unavailable.
            }
        }
        return try await capture.screenshot(on: device, format: format, scale: scale, quality: quality, out: nil)
    }

    public func screenshot(
        on device: DeviceID,
        format: ScreenshotFormat,
        scale: Double,
        quality: Int?,
        out: String?
    ) async throws -> Screenshot {
        if let framebuffer {
            do {
                return try framebuffer.screenshot(
                    on: device,
                    format: format,
                    scale: scale,
                    quality: quality,
                    out: out
                )
            } catch let error as OpenSimError where error.code == ErrorCode.privateApiUnavailable.rawValue {
                // Fall back to simctl when the private framebuffer path is unavailable.
            }
        }
        return try await capture.screenshot(on: device, format: format, scale: scale, quality: quality, out: out)
    }

    public func startRecording(on device: DeviceID, to path: String?, codec: VideoCodec) async throws -> RecordingID {
        try await recorder.start(on: device, to: path, codec: codec)
    }

    public func stopRecording(_ id: RecordingID) async throws -> String {
        try await recorder.stop(id).path
    }

    public func recordingInfo(_ id: RecordingID) async throws -> RecordingInfo {
        try await recorder.info(id)
    }

    public func stopRecordingResult(_ id: RecordingID) async throws -> RecordingStopResult {
        try await recorder.stop(id)
    }
}
