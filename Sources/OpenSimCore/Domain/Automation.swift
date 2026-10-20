import Foundation

public struct UIActionResult: Codable, Sendable, Equatable {
    public var action: String
    public var point: Point?
    public var matchedElementID: String?
    public var matchedCount: Int
    public var settleMs: Int?
    public var screenshot: Screenshot?

    public init(
        action: String,
        point: Point? = nil,
        matchedElementID: String? = nil,
        matchedCount: Int = 0,
        settleMs: Int? = nil,
        screenshot: Screenshot? = nil
    ) {
        self.action = action
        self.point = point
        self.matchedElementID = matchedElementID
        self.matchedCount = matchedCount
        self.settleMs = settleMs
        self.screenshot = screenshot
    }
}

public struct UIWaitResult: Codable, Sendable, Equatable {
    public var matched: Bool
    public var idle: Bool
    public var waitedMs: Int
    public var element: UIElement?

    public init(matched: Bool, idle: Bool, waitedMs: Int, element: UIElement? = nil) {
        self.matched = matched
        self.idle = idle
        self.waitedMs = waitedMs
        self.element = element
    }
}

public struct UIActStepResult: Codable, Sendable, Equatable {
    public var index: Int
    public var type: String
    public var ok: Bool
    public var error: OpenSimError?
    public var action: UIActionResult?
    public var wait: UIWaitResult?
    public var screenshot: Screenshot?

    public init(
        index: Int,
        type: String,
        ok: Bool,
        error: OpenSimError? = nil,
        action: UIActionResult? = nil,
        wait: UIWaitResult? = nil,
        screenshot: Screenshot? = nil
    ) {
        self.index = index
        self.type = type
        self.ok = ok
        self.error = error
        self.action = action
        self.wait = wait
        self.screenshot = screenshot
    }
}

public struct UIActResult: Codable, Sendable, Equatable {
    public var steps: [UIActStepResult]
    public var stopped: Bool

    public init(steps: [UIActStepResult], stopped: Bool) {
        self.steps = steps
        self.stopped = stopped
    }
}

public struct RecordingStartResult: Codable, Sendable, Equatable {
    public var id: RecordingID

    public init(id: RecordingID) {
        self.id = id
    }
}

public struct RecordingInfo: Codable, Sendable, Equatable {
    public var id: RecordingID
    public var deviceID: DeviceID
    public var path: String
    public var codec: VideoCodec
    public var startedAt: Date

    public init(id: RecordingID, deviceID: DeviceID, path: String, codec: VideoCodec, startedAt: Date) {
        self.id = id
        self.deviceID = deviceID
        self.path = path
        self.codec = codec
        self.startedAt = startedAt
    }
}

public struct RecordingStopResult: Codable, Sendable, Equatable {
    public var id: RecordingID
    public var path: String
    public var durationMs: Int

    public init(id: RecordingID, path: String, durationMs: Int) {
        self.id = id
        self.path = path
        self.durationMs = durationMs
    }
}

public struct UIActStep: Codable, Sendable, Equatable {
    public var type: String
    public var x: Double? = nil
    public var y: Double? = nil
    public var from: Point? = nil
    public var to: Point? = nil
    public var center: Point? = nil
    public var at: Point? = nil
    public var scale: Double? = nil
    public var angle: Double? = nil
    public var deltaX: Double? = nil
    public var deltaY: Double? = nil
    public var durationMs: Int? = nil
    public var text: String? = nil
    public var key: String? = nil
    public var button: String? = nil
    public var modifiers: KeyModifiers? = nil
    public var on: ElementSelector? = nil
    public var selector: String? = nil
    public var ms: Int? = nil
    public var idleMs: Int? = nil
    public var timeoutMs: Int? = nil
    public var format: ScreenshotFormat? = nil
    public var quality: Int? = nil
    public var out: String? = nil
    public var settle: Bool? = nil

    public init(type: String) {
        self.type = type
    }

    public init(type: String, on: ElementSelector) {
        self.type = type
        self.on = on
    }
}
