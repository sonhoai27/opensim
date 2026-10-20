import Foundation

public extension OperationCatalog {
    static func plan2() -> OperationCatalog {
        plan1().merging(OperationCatalog(operations: Plan2Operations.all))
    }
}

public enum Plan2Operations {
    private static func p(
        _ name: String,
        _ type: String,
        required: Bool = true,
        default value: String? = nil
    ) -> OperationParameter {
        OperationParameter(name: name, type: type, required: required, defaultValue: value)
    }

    private static let device = p("device", "string", required: false)
    private static let duration = p("durationMs", "integer", required: false, default: "300")

    private static let specs: [(path: [String], mcp: String, readOnly: Bool, lease: Bool, service: BridgeService?, params: [OperationParameter])] = [
        (["ui", "info"], "screen_info", true, false, .screen, [device]),
        (["ui", "screenshot"], "screen_screenshot", true, false, .screen, [device, p("format", "string", required: false, default: "png"), p("scale", "number", required: false, default: "1.0"), p("quality", "integer", required: false), p("out", "string", required: false)]),
        (["ui", "record", "start"], "screen_record_start", false, true, .screen, [device, p("out", "string", required: false), p("codec", "string", required: false, default: "h264")]),
        (["ui", "record", "stop"], "screen_record_stop", false, true, .screen, [p("recordingID", "string")]),
        (["ui", "tree"], "ui_tree", true, false, .accessibility, [device, p("maxDepth", "integer", required: false, default: "30"), p("maxNodes", "integer", required: false, default: "1500")]),
        (["ui", "find"], "ui_find", true, false, .accessibility, [device, p("selector", "selector")]),
        (["ui", "tap"], "ui_tap", false, true, .input, [device, p("x", "number", required: false), p("y", "number", required: false), p("on", "selector", required: false), p("settle", "boolean", required: false, default: "false")]),
        (["ui", "swipe"], "ui_swipe", false, true, .input, [device, p("from", "point"), p("to", "point"), duration]),
        (["ui", "long-press"], "ui_long_press", false, true, .input, [device, p("x", "number"), p("y", "number"), p("durationMs", "integer", required: false, default: "800")]),
        (["ui", "drag"], "ui_drag", false, true, .input, [device, p("from", "point"), p("to", "point"), duration]),
        (["ui", "pinch"], "ui_pinch", false, true, .input, [device, p("center", "point"), p("scale", "number"), duration]),
        (["ui", "rotate"], "ui_rotate", false, true, .input, [device, p("center", "point"), p("angle", "number"), duration]),
        (["ui", "scroll"], "ui_scroll", false, true, .input, [device, p("deltaX", "number"), p("deltaY", "number"), p("at", "point", required: false)]),
        (["ui", "type"], "ui_type", false, true, .input, [device, p("text", "string")]),
        (["ui", "key"], "ui_key", false, true, .input, [device, p("key", "string"), p("modifiers", "json", required: false)]),
        (["ui", "button"], "ui_button", false, true, .input, [device, p("button", "string")]),
        (["ui", "wait"], "ui_wait", true, false, .accessibility, [device, p("selector", "selector", required: false), p("idleMs", "integer", required: false, default: "250"), p("timeoutMs", "integer", required: false, default: "5000")]),
        (["ui", "act"], "ui_act", false, true, .input, [device, p("steps", "json"), p("stopOnError", "boolean", required: false, default: "true")]),
    ]

    public static var all: [Operation] {
        specs.map { spec in
            Operation(
                cliPath: spec.path,
                mcpName: spec.mcp,
                summary: spec.mcp.replacingOccurrences(of: "_", with: " "),
                requiresControlLease: spec.lease,
                destructive: false,
                readOnly: spec.readOnly,
                parameters: spec.params,
                requiredService: spec.service
            )
        }
    }
}
