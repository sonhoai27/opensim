import AppKit
import OpenSimBridge
import OpenSimCore

@MainActor
public final class SimulatorScreenView: NSView {
    public let device: DeviceID
    private let bridge: any SimulatorScreenDisplaying
    private var surface: (any DisplaySurface)?
    private let rotationContainer = NSView()
    private let mapper = ScreenPointerMapper()

    public private(set) var screenSize: CGSize = .zero
    public private(set) var rotation: ScreenRotation = .portrait
    public var onScreenSizeChange: ((CGSize) -> Void)?
    public var onError: ((OpenSimError) -> Void)?

    public convenience init(device: DeviceID) throws {
        try self.init(device: device, bridge: SimctlBridge.live())
    }

    public init(device: DeviceID, bridge: any SimulatorScreenDisplaying) {
        self.device = device
        self.bridge = bridge
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 640))
        wantsLayer = true
        rotationContainer.wantsLayer = true
        addSubview(rotationContainer)
    }

    public required init?(coder: NSCoder) {
        nil
    }

    public func connect() async throws {
        guard surface == nil else { return }
        do {
            let surface = try bridge.makeDisplaySurface(for: device)
            surface.onSizeChange = { [weak self] size in self?.update(size) }
            surface.onError = { [weak self] error in self?.onError?(error) }
            try await surface.connect()
            self.surface = surface
            rotationContainer.addSubview(surface.view)
            update(surface.pixelSize)
            needsLayout = true
        } catch let error as OpenSimError {
            onError?(error)
            throw error
        } catch {
            let mapped = OpenSimError(code: .internalError, message: String(describing: error))
            onError?(mapped)
            throw mapped
        }
    }

    public func disconnect() {
        surface?.disconnect()
        surface?.view.removeFromSuperview()
        surface = nil
        if screenSize != .zero {
            screenSize = .zero
            onScreenSizeChange?(.zero)
        }
    }

    public func setRotation(_ rotation: ScreenRotation) {
        self.rotation = rotation
        if let surface {
            update(surface.pixelSize)
        }
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        guard let surface else { return }
        let base = baseSize(surface)
        let displaySize = rotation.isSideways
            ? CGSize(width: base.height, height: base.width)
            : base
        guard base.width > 0, base.height > 0, bounds.width > 0, bounds.height > 0 else {
            return
        }
        let fit = mapper.aspectFitRect(content: displaySize, in: bounds)
        guard displaySize.width > 0, fit.width > 0 else { return }
        let scale = fit.width / displaySize.width

        let scaledBase = CGSize(
            width: base.width * scale,
            height: base.height * scale
        )
        rotationContainer.frame = CGRect(
            x: bounds.midX - scaledBase.width / 2,
            y: bounds.midY - scaledBase.height / 2,
            width: scaledBase.width,
            height: scaledBase.height
        )
        surface.view.frame = rotationContainer.bounds
        rotationContainer.frameCenterRotation = CGFloat(rotation.degrees)
    }

    public func simulatorPoint(fromViewPoint point: NSPoint) -> Point? {
        guard let surface else { return nil }
        return mapper.simulatorPoint(
            fromViewPoint: point,
            in: bounds,
            contentSize: baseSize(surface),
            rotation: rotation
        )
    }

    public func viewPoint(fromSimulatorPoint point: Point) -> NSPoint? {
        guard let surface else { return nil }
        return mapper.viewPoint(
            fromSimulatorPoint: point,
            in: bounds,
            contentSize: baseSize(surface),
            rotation: rotation
        )
    }

    private func baseSize(_ surface: any DisplaySurface) -> CGSize {
        CGSize(
            width: surface.pixelSize.width / max(1, surface.screenScale),
            height: surface.pixelSize.height / max(1, surface.screenScale)
        )
    }

    private func update(_ pixels: CGSize) {
        guard let surface else { return }
        let base = baseSize(surface)
        let size = rotation.isSideways
            ? CGSize(width: base.height, height: base.width)
            : base
        if size != screenSize {
            screenSize = size
            onScreenSizeChange?(size)
            needsLayout = true
        }
    }
}
