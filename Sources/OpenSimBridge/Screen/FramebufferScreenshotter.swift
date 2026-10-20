import CoreGraphics
import CoreImage
import Foundation
import IOSurface
import ObjectiveC
import OpenSimCore

public struct FramebufferScreenshotter: Sendable {
    private let paths: OpenSimPaths
    private let processor: ScreenshotProcessor

    public init(
        paths: OpenSimPaths = OpenSimPaths(),
        processor: ScreenshotProcessor = ScreenshotProcessor()
    ) {
        self.paths = paths
        self.processor = processor
    }

    public nonisolated static func isSupported(checker: any SimulatorKitClassChecking) -> Bool {
        IOSurfaceDisplaySurface.isSupported(checker: checker)
    }

    public func screenshot(
        on device: DeviceID,
        format: ScreenshotFormat,
        scale: Double,
        quality: Int?,
        out: String?
    ) throws -> Screenshot {
        guard let surface = try captureSurface(device) else {
            throw OpenSimError(
                code: .privateApiUnavailable,
                message: "Framebuffer capture returned no surface",
                details: ["udid": device.rawValue]
            )
        }
        let ciImage = CIImage(ioSurface: surface)
        guard let image = Self.ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw OpenSimError(
                code: .privateApiUnavailable,
                message: "Could not render the framebuffer surface",
                details: ["udid": device.rawValue]
            )
        }
        let rendered = try processor.render(image: image, format: format, scale: scale, quality: quality)

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

    private func captureSurface(_ device: DeviceID) throws -> IOSurface? {
        guard let screenClass = SimulatorKitLoader.resolveClass(named: "SimDeviceScreen") else {
            throw OpenSimError(
                code: .privateApiUnavailable,
                message: "SimDeviceScreen is missing",
                details: ["udid": device.rawValue]
            )
        }
        let deviceObject = try CoreSimulatorDeviceLookup.device(device)
        let initSelector = NSSelectorFromString("initWithDevice:screenID:")
        guard let initMethod = class_getInstanceMethod(screenClass, initSelector),
              let allocated = Self.allocate(screenClass) else {
            throw OpenSimError(
                code: .privateApiUnavailable,
                message: "SimDeviceScreen cannot be created",
                details: ["udid": device.rawValue]
            )
        }
        typealias InitFunction = @convention(c) (AnyObject, Selector, AnyObject, UInt32) -> Unmanaged<AnyObject>?
        let initialize = unsafeBitCast(method_getImplementation(initMethod), to: InitFunction.self)
        guard let screen = initialize(allocated, initSelector, deviceObject, 1)?.takeRetainedValue() else {
            throw OpenSimError(
                code: .privateApiUnavailable,
                message: "SimDeviceScreen initialization returned nil",
                details: ["udid": device.rawValue]
            )
        }
        guard let proxy = callObject(screen, selector: "screen"),
              let surface = callForwarded(proxy, selector: "framebufferSurface") else {
            return nil
        }
        return surface as? IOSurface
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private static func allocate(_ cls: AnyClass) -> AnyObject? {
        let selector = NSSelectorFromString("alloc")
        guard let method = class_getClassMethod(cls, selector) else { return nil }
        typealias AllocateFunction = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let allocate = unsafeBitCast(method_getImplementation(method), to: AllocateFunction.self)
        return allocate(cls as AnyObject, selector)?.takeUnretainedValue()
    }

    private typealias MessageSend = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    private typealias SignatureFunction = @convention(c) (AnyObject, Selector, Selector) -> Unmanaged<AnyObject>?

    private static let messageSend: MessageSend? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend") else {
            return nil
        }
        return unsafeBitCast(symbol, to: MessageSend.self)
    }()

    private static let methodSignatureSelector = NSSelectorFromString("methodSignatureForSelector:")

    private func callObject(_ object: AnyObject, selector name: String) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard let cls = object_getClass(object), let method = class_getInstanceMethod(cls, selector) else {
            return nil
        }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return getter(object, selector)?.takeUnretainedValue()
    }

    private func callForwarded(_ object: AnyObject, selector name: String) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard let nsObject = object as? NSObject,
              hasMethodSignature(nsObject, selector: selector),
              let messageSend = Self.messageSend else {
            return nil
        }
        return messageSend(nsObject, selector)?.takeUnretainedValue()
    }

    private func hasMethodSignature(_ object: NSObject, selector: Selector) -> Bool {
        guard let cls = object_getClass(object),
              let method = class_getInstanceMethod(cls, Self.methodSignatureSelector) else {
            return false
        }
        let function = unsafeBitCast(method_getImplementation(method), to: SignatureFunction.self)
        return function(object, Self.methodSignatureSelector, selector)?.takeUnretainedValue() != nil
    }
}
