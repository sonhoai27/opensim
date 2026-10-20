import AppKit
import Foundation
import OpenSimCore

@MainActor
public final class ScreenshotPollingSurface: DisplaySurface {
    public let device: DeviceID
    public private(set) var pixelSize: CGSize = .zero
    public var screenScale: CGFloat = 1
    public var onSizeChange: ((CGSize) -> Void)?
    public var onError: ((OpenSimError) -> Void)?

    private let screens: any ScreenControlling
    private let imageView = NSImageView()
    private var pollTask: Task<Void, Never>?
    private var failures = 0
    private var isConnected = false

    public var view: NSView { imageView }

    public init(device: DeviceID, screens: any ScreenControlling) {
        self.device = device
        self.screens = screens
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.black.cgColor
    }

    public func connect() async throws {
        guard !isConnected else { return }
        isConnected = true
        do {
            try await poll()
        } catch {
            isConnected = false
            throw error
        }
        startPolling()
    }

    public func disconnect() {
        isConnected = false
        pollTask?.cancel()
        pollTask = nil
        imageView.image = nil
    }

    private func poll() async throws {
        let screenshot = try await screens.screenshot(on: device, format: .png, scale: 1, quality: nil)
        let data: Data?
        if let inline = screenshot.data {
            data = inline
        } else if let path = screenshot.path {
            data = try? Data(contentsOf: URL(fileURLWithPath: path))
        } else {
            data = nil
        }
        guard let data, let image = NSImage(data: data) else {
            throw OpenSimError(
                code: .inputFailed,
                message: "Screenshot polling could not decode a frame",
                details: ["udid": device.rawValue]
            )
        }
        imageView.image = image
        let size = CGSize(width: screenshot.width, height: screenshot.height)
        if size != pixelSize {
            pixelSize = size
            onSizeChange?(size)
        }
    }

    private func startPolling() {
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.isConnected else { return }
                do {
                    try await self.poll()
                    self.failures = 0
                } catch {
                    self.failures += 1
                    if self.failures >= 3 {
                        self.onError?(OpenSimError.capabilityUnavailable("screen_polling"))
                        self.disconnect()
                        return
                    }
                }
            }
        }
    }
}
