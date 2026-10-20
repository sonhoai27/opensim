import Foundation
import OpenSimCore

public struct SimctlScreenService: ScreenControlling, RecordingControlling {
    private let capture: SimctlScreenCapture
    private let recorder: SimctlRecordingController

    public init(capture: SimctlScreenCapture, recorder: SimctlRecordingController) {
        self.capture = capture
        self.recorder = recorder
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
        try await capture.screenshot(on: device, format: format, scale: scale, quality: quality, out: nil)
    }

    public func screenshot(
        on device: DeviceID,
        format: ScreenshotFormat,
        scale: Double,
        quality: Int?,
        out: String?
    ) async throws -> Screenshot {
        try await capture.screenshot(on: device, format: format, scale: scale, quality: quality, out: out)
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
