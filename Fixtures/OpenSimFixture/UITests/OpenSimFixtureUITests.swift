import Darwin
import XCTest

final class OpenSimFixtureUITests: XCTestCase {
    func testFixtureLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["fixture-primary-button"].exists)
    }

    func testHelper() throws {
        let env = ProcessInfo.processInfo.environment
        guard let request = HelperRequest(environment: env),
              let bundleID = env["OPENSIM_HELPER_BUNDLE_ID"] else {
            return
        }
        let app = XCUIApplication(bundleIdentifier: bundleID)
        if app.state != .runningForeground {
            app.activate()
        }
        emit(try perform(request, app: app))
    }

    func testHelperServer() throws {
        executionTimeAllowance = 3_600
        let env = ProcessInfo.processInfo.environment
        guard let portText = env["OPENSIM_HELPER_SERVER_PORT"],
              let port = UInt16(portText) else {
            return
        }
        let bundleID = env["OPENSIM_HELPER_BUNDLE_ID"] ?? "dev.opensim.fixture"
        let app = XCUIApplication(bundleIdentifier: bundleID)
        if app.state != .runningForeground {
            app.activate()
        }

        let fd = try connectToHost(port: port)
        defer { close(fd) }
        sendLine(fd, #"{"ready":true}"#)

        while true {
            guard let line = readLine(fd) else { return }
            let response: HelperResponse
            do {
                let request = try JSONDecoder().decode(HelperRequest.self, from: Data(line.utf8))
                if request.action == "quit" {
                    return
                }
                response = try perform(request, app: app)
            } catch {
                response = HelperResponse(ok: false, error: String(describing: error), node: nil)
            }
            guard let data = try? JSONEncoder().encode(response),
                  let text = String(data: data, encoding: .utf8) else {
                return
            }
            sendLine(fd, text)
        }
    }

    private func perform(_ request: HelperRequest, app: XCUIApplication) throws -> HelperResponse {
        switch request.action {
        case "tree":
            return HelperResponse(ok: true, error: nil, node: try snapshot(app))
        case "tapIdentifier":
            let identifier = request.identifier ?? ""
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            if element.waitForExistence(timeout: 5) {
                element.tap()
                return HelperResponse(ok: true, error: nil, node: nil)
            }
            return HelperResponse(ok: false, error: "element not found: \(identifier)", node: nil)
        case "tapPoint":
            coordinate(app, x: request.x ?? 0, y: request.y ?? 0).tap()
            return HelperResponse(ok: true, error: nil, node: nil)
        case "typeText":
            app.typeText(request.text ?? "")
            return HelperResponse(ok: true, error: nil, node: nil)
        case "swipe":
            let from = coordinate(app, x: request.fromX ?? 0, y: request.fromY ?? 0)
            let to = coordinate(app, x: request.toX ?? 0, y: request.toY ?? 0)
            from.press(forDuration: 0.01, thenDragTo: to, withVelocity: 1_000, thenHoldForDuration: 0)
            return HelperResponse(ok: true, error: nil, node: nil)
        case "drag":
            let from = coordinate(app, x: request.fromX ?? 0, y: request.fromY ?? 0)
            let to = coordinate(app, x: request.toX ?? 0, y: request.toY ?? 0)
            from.press(forDuration: seconds(request.durationMs), thenDragTo: to)
            return HelperResponse(ok: true, error: nil, node: nil)
        case "longPress":
            coordinate(app, x: request.x ?? 0, y: request.y ?? 0)
                .press(forDuration: seconds(request.durationMs))
            return HelperResponse(ok: true, error: nil, node: nil)
        case "pinch":
            app.pinch(withScale: CGFloat(request.scale ?? 2), velocity: 1)
            return HelperResponse(ok: true, error: nil, node: nil)
        case "rotate":
            app.rotate(CGFloat(request.angle ?? 90), withVelocity: 1)
            return HelperResponse(ok: true, error: nil, node: nil)
        case "scroll":
            let from = coordinate(app, x: request.x ?? 0, y: request.y ?? 0)
            let to = coordinate(
                app,
                x: (request.x ?? 0) - (request.dx ?? 0),
                y: (request.y ?? 0) - (request.dy ?? 0)
            )
            from.press(forDuration: 0.05, thenDragTo: to)
            return HelperResponse(ok: true, error: nil, node: nil)
        case "key":
            app.typeKey(
                XCUIKeyboardKey(rawValue: request.key ?? ""),
                modifierFlags: request.keyModifiers
            )
            return HelperResponse(ok: true, error: nil, node: nil)
        case "button":
            guard request.button == "home" else {
                return HelperResponse(ok: false, error: "unsupported button: \(request.button ?? "")", node: nil)
            }
            XCUIDevice.shared.press(.home)
            return HelperResponse(ok: true, error: nil, node: nil)
        default:
            return HelperResponse(ok: false, error: "unknown action: \(request.action)", node: nil)
        }
    }

    private func coordinate(_ app: XCUIApplication, x: Double, y: Double) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: x, dy: y))
    }

    private func seconds(_ milliseconds: Int?) -> TimeInterval {
        TimeInterval(milliseconds ?? 100) / 1_000
    }

    private func snapshot(_ app: XCUIApplication) throws -> HelperNode {
        node(from: try app.snapshot(), depth: 0)
    }

    private func node(from snapshot: XCUIElementSnapshot, depth: Int) -> HelperNode {
        HelperNode(
            role: role(snapshot.elementType),
            identifier: snapshot.identifier.isEmpty ? nil : snapshot.identifier,
            label: snapshot.label.isEmpty ? nil : snapshot.label,
            value: snapshot.value as? String,
            x: snapshot.frame.origin.x,
            y: snapshot.frame.origin.y,
            width: snapshot.frame.width,
            height: snapshot.frame.height,
            enabled: snapshot.isEnabled,
            selected: snapshot.isSelected,
            children: depth >= 30 ? [] : snapshot.children.map { node(from: $0, depth: depth + 1) }
        )
    }

    private func role(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: return "button"
        case .staticText: return "staticText"
        case .textField: return "textField"
        case .secureTextField: return "secureTextField"
        case .switch: return "switch"
        case .slider: return "slider"
        case .image: return "image"
        case .cell: return "cell"
        case .window: return "window"
        case .other: return "other"
        default: return "type\(type.rawValue)"
        }
    }

    private func emit(_ result: HelperResponse) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        print("OPENSIM_HELPER_RESULT:" + data.base64EncodedString())
    }

    private func connectToHost(port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw HelperSocketError("socket failed: \(errno)")
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            throw HelperSocketError("connect failed: \(errno)")
        }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    private func sendLine(_ fd: Int32, _ line: String) {
        let bytes = Array((line + "\n").utf8)
        var offset = 0
        while offset < bytes.count {
            let sent = bytes[offset...].withUnsafeBytes { buffer in
                send(fd, buffer.baseAddress, buffer.count, 0)
            }
            if sent <= 0 { return }
            offset += sent
        }
    }

    private func readLine(_ fd: Int32) -> String? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = recv(fd, &chunk, chunk.count, 0)
            if count > 0 {
                buffer.append(chunk, count: count)
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[..<newline]
                    return String(data: Data(line), encoding: .utf8)
                }
            } else if count == 0 {
                return nil
            } else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                return nil
            }
        }
    }
}

private struct HelperSocketError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct HelperRequest: Codable {
    var action: String
    var identifier: String?
    var x: Double?
    var y: Double?
    var fromX: Double?
    var fromY: Double?
    var toX: Double?
    var toY: Double?
    var durationMs: Int?
    var text: String?
    var scale: Double?
    var angle: Double?
    var dx: Double?
    var dy: Double?
    var key: String?
    var modifierCommand: Bool?
    var modifierShift: Bool?
    var modifierOption: Bool?
    var modifierControl: Bool?
    var button: String?

    init(action: String) {
        self.action = action
    }

    init?(environment: [String: String]) {
        guard let action = environment["OPENSIM_HELPER_ACTION"] else { return nil }
        self.action = action
        identifier = environment["OPENSIM_HELPER_IDENTIFIER"]
        x = Self.double(environment["OPENSIM_HELPER_X"])
        y = Self.double(environment["OPENSIM_HELPER_Y"])
        fromX = Self.double(environment["OPENSIM_HELPER_FROMX"])
        fromY = Self.double(environment["OPENSIM_HELPER_FROMY"])
        toX = Self.double(environment["OPENSIM_HELPER_TOX"])
        toY = Self.double(environment["OPENSIM_HELPER_TOY"])
        durationMs = Int(environment["OPENSIM_HELPER_DURATION_MS"] ?? "")
        text = environment["OPENSIM_HELPER_TEXT"]
        scale = Self.double(environment["OPENSIM_HELPER_SCALE"])
        angle = Self.double(environment["OPENSIM_HELPER_ANGLE"])
        dx = Self.double(environment["OPENSIM_HELPER_DX"])
        dy = Self.double(environment["OPENSIM_HELPER_DY"])
        key = environment["OPENSIM_HELPER_KEY"]
        modifierCommand = environment["OPENSIM_HELPER_MODIFIER_COMMAND"] == "1"
        modifierShift = environment["OPENSIM_HELPER_MODIFIER_SHIFT"] == "1"
        modifierOption = environment["OPENSIM_HELPER_MODIFIER_OPTION"] == "1"
        modifierControl = environment["OPENSIM_HELPER_MODIFIER_CONTROL"] == "1"
        button = environment["OPENSIM_HELPER_BUTTON"]
    }

    var keyModifiers: XCUIElement.KeyModifierFlags {
        var flags: XCUIElement.KeyModifierFlags = []
        if modifierCommand == true { flags.insert(.command) }
        if modifierShift == true { flags.insert(.shift) }
        if modifierOption == true { flags.insert(.alternate) }
        if modifierControl == true { flags.insert(.control) }
        return flags
    }

    private static func double(_ text: String?) -> Double? {
        guard let text else { return nil }
        return Double(text)
    }
}

private struct HelperResponse: Codable {
    let ok: Bool
    let error: String?
    let node: HelperNode?
}

private struct HelperNode: Codable {
    let role: String
    let identifier: String?
    let label: String?
    let value: String?
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let enabled: Bool
    let selected: Bool
    let children: [HelperNode]
}
