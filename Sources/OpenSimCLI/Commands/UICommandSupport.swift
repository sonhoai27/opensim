import Foundation
import OpenSimCore

public enum UICommandSupport {
    public static func selectorJSON(_ text: String) throws -> String {
        let selector = try SelectorParser.parse(text)
        return String(decoding: try OpenSimJSON.encoder(pretty: false).encode(selector), as: UTF8.self)
    }

    public static func pointJSON(_ text: String, label: String) throws -> String {
        let point = try PointParser.parse(text, label: label)
        return String(decoding: try OpenSimJSON.encoder(pretty: false).encode(point), as: UTF8.self)
    }

    public static func modifiersJSON(_ modifiers: KeyModifiers) throws -> String {
        String(decoding: try OpenSimJSON.encoder(pretty: false).encode(modifiers), as: UTF8.self)
    }

    public static func actionTable(_ result: UIActionResult) -> Table {
        Table(
            headers: ["ACTION", "X", "Y", "MATCHED", "SETTLE_MS"],
            rows: [[
                result.action,
                result.point.map { String($0.x) } ?? "",
                result.point.map { String($0.y) } ?? "",
                String(result.matchedCount),
                String(result.settleMs ?? 0),
            ]]
        )
    }

    public static func screenTable(_ screens: [ScreenInfo]) -> Table {
        Table(
            headers: ["SCREEN", "WIDTH", "HEIGHT", "SCALE", "ROTATION", "CLASS"],
            rows: screens.map {
                [
                    String($0.id),
                    String($0.width),
                    String($0.height),
                    String($0.scale),
                    String($0.rotation),
                    String($0.displayClass),
                ]
            }
        )
    }

    public static func screenshotTable(_ screenshot: Screenshot) -> Table {
        Table(
            headers: ["PATH", "FORMAT", "WIDTH", "HEIGHT", "SCALE"],
            rows: [[
                screenshot.path ?? "",
                screenshot.format.rawValue,
                String(screenshot.width),
                String(screenshot.height),
                String(screenshot.scale),
            ]]
        )
    }

    public static func treeTable(_ tree: UITree) -> Table {
        var rows: [[String]] = []
        func visit(_ element: UIElement) {
            rows.append([
                element.id,
                element.role,
                element.label ?? "",
                element.identifier ?? "",
                String(element.frame.x),
                String(element.frame.y),
                String(element.frame.width),
                String(element.frame.height),
                element.enabled ? "yes" : "no",
            ])
            for child in element.children {
                visit(child)
            }
        }
        visit(tree.root)
        return Table(
            headers: ["ID", "ROLE", "LABEL", "IDENTIFIER", "X", "Y", "W", "H", "ENABLED"],
            rows: rows
        )
    }

    public static func elementTable(_ elements: [UIElement]) -> Table {
        Table(
            headers: ["ID", "ROLE", "LABEL", "IDENTIFIER", "X", "Y", "W", "H", "ENABLED"],
            rows: elements.map {
                [
                    $0.id,
                    $0.role,
                    $0.label ?? "",
                    $0.identifier ?? "",
                    String($0.frame.x),
                    String($0.frame.y),
                    String($0.frame.width),
                    String($0.frame.height),
                    $0.enabled ? "yes" : "no",
                ]
            }
        )
    }

    public static func waitTable(_ result: UIWaitResult) -> Table {
        Table(
            headers: ["MATCHED", "IDLE", "WAITED_MS", "ELEMENT"],
            rows: [[
                result.matched ? "yes" : "no",
                result.idle ? "yes" : "no",
                String(result.waitedMs),
                result.element?.id ?? "",
            ]]
        )
    }

    public static func actTable(_ result: UIActResult) -> Table {
        Table(
            headers: ["STEP", "TYPE", "OK", "DETAIL"],
            rows: result.steps.map { step in
                let detail = step.error?.message
                    ?? step.action.map { "\($0.action) matched=\($0.matchedCount)" }
                    ?? step.wait.map { "matched=\($0.matched) idle=\($0.idle)" }
                    ?? step.screenshot?.path
                    ?? ""
                return [String(step.index), step.type, step.ok ? "yes" : "no", detail]
            }
        )
    }

    public static func recordingStartTable(_ result: RecordingStartResult) -> Table {
        Table(headers: ["RECORDING_ID"], rows: [[result.id.rawValue]])
    }

    public static func recordingStopTable(_ result: RecordingStopResult) -> Table {
        Table(
            headers: ["RECORDING_ID", "PATH", "DURATION_MS"],
            rows: [[result.id.rawValue, result.path, String(result.durationMs)]]
        )
    }
}
