import ArgumentParser
import Foundation
import OpenSimCore

public struct UICommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "ui",
        abstract: "Inspect and interact with the device screen",
        subcommands: [
            UIScreenshotCommand.self,
            UIRecordCommand.self,
            UIInfoCommand.self,
            UITapCommand.self,
            UISwipeCommand.self,
            UILongPressCommand.self,
            UIDragCommand.self,
            UIPinchCommand.self,
            UIRotateCommand.self,
            UIScrollCommand.self,
            UITypeCommand.self,
            UIKeyCommand.self,
            UIButtonCommand.self,
            UIWaitCommand.self,
            UITreeCommand.self,
            UIFindCommand.self,
            UIActCommand.self,
        ]
    )

    public init() {}
}

public struct UIScreenshotCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "screenshot", abstract: "Capture a screenshot")

    @OptionGroup public var globals: GlobalOptions
    @Option(name: .long, help: "Output path (defaults to the OpenSim screenshots directory)")
    public var out: String?
    @Option(name: .long, help: "Format: png or jpeg")
    public var format: String = "png"
    @Option(name: .long, help: "Scale between 0.1 and 4.0")
    public var scale: Double = 1.0
    @Option(name: .long, help: "JPEG quality between 1 and 100")
    public var quality: Int?

    public init() {}

    public func validate() throws {
        guard ScreenshotFormat(rawValue: format) != nil else {
            throw OpenSimError.invalidArgument("format must be png or jpeg")
        }
        guard scale >= 0.1 && scale <= 4.0 else {
            throw OpenSimError.invalidArgument("scale must be between 0.1 and 4.0")
        }
        if let quality, !(1..<101).contains(quality) {
            throw OpenSimError.invalidArgument("quality must be between 1 and 100")
        }
    }

    public func run() async throws {
        var values = globals.parameters(["format": format, "scale": String(scale)])
        if let out { values["out"] = out }
        if let quality { values["quality"] = String(quality) }
        let parameters = values
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.screenshotTable) { backend in
            try await backend.execute("screen_screenshot", parameters: parameters, as: Screenshot.self)
        }
    }
}

public struct UIRecordCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Record device video",
        subcommands: [UIRecordStartCommand.self, UIRecordStopCommand.self]
    )

    public init() {}
}

public struct UIRecordStartCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "start", abstract: "Start recording")

    @OptionGroup public var globals: GlobalOptions
    @Option(name: .long, help: "Output .mov path")
    public var out: String?
    @Option(name: .long, help: "Codec: h264 or hevc")
    public var codec: String = "h264"

    public init() {}

    public func validate() throws {
        guard VideoCodec(rawValue: codec) != nil else {
            throw OpenSimError.invalidArgument("codec must be h264 or hevc")
        }
    }

    public func run() async throws {
        var values = globals.parameters(["codec": codec])
        if let out { values["out"] = out }
        let parameters = values
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.recordingStartTable) { backend in
            try await backend.execute("screen_record_start", parameters: parameters, as: RecordingStartResult.self)
        }
    }
}

public struct UIRecordStopCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "stop", abstract: "Stop recording")

    @OptionGroup public var globals: GlobalOptions
    @Argument(help: "Recording identifier")
    public var recordingID: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["recordingID": recordingID])
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.recordingStopTable) { backend in
            try await backend.execute("screen_record_stop", parameters: parameters, as: RecordingStopResult.self)
        }
    }
}

public struct UIInfoCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "info", abstract: "List device screens")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters()
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.screenTable) { backend in
            try await backend.execute("screen_info", parameters: parameters, as: [ScreenInfo].self)
        }
    }
}

public struct UITapCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "tap", abstract: "Tap a point or matched element")

    @OptionGroup public var globals: GlobalOptions
    @Option(name: .long, help: "Element selector, e.g. id=fixture-primary-button")
    public var on: String?
    @Option(name: .long, help: "Horizontal point")
    public var x: Double?
    @Option(name: .long, help: "Vertical point")
    public var y: Double?
    @Flag(name: .long, help: "Wait for the screen to settle after tapping")
    public var settle: Bool = false

    public init() {}

    public func validate() throws {
        let hasSelector = !(on ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let hasPoint = x != nil || y != nil
        guard hasSelector != hasPoint else {
            throw OpenSimError.invalidArgument("Use either --on or --x/--y, not both")
        }
        if hasSelector, let on {
            _ = try SelectorParser.parse(on)
        } else {
            guard x != nil, y != nil else {
                throw OpenSimError.invalidArgument("Both --x and --y are required")
            }
        }
    }

    public func run() async throws {
        var values = globals.parameters(["settle": settle ? "true" : "false"])
        if let on {
            values["on"] = try UICommandSupport.selectorJSON(on)
        }
        if let x { values["x"] = String(x) }
        if let y { values["y"] = String(y) }
        let parameters = values
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.actionTable) { backend in
            try await backend.execute("ui_tap", parameters: parameters, as: UIActionResult.self)
        }
    }
}

public struct UISwipeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "swipe", abstract: "Swipe between two points")

    @OptionGroup public var globals: GlobalOptions
    @Option(name: .long, help: "Start point x,y")
    public var from: String
    @Option(name: .long, help: "End point x,y")
    public var to: String
    @Option(name: .long, help: "Duration in milliseconds")
    public var durationMs: Int = 300

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters([
            "from": try UICommandSupport.pointJSON(from, label: "from"),
            "to": try UICommandSupport.pointJSON(to, label: "to"),
            "durationMs": String(durationMs),
        ])
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.actionTable) { backend in
            try await backend.execute("ui_swipe", parameters: parameters, as: UIActionResult.self)
        }
    }
}

public struct UILongPressCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "long-press", abstract: "Long press a point")

    @OptionGroup public var globals: GlobalOptions
    @Option(name: .long) public var x: Double
    @Option(name: .long) public var y: Double
    @Option(name: .long, help: "Duration in milliseconds")
    public var durationMs: Int = 800

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters([
            "x": String(x),
            "y": String(y),
            "durationMs": String(durationMs),
        ])
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.actionTable) { backend in
            try await backend.execute("ui_long_press", parameters: parameters, as: UIActionResult.self)
        }
    }
}

public struct UIDragCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "drag", abstract: "Drag between two points")

    @OptionGroup public var globals: GlobalOptions
    @Option(name: .long, help: "Start point x,y")
    public var from: String
    @Option(name: .long, help: "End point x,y")
    public var to: String
    @Option(name: .long, help: "Duration in milliseconds")
    public var durationMs: Int = 300

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters([
            "from": try UICommandSupport.pointJSON(from, label: "from"),
            "to": try UICommandSupport.pointJSON(to, label: "to"),
            "durationMs": String(durationMs),
        ])
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.actionTable) { backend in
            try await backend.execute("ui_drag", parameters: parameters, as: UIActionResult.self)
        }
    }
}

public struct UIPinchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "pinch", abstract: "Pinch at a center point")

    @OptionGroup public var globals: GlobalOptions
    @Option(name: .long, help: "Center point x,y")
    public var center: String
    @Option(name: .long) public var scale: Double
    @Option(name: .long, help: "Duration in milliseconds")
    public var durationMs: Int = 300

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters([
            "center": try UICommandSupport.pointJSON(center, label: "center"),
            "scale": String(scale),
            "durationMs": String(durationMs),
        ])
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.actionTable) { backend in
            try await backend.execute("ui_pinch", parameters: parameters, as: UIActionResult.self)
        }
    }
}

public struct UIRotateCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "rotate", abstract: "Rotate at a center point")

    @OptionGroup public var globals: GlobalOptions
    @Option(name: .long, help: "Center point x,y")
    public var center: String
    @Option(name: .long) public var angle: Double
    @Option(name: .long, help: "Duration in milliseconds")
    public var durationMs: Int = 300

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters([
            "center": try UICommandSupport.pointJSON(center, label: "center"),
            "angle": String(angle),
            "durationMs": String(durationMs),
        ])
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.actionTable) { backend in
            try await backend.execute("ui_rotate", parameters: parameters, as: UIActionResult.self)
        }
    }
}

public struct UIScrollCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "scroll", abstract: "Scroll the screen")

    @OptionGroup public var globals: GlobalOptions
    @Option(name: .long) public var deltaX: Double
    @Option(name: .long) public var deltaY: Double
    @Option(name: .long, help: "Optional center point x,y")
    public var at: String?

    public init() {}

    public func run() async throws {
        var values = globals.parameters([
            "deltaX": String(deltaX),
            "deltaY": String(deltaY),
        ])
        if let at {
            values["at"] = try UICommandSupport.pointJSON(at, label: "at")
        }
        let parameters = values
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.actionTable) { backend in
            try await backend.execute("ui_scroll", parameters: parameters, as: UIActionResult.self)
        }
    }
}

public struct UITypeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "type", abstract: "Type text into the focused field")

    @OptionGroup public var globals: GlobalOptions
    @Argument(help: "Text to type")
    public var text: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["text": text])
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.actionTable) { backend in
            try await backend.execute("ui_type", parameters: parameters, as: UIActionResult.self)
        }
    }
}

public struct UIKeyCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "key", abstract: "Press a keyboard key")

    @OptionGroup public var globals: GlobalOptions
    @Argument(help: "Key name")
    public var name: String
    @Flag(name: .long) public var command: Bool = false
    @Flag(name: .long) public var shift: Bool = false
    @Flag(name: .long) public var option: Bool = false
    @Flag(name: .long) public var control: Bool = false

    public init() {}

    public func run() async throws {
        let modifiers = KeyModifiers(command: command, shift: shift, option: option, control: control)
        let parameters = globals.parameters([
            "key": name,
            "modifiers": try UICommandSupport.modifiersJSON(modifiers),
        ])
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.actionTable) { backend in
            try await backend.execute("ui_key", parameters: parameters, as: UIActionResult.self)
        }
    }
}

public struct UIButtonCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "button", abstract: "Press a hardware button")

    @OptionGroup public var globals: GlobalOptions
    @Argument(help: "Hardware button name")
    public var button: String

    public init() {}

    public func validate() throws {
        guard HardwareButton(rawValue: button) != nil else {
            throw OpenSimError.invalidArgument("Unknown hardware button: \(button)")
        }
    }

    public func run() async throws {
        let parameters = globals.parameters(["button": button])
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.actionTable) { backend in
            try await backend.execute("ui_button", parameters: parameters, as: UIActionResult.self)
        }
    }
}

public struct UIWaitCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "wait", abstract: "Wait for an element or an idle screen")

    @OptionGroup public var globals: GlobalOptions
    @Option(name: .long, help: "Element selector")
    public var on: String?
    @Option(name: .long, help: "Idle time in milliseconds")
    public var idleMs: Int = 250
    @Option(name: .long, help: "Timeout in milliseconds")
    public var timeoutMs: Int = 5_000

    public init() {}

    public func validate() throws {
        if let on {
            _ = try SelectorParser.parse(on)
        }
        guard idleMs >= 0, timeoutMs >= 0 else {
            throw OpenSimError.invalidArgument("idleMs and timeoutMs must be >= 0")
        }
    }

    public func run() async throws {
        var values = globals.parameters([
            "idleMs": String(idleMs),
            "timeoutMs": String(timeoutMs),
        ])
        if let on {
            values["selector"] = try UICommandSupport.selectorJSON(on)
        }
        let parameters = values
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.waitTable) { backend in
            try await backend.execute("ui_wait", parameters: parameters, as: UIWaitResult.self)
        }
    }
}

public struct UITreeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "tree", abstract: "Print the accessibility tree")

    @OptionGroup public var globals: GlobalOptions
    @Option(name: .long) public var maxDepth: Int = 30
    @Option(name: .long) public var maxNodes: Int = 1_500

    public init() {}

    public func validate() throws {
        guard maxDepth >= 0, maxNodes > 0 else {
            throw OpenSimError.invalidArgument("maxDepth must be >= 0 and maxNodes must be > 0")
        }
    }

    public func run() async throws {
        let parameters = globals.parameters([
            "maxDepth": String(maxDepth),
            "maxNodes": String(maxNodes),
        ])
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.treeTable) { backend in
            try await backend.execute("ui_tree", parameters: parameters, as: UITree.self)
        }
    }
}

public struct UIFindCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "find", abstract: "Find elements by selector")

    @OptionGroup public var globals: GlobalOptions
    @Argument(help: "Selector, e.g. id=fixture-primary-button")
    public var selector: String

    public init() {}

    public func validate() throws {
        _ = try SelectorParser.parse(selector)
    }

    public func run() async throws {
        let parameters = globals.parameters([
            "selector": try UICommandSupport.selectorJSON(selector),
        ])
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.elementTable) { backend in
            try await backend.execute("ui_find", parameters: parameters, as: [UIElement].self)
        }
    }
}

public struct UIActCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "act", abstract: "Run an automation step batch")

    @OptionGroup public var globals: GlobalOptions
    @Option(name: .long, help: "JSON array of UI act steps")
    public var steps: String?
    @Option(name: .long, help: "Path to a JSON steps file")
    public var stepsFile: String?
    @Flag(name: .long, inversion: .prefixedNo, help: "Stop on the first failing step")
    public var stopOnError: Bool = true

    public init() {}

    public static let allowedTypes: Set<String> = [
        "tap", "swipe", "long-press", "drag", "pinch", "rotate",
        "scroll", "type", "key", "button", "wait", "screenshot",
    ]

    public func validatedSteps() throws -> [UIActStep] {
        guard (steps == nil) != (stepsFile == nil) else {
            throw OpenSimError.invalidArgument("Use exactly one of --steps or --steps-file")
        }
        let text: String
        if let steps {
            text = steps
        } else if let stepsFile {
            let path = try PathPolicy.validateExistingFile(
                stepsFile,
                allowedExtensions: ["json"],
                requireDirectory: false
            )
            text = try String(contentsOfFile: path, encoding: .utf8)
        } else {
            throw OpenSimError.invalidArgument("Missing steps")
        }
        guard let data = text.data(using: .utf8) else {
            throw OpenSimError.invalidArgument("Steps must be UTF-8 JSON")
        }
        let decoded: [UIActStep]
        do {
            decoded = try OpenSimJSON.decoder().decode([UIActStep].self, from: data)
        } catch {
            throw OpenSimError.invalidArgument(
                "Steps must be a JSON array of UI act steps",
                details: ["error": String(describing: error)]
            )
        }
        guard !decoded.isEmpty else {
            throw OpenSimError.invalidArgument("Steps must not be empty")
        }
        for step in decoded where !Self.allowedTypes.contains(step.type) {
            throw OpenSimError.invalidArgument("Unknown step type: \(step.type)")
        }
        return decoded
    }

    public func run() async throws {
        let decoded = try validatedSteps()
        let data = try OpenSimJSON.encoder(pretty: false).encode(decoded)
        let parameters = globals.parameters([
            "steps": String(decoding: data, as: UTF8.self),
            "stopOnError": stopOnError ? "true" : "false",
        ])
        _ = try await CLIRuntime.run(globals: globals, table: UICommandSupport.actTable) { backend in
            try await backend.execute("ui_act", parameters: parameters, as: UIActResult.self)
        }
    }
}
