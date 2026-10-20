import AppKit
import Foundation
import OpenSimBridge
import OpenSimBridgeUI
import OpenSimCore

@MainActor
final class PreviewController: NSObject, NSApplicationDelegate {
    private let snapshotPath: String?
    private let requestedDevice: String?
    private let autoClick: Bool
    private let snapshotDelay: TimeInterval
    private var window: NSWindow?
    private var screenView: SimulatorScreenView?
    private var statusLabel: NSTextField?
    private var bridge: SimctlBridge?
    private var device: Device?
    private var connectionTask: Task<Void, Never>?
    private var didCapture = false
    private var mouseDownViewPoint: NSPoint?
    private var mouseMonitor: Any?

    init(
        snapshotPath: String?,
        requestedDevice: String?,
        autoClick: Bool,
        snapshotDelay: TimeInterval
    ) {
        self.snapshotPath = snapshotPath
        self.requestedDevice = requestedDevice
        self.autoClick = autoClick
        self.snapshotDelay = snapshotDelay
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        installMouseMonitor()
        connectionTask = Task { [weak self] in
            await self?.connect()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let bridge {
            Task.detached {
                await bridge.shutdownHelper()
            }
            usleep(200_000)
        }
        return .terminateNow
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 980),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenSim Preview"
        window.center()

        let content = NSView()
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

        let status = NSTextField(labelWithString: "Connecting…")
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        statusLabel = status

        let home = NSButton(title: "Home", target: self, action: #selector(homePressed))
        home.bezelStyle = .rounded
        let reconnect = NSButton(title: "Reconnect", target: self, action: #selector(reconnectPressed))
        reconnect.bezelStyle = .rounded

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(status)
        toolbar.addArrangedSubview(spacer)
        toolbar.addArrangedSubview(home)
        toolbar.addArrangedSubview(reconnect)

        content.addSubview(toolbar)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
        ])

        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func connect() async {
        statusLabel?.stringValue = "Starting bridge…"
        do {
            let bridge = try SimctlBridge.live(timeout: .seconds(90))
            self.bridge = bridge
            let device = try await pickDevice(bridge)
            self.device = device
            statusLabel?.stringValue = "\(device.name) · \(device.id.rawValue.prefix(8))"

            let screen = try SimulatorScreenView(device: device.id, bridge: bridge)
            screen.onScreenSizeChange = { [weak self] size in
                self?.resizeWindow(for: size)
            }
            screen.onError = { [weak self] error in
                self?.statusLabel?.stringValue = "Render error: \(error.message)"
            }

            guard let content = window?.contentView else { return }
            content.addSubview(screen)
            screen.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                screen.topAnchor.constraint(equalTo: content.topAnchor, constant: 44),
                screen.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                screen.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                screen.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
            self.screenView = screen
            try await screen.connect()
            statusLabel?.stringValue = "\(device.name) · \(Int(screen.screenSize.width))×\(Int(screen.screenSize.height))"
            resizeWindow(for: screen.screenSize)
            if autoClick {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.performSelfClick()
                }
            }
            scheduleSnapshotIfNeeded()
        } catch {
            let message = (error as? OpenSimError)?.message ?? String(describing: error)
            statusLabel?.stringValue = "Error: \(message)"
            print("OpenSimPreview error: \(message)")
            if snapshotPath != nil {
                NSApp.terminate(nil)
            }
        }
    }

    private func pickDevice(_ bridge: SimctlBridge) async throws -> Device {
        let devices = try await bridge.devices.listDevices()
        if let query = requestedDevice, !query.isEmpty {
            return try DeviceResolver.resolve(query: query, in: devices)
        }
        if let booted = devices.first(where: { $0.state == .booted && $0.platform == .iOS }) {
            return booted
        }
        guard let candidate = devices.first(where: { $0.platform == .iOS && $0.isAvailable }) else {
            throw OpenSimError(
                code: .deviceNotFound,
                message: "No iOS simulator is available",
                recovery: "Create or boot an iOS simulator first"
            )
        }
        statusLabel?.stringValue = "Booting \(candidate.name)…"
        return try await bridge.devices.boot(candidate.id, wait: true)
    }

    private func resizeWindow(for size: CGSize) {
        guard let window, size.width > 0, size.height > 0 else { return }
        let maxHeight: CGFloat = 1_000
        let scale = min(1, maxHeight / size.height)
        window.setContentSize(NSSize(width: max(360, size.width * scale), height: max(480, size.height * scale) + 44))
    }

    private func scheduleSnapshotIfNeeded() {
        guard let snapshotPath, !didCapture else { return }
        didCapture = true
        DispatchQueue.main.asyncAfter(deadline: .now() + snapshotDelay) { [weak self] in
            self?.captureSnapshot(to: snapshotPath)
        }
    }

    private func captureSnapshot(to path: String) {
        guard let window, let content = window.contentView else {
            print("OpenSimPreview snapshot failed: no window")
            NSApp.terminate(nil)
            return
        }
        window.displayIfNeeded()
        content.layoutSubtreeIfNeeded()
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            print("OpenSimPreview snapshot failed: no bitmap")
            NSApp.terminate(nil)
            return
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("OpenSimPreview snapshot failed: no PNG")
            NSApp.terminate(nil)
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("OPENSIM_PREVIEW_SNAPSHOT=\(path)")
        } catch {
            print("OpenSimPreview snapshot write failed: \(error)")
        }
        NSApp.terminate(nil)
    }

    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        ) { [weak self] event in
            self?.handleMouse(event)
            return event
        }
    }

    private func handleMouse(_ event: NSEvent) {
        guard let window, event.window === window, let screenView else { return }
        let point = screenView.convert(event.locationInWindow, from: nil)
        guard screenView.bounds.contains(point) else { return }
        switch event.type {
        case .leftMouseDown:
            mouseDownViewPoint = point
        case .leftMouseUp:
            guard let startPoint = mouseDownViewPoint else { return }
            mouseDownViewPoint = nil
            guard let from = screenView.simulatorPoint(fromViewPoint: startPoint),
                  let to = screenView.simulatorPoint(fromViewPoint: point) else {
                return
            }
            let distance = hypot(point.x - startPoint.x, point.y - startPoint.y)
            if distance > 8 {
                sendSwipe(from: from, to: to)
            } else {
                sendTap(at: to)
            }
        default:
            break
        }
    }

    private func sendSwipe(from: Point, to: Point) {
        guard let bridge, let device else { return }
        guard let input = bridge.input else {
            statusLabel?.stringValue = "drag → helper off"
            return
        }
        statusLabel?.stringValue = "drag (\(Int(from.x)),\(Int(from.y))) → (\(Int(to.x)),\(Int(to.y)))"
        Task {
            do {
                try await input.swipe(on: device.id, from: from, to: to, durationMs: 50)
            } catch {
                statusLabel?.stringValue = "Drag failed: \((error as? OpenSimError)?.message ?? String(describing: error))"
            }
        }
    }

    private func sendTap(at point: Point) {
        guard let bridge, let device else { return }
        guard let input = bridge.input else {
            statusLabel?.stringValue = "tap → (\(Int(point.x)), \(Int(point.y))) · helper off"
            return
        }
        statusLabel?.stringValue = "tap → (\(Int(point.x)), \(Int(point.y)))"
        Task {
            do {
                try await input.tap(on: device.id, at: point, settle: false)
                statusLabel?.stringValue = "tap sent → (\(Int(point.x)), \(Int(point.y)))"
            } catch {
                statusLabel?.stringValue = "Tap failed: \((error as? OpenSimError)?.message ?? String(describing: error))"
            }
        }
    }

    private func performSelfClick() {
        guard let screenView, let window else { return }
        let devicePoint = Point(x: 210, y: 307)
        guard let viewPoint = screenView.viewPoint(fromSimulatorPoint: devicePoint) else { return }
        let windowPoint = screenView.convert(viewPoint, to: nil)
        let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
        let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
        if let down { NSApp.sendEvent(down) }
        if let up { NSApp.sendEvent(up) }
    }

    @objc private func homePressed() {
        guard let bridge, let device else { return }
        guard let input = bridge.input else {
            statusLabel?.stringValue = "Input helper is not configured (set OPENSIM_XCUITEST_BUNDLE_ID)"
            return
        }
        Task {
            do {
                try await input.button(on: device.id, button: .home)
            } catch {
                statusLabel?.stringValue = "Home failed: \((error as? OpenSimError)?.message ?? String(describing: error))"
            }
        }
    }

    @objc private func reconnectPressed() {
        guard let screenView else { return }
        screenView.disconnect()
        Task {
            do {
                try await screenView.connect()
                statusLabel?.stringValue = "Reconnected"
            } catch {
                statusLabel?.stringValue = "Reconnect failed: \((error as? OpenSimError)?.message ?? String(describing: error))"
            }
        }
    }
}

let arguments = CommandLine.arguments
func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

let snapshotPath = value(after: "--snapshot")
let requestedDevice = value(after: "--device")
let autoClick = arguments.contains("--auto-click")
let snapshotDelay = value(after: "--snapshot-delay").flatMap(Double.init) ?? 2
let application = NSApplication.shared
application.setActivationPolicy(snapshotPath == nil ? .regular : .accessory)
let controller = PreviewController(
    snapshotPath: snapshotPath,
    requestedDevice: requestedDevice,
    autoClick: autoClick,
    snapshotDelay: snapshotDelay
)
application.delegate = controller
application.run()
