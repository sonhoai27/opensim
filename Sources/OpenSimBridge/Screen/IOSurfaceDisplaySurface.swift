import AppKit
import CoreImage
import Foundation
import IOSurface
import ObjectiveC
import OpenSimCore

@MainActor
public final class IOSurfaceDisplaySurface: DisplaySurface {
    public let device: DeviceID
    public let view: NSView
    public private(set) var pixelSize: CGSize = .zero
    public var screenScale: CGFloat = 1
    public var onSizeChange: ((CGSize) -> Void)?
    public var onError: ((OpenSimError) -> Void)?

    private var screenObject: AnyObject?
    private var framebufferSurface: IOSurface?
    private var refreshTask: Task<Void, Never>?
    private var isConnected = false

    public init(device: DeviceID) {
        self.device = device
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.contentsGravity = .resizeAspect
        self.view = view
    }

    public nonisolated static func isSupported(checker: any SimulatorKitClassChecking) -> Bool {
        checker.hasClass("SimServiceContext")
            && checker.hasClass("SimDeviceScreen")
            && checker.responds("SimDeviceScreen", "screen")
    }

    public func connect() async throws {
        guard !isConnected else { return }
        let checker = SimulatorKitLoader.live()
        guard Self.isSupported(checker: checker) else {
            throw surfaceError("IOSurface display is unavailable in this Xcode build")
        }
        guard let screenClass = SimulatorKitLoader.resolveClass(named: "SimDeviceScreen") else {
            throw surfaceError("SimDeviceScreen is missing")
        }
        let deviceObject = try CoreSimulatorDeviceLookup.device(device)
        let selector = NSSelectorFromString("initWithDevice:screenID:")
        guard let method = class_getInstanceMethod(screenClass, selector) else {
            throw surfaceError("SimDeviceScreen cannot be created")
        }
        guard let allocated = class_createInstance(screenClass, 0) as AnyObject? else {
            throw surfaceError("Could not allocate SimDeviceScreen")
        }
        typealias InitFunction = @convention(c) (AnyObject, Selector, AnyObject, UInt32) -> Unmanaged<AnyObject>?
        let initialize = unsafeBitCast(method_getImplementation(method), to: InitFunction.self)
        guard let screen = initialize(allocated, selector, deviceObject, 1)?.takeRetainedValue() else {
            throw surfaceError("SimDeviceScreen initialization returned nil")
        }
        screenObject = screen
        do {
            try updateSurface()
        } catch {
            screenObject = nil
            throw error
        }
        isConnected = true
        startRefresh()
    }

    public func disconnect() {
        isConnected = false
        refreshTask?.cancel()
        refreshTask = nil
        view.layer?.contents = nil
        framebufferSurface = nil
        screenObject = nil
    }

    private func startRefresh() {
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, self.isConnected else { return }
                do {
                    try self.updateSurface()
                } catch {
                    self.onError?(error as? OpenSimError ?? self.surfaceError("\(error)"))
                    self.disconnect()
                    return
                }
            }
        }
    }

    private func updateSurface() throws {
        guard let screenObject else {
            throw surfaceError("SimDeviceScreen is not connected")
        }
        guard let proxy = callObject(screenObject, selector: "screen") else {
            throw surfaceError("SimDeviceScreen.screen returned nil")
        }
        guard let surface = callForwarded(proxy, selector: "framebufferSurface") else {
            throw surfaceError("framebufferSurface returned nil")
        }
        guard let ioSurface = surface as? IOSurface else {
            throw surfaceError("framebufferSurface is not an IOSurface")
        }
        framebufferSurface = ioSurface
        let width = IOSurfaceGetWidth(ioSurface)
        let height = IOSurfaceGetHeight(ioSurface)
        let ciImage = CIImage(ioSurface: ioSurface)
        if let cgImage = Self.ciContext.createCGImage(ciImage, from: ciImage.extent) {
            setLayerContents(cgImage)
        }
        let size = CGSize(width: width, height: height)
        if size != pixelSize {
            pixelSize = size
            onSizeChange?(size)
        }
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private func setLayerContents(_ contents: AnyObject) {
        guard let layer = view.layer else { return }
        let selector = NSSelectorFromString("setContents:")
        guard let method = class_getInstanceMethod(object_getClass(layer), selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)
        setter(layer, selector, contents)
    }

    private func callObject(_ object: AnyObject, selector name: String) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard let cls = object_getClass(object), let method = class_getInstanceMethod(cls, selector) else {
            return nil
        }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return getter(object, selector)?.takeUnretainedValue()
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

    private func surfaceError(_ message: String) -> OpenSimError {
        OpenSimError(
            code: .privateApiUnavailable,
            message: message,
            details: ["udid": device.rawValue],
            recovery: "Use Xcode 27.1 or fall back to screenshot polling"
        )
    }
}
