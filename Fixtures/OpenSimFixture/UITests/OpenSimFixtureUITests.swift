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
        guard let action = env["OPENSIM_HELPER_ACTION"],
              let bundleID = env["OPENSIM_HELPER_BUNDLE_ID"] else {
            return
        }
        let app = XCUIApplication(bundleIdentifier: bundleID)
        if app.state != .runningForeground {
            app.activate()
        }

        switch action {
        case "tree":
            emit(HelperResult(ok: true, error: nil, node: try snapshot(app)))
        case "tapIdentifier":
            let identifier = env["OPENSIM_HELPER_IDENTIFIER"] ?? ""
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            if element.waitForExistence(timeout: 5) {
                element.tap()
                emit(HelperResult(ok: true, error: nil, node: nil))
            } else {
                emit(HelperResult(ok: false, error: "element not found: \(identifier)", node: nil))
            }
        case "tapPoint":
            coordinate(app, pointFrom: env).tap()
            emit(HelperResult(ok: true, error: nil, node: nil))
        case "typeText":
            app.typeText(env["OPENSIM_HELPER_TEXT"] ?? "")
            emit(HelperResult(ok: true, error: nil, node: nil))
        case "swipe", "drag":
            let from = pointFrom(env, prefix: "FROM")
            let to = pointFrom(env, prefix: "TO")
            coordinate(app, x: from.x, y: from.y)
                .press(forDuration: seconds(env["OPENSIM_HELPER_DURATION_MS"]), thenDragTo: coordinate(app, x: to.x, y: to.y))
            emit(HelperResult(ok: true, error: nil, node: nil))
        case "longPress":
            let point = pointFrom(env)
            coordinate(app, x: point.x, y: point.y)
                .press(forDuration: seconds(env["OPENSIM_HELPER_DURATION_MS"]))
            emit(HelperResult(ok: true, error: nil, node: nil))
        case "pinch":
            let scale = Double(env["OPENSIM_HELPER_SCALE"] ?? "2") ?? 2
            app.pinch(withScale: CGFloat(scale), velocity: 1)
            emit(HelperResult(ok: true, error: nil, node: nil))
        case "rotate":
            let angle = Double(env["OPENSIM_HELPER_ANGLE"] ?? "90") ?? 90
            app.rotate(CGFloat(angle), withVelocity: 1)
            emit(HelperResult(ok: true, error: nil, node: nil))
        case "scroll":
            let point = pointFrom(env)
            let dx = Double(env["OPENSIM_HELPER_DX"] ?? "0") ?? 0
            let dy = Double(env["OPENSIM_HELPER_DY"] ?? "0") ?? 0
            let from = coordinate(app, x: point.x, y: point.y)
            let to = coordinate(app, x: point.x - dx, y: point.y - dy)
            from.press(forDuration: 0.05, thenDragTo: to)
            emit(HelperResult(ok: true, error: nil, node: nil))
        case "key":
            let name = env["OPENSIM_HELPER_KEY"] ?? ""
            let flags = keyModifiers(env)
            app.typeKey(XCUIKeyboardKey(rawValue: name), modifierFlags: flags)
            emit(HelperResult(ok: true, error: nil, node: nil))
        case "button":
            let button = env["OPENSIM_HELPER_BUTTON"] ?? ""
            guard button == "home" else {
                emit(HelperResult(ok: false, error: "unsupported button: \(button)", node: nil))
                return
            }
            XCUIDevice.shared.press(.home)
            emit(HelperResult(ok: true, error: nil, node: nil))
        default:
            emit(HelperResult(ok: false, error: "unknown action: \(action)", node: nil))
        }
    }

    private func coordinate(_ app: XCUIApplication, pointFrom env: [String: String], prefix: String = "") -> XCUICoordinate {
        let x = Double(env["OPENSIM_HELPER_\(prefix)X"] ?? env["OPENSIM_HELPER_X"] ?? "0") ?? 0
        let y = Double(env["OPENSIM_HELPER_\(prefix)Y"] ?? env["OPENSIM_HELPER_Y"] ?? "0") ?? 0
        return coordinate(app, x: x, y: y)
    }

    private func coordinate(_ app: XCUIApplication, x: Double, y: Double) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: x, dy: y))
    }

    private func pointFrom(_ env: [String: String], prefix: String = "") -> (x: Double, y: Double) {
        let x = Double(env["OPENSIM_HELPER_\(prefix)X"] ?? env["OPENSIM_HELPER_X"] ?? "0") ?? 0
        let y = Double(env["OPENSIM_HELPER_\(prefix)Y"] ?? env["OPENSIM_HELPER_Y"] ?? "0") ?? 0
        return (x, y)
    }

    private func seconds(_ text: String?) -> TimeInterval {
        (Double(text ?? "100") ?? 100) / 1000
    }

    private func keyModifiers(_ env: [String: String]) -> XCUIElement.KeyModifierFlags {
        var flags: XCUIElement.KeyModifierFlags = []
        if env["OPENSIM_HELPER_MODIFIER_COMMAND"] == "1" { flags.insert(.command) }
        if env["OPENSIM_HELPER_MODIFIER_SHIFT"] == "1" { flags.insert(.shift) }
        if env["OPENSIM_HELPER_MODIFIER_OPTION"] == "1" { flags.insert(.alternate) }
        if env["OPENSIM_HELPER_MODIFIER_CONTROL"] == "1" { flags.insert(.control) }
        return flags
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

    private func emit(_ result: HelperResult) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        print("OPENSIM_HELPER_RESULT:" + data.base64EncodedString())
    }
}

private struct HelperResult: Codable {
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
