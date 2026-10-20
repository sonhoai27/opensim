import CoreGraphics
import Foundation
import OpenSimCore

public actor DTUHIDInputService: InputControlling {
    private let screens: any ScreenControlling
    private var connections: [DeviceID: DTUHIDConnection] = [:]
    private var screenPoints: [DeviceID: CGSize] = [:]

    public init(screens: any ScreenControlling) {
        self.screens = screens
    }

    public func tap(on device: DeviceID, at point: Point, settle: Bool) async throws {
        let size = try await size(for: device)
        let connection = try connection(for: device)
        let normalized = normalize(point, in: size)
        try connection.sendDigitizer(first: normalized, eventType: 0)
        try await Task.sleep(for: .milliseconds(20))
        try connection.sendDigitizer(first: normalized, eventType: 2)
        try await Task.sleep(for: .milliseconds(10))
    }

    public func swipe(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {
        try await drag(on: device, from: from, to: to, durationMs: durationMs)
    }

    public func longPress(on device: DeviceID, at point: Point, durationMs: Int) async throws {
        let size = try await size(for: device)
        let connection = try connection(for: device)
        let normalized = normalize(point, in: size)
        try connection.sendDigitizer(first: normalized, eventType: 0)
        try await Task.sleep(for: .milliseconds(30))
        let steps = max(1, durationMs / 80)
        for _ in 0..<steps {
            try await Task.sleep(for: .milliseconds(80))
            try connection.sendDigitizer(first: normalized, eventType: 1)
        }
        try connection.sendDigitizer(first: normalized, eventType: 2)
        try await Task.sleep(for: .milliseconds(10))
    }

    public func drag(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {
        let size = try await size(for: device)
        let connection = try connection(for: device)
        let steps = max(4, min(40, max(durationMs, 16) / 16))
        let delay = max(4, durationMs / steps)
        try connection.sendDigitizer(first: normalize(from, in: size), eventType: 0)
        try await Task.sleep(for: .milliseconds(30))
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            let point = Point(
                x: from.x + (to.x - from.x) * progress,
                y: from.y + (to.y - from.y) * progress
            )
            try await Task.sleep(for: .milliseconds(delay))
            try connection.sendDigitizer(first: normalize(point, in: size), eventType: 1)
        }
        try connection.sendDigitizer(first: normalize(to, in: size), eventType: 2)
        try await Task.sleep(for: .milliseconds(10))
    }

    public func pinch(on device: DeviceID, center: Point, scale: Double, durationMs: Int) async throws {
        try await twoFingerGesture(
            on: device,
            center: center,
            initial: 60,
            final: 60 * max(0.1, scale),
            angleDelta: 0,
            durationMs: durationMs
        )
    }

    public func rotate(on device: DeviceID, center: Point, angle: Double, durationMs: Int) async throws {
        try await twoFingerGesture(
            on: device,
            center: center,
            initial: 150,
            final: 150,
            angleDelta: angle,
            durationMs: durationMs
        )
    }

    public func scroll(on device: DeviceID, deltaX: Double, deltaY: Double, at point: Point?) async throws {
        let size = try await size(for: device)
        let center = point ?? Point(x: size.width / 2, y: size.height / 2)
        let from = Point(x: center.x + deltaX / 2, y: center.y + deltaY / 2)
        let to = Point(x: center.x - deltaX / 2, y: center.y - deltaY / 2)
        try await drag(on: device, from: from, to: to, durationMs: 160)
    }

    public func typeText(on device: DeviceID, text: String) async throws {
        let connection = try connection(for: device)
        for character in text {
            guard let entry = DTUHIDKeyboardMap.characters[character] else {
                throw OpenSimError.invalidArgument(
                    "The dtuhidd keyboard map does not support '\(character)'",
                    details: ["character": String(character)]
                )
            }
            if entry.shift {
                try connection.sendKeyboard(usage: DTUHIDKeyboardMap.leftShift, state: 1)
            }
            try connection.sendKeyboard(usage: entry.usage, state: 1)
            try connection.sendKeyboard(usage: entry.usage, state: 2)
            if entry.shift {
                try connection.sendKeyboard(usage: DTUHIDKeyboardMap.leftShift, state: 2)
            }
            try await Task.sleep(for: .milliseconds(4))
        }
        try await Task.sleep(for: .milliseconds(20))
    }

    public func key(on device: DeviceID, key: Key, modifiers: KeyModifiers) async throws {
        guard let usage = DTUHIDKeyboardMap.keys[key.name.lowercased()] else {
            throw OpenSimError.invalidArgument("Unknown keyboard key: \(key.name)")
        }
        let connection = try connection(for: device)
        let active = DTUHIDKeyboardMap.modifierUsages(for: modifiers)
        for modifier in active {
            try connection.sendKeyboard(usage: modifier, state: 1)
        }
        try connection.sendKeyboard(usage: usage, state: 1)
        try connection.sendKeyboard(usage: usage, state: 2)
        for modifier in active.reversed() {
            try connection.sendKeyboard(usage: modifier, state: 2)
        }
        try await Task.sleep(for: .milliseconds(10))
    }

    public func button(on device: DeviceID, button: HardwareButton) async throws {
        guard let usage = DTUHIDKeyboardMap.buttons[button] else {
            throw OpenSimError.capabilityUnavailable("hardware_button_\(button.rawValue)")
        }
        let connection = try connection(for: device)
        try connection.sendButton(page: usage.page, code: usage.code, state: 1)
        try await Task.sleep(for: .milliseconds(60))
        try connection.sendButton(page: usage.page, code: usage.code, state: 2)
        try await Task.sleep(for: .milliseconds(60))
    }

    private func twoFingerGesture(
        on device: DeviceID,
        center: Point,
        initial: Double,
        final: Double,
        angleDelta: Double,
        durationMs: Int
    ) async throws {
        let size = try await size(for: device)
        let connection = try connection(for: device)
        let steps = max(6, min(40, max(durationMs, 60) / 16))
        let delay = max(4, durationMs / steps)
        let startAngle = -Double.pi / 2
        let endAngle = startAngle + angleDelta * Double.pi / 180

        func fingers(distance: Double, angle: Double) -> (Point, Point) {
            let offsetX = cos(angle) * distance / 2
            let offsetY = sin(angle) * distance / 2
            return (
                Point(x: center.x + offsetX, y: center.y + offsetY),
                Point(x: center.x - offsetX, y: center.y - offsetY)
            )
        }

        let start = fingers(distance: initial, angle: startAngle)
        try connection.sendDigitizer(
            first: normalize(start.0, in: size),
            second: normalize(start.1, in: size),
            eventType: 0
        )
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            let distance = initial + (final - initial) * progress
            let angle = startAngle + (endAngle - startAngle) * progress
            let points = fingers(distance: distance, angle: angle)
            try await Task.sleep(for: .milliseconds(delay))
            try connection.sendDigitizer(
                first: normalize(points.0, in: size),
                second: normalize(points.1, in: size),
                eventType: 1
            )
        }
        let end = fingers(distance: final, angle: endAngle)
        try connection.sendDigitizer(
            first: normalize(end.0, in: size),
            second: normalize(end.1, in: size),
            eventType: 2
        )
        try await Task.sleep(for: .milliseconds(10))
    }

    private func size(for device: DeviceID) async throws -> CGSize {
        if let cached = screenPoints[device] {
            return cached
        }
        let screens = try await screens.screens(for: device)
        guard let main = screens.first(where: { $0.displayClass == 0 }) ?? screens.first else {
            throw OpenSimError(
                code: .capabilityUnavailable,
                message: "Device has no main display",
                details: ["udid": device.rawValue]
            )
        }
        let scale = max(1, main.scale)
        let size = CGSize(width: Double(main.width) / scale, height: Double(main.height) / scale)
        screenPoints[device] = size
        return size
    }

    private func connection(for device: DeviceID) throws -> DTUHIDConnection {
        if let connection = connections[device], !connection.isInvalidated {
            return connection
        }
        let deviceObject = try CoreSimulatorDeviceLookup.device(device)
        let connection = try DTUHIDConnection(deviceObject: deviceObject, deviceID: device)
        connections[device] = connection
        return connection
    }

    private func normalize(_ point: Point, in size: CGSize) -> CGPoint {
        let x = min(max(point.x / max(1, size.width), 0), 1)
        let y = min(max(point.y / max(1, size.height), 0), 1)
        return CGPoint(x: x, y: y)
    }
}

enum DTUHIDKeyboardMap {
    static let leftShift: UInt64 = 0xE1

    static let characters: [Character: (usage: UInt64, shift: Bool)] = {
        var map: [Character: (usage: UInt64, shift: Bool)] = [:]
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        for (index, letter) in letters.enumerated() {
            let usage = UInt64(0x04 + index)
            map[letter] = (usage, false)
            map[Character(String(letter).uppercased())] = (usage, true)
        }
        let digits = Array("1234567890")
        for (index, digit) in digits.enumerated() {
            map[digit] = (UInt64(0x1E + index), false)
        }
        let shiftedDigits: [(Character, UInt64)] = [
            ("!", 0x1E), ("@", 0x1F), ("#", 0x20), ("$", 0x21), ("%", 0x22),
            ("^", 0x23), ("&", 0x24), ("*", 0x25), ("(", 0x26), (")", 0x27),
        ]
        for (character, usage) in shiftedDigits {
            map[character] = (usage, true)
        }
        let punctuation: [(Character, Character, UInt64)] = [
            ("-", "_", 0x2D), ("=", "+", 0x2E), ("[", "{", 0x2F), ("]", "}", 0x30),
            ("\\", "|", 0x31), (";", ":", 0x33), ("'", "\"", 0x34), ("`", "~", 0x35),
            (",", "<", 0x36), (".", ">", 0x37), ("/", "?", 0x38),
        ]
        for (plain, shifted, usage) in punctuation {
            map[plain] = (usage, false)
            map[shifted] = (usage, true)
        }
        map[" "] = (0x2C, false)
        map["\n"] = (0x28, false)
        map["\t"] = (0x2B, false)
        return map
    }()

    static let keys: [String: UInt64] = [
        "a": 0x04, "b": 0x05, "c": 0x06, "d": 0x07, "e": 0x08, "f": 0x09,
        "g": 0x0A, "h": 0x0B, "i": 0x0C, "j": 0x0D, "k": 0x0E, "l": 0x0F,
        "m": 0x10, "n": 0x11, "o": 0x12, "p": 0x13, "q": 0x14, "r": 0x15,
        "s": 0x16, "t": 0x17, "u": 0x18, "v": 0x19, "w": 0x1A, "x": 0x1B,
        "y": 0x1C, "z": 0x1D,
        "return": 0x28, "enter": 0x28, "escape": 0x29, "esc": 0x29,
        "delete": 0x2A, "backspace": 0x2A, "tab": 0x2B, "space": 0x2C,
        "left": 0x50, "right": 0x4F, "up": 0x52, "down": 0x51,
        "home": 0x4A, "end": 0x4D, "pageup": 0x4B, "pagedown": 0x4E,
        "deleteforward": 0x4C,
    ]

    static func modifierUsages(for modifiers: KeyModifiers) -> [UInt64] {
        var usages: [UInt64] = []
        if modifiers.control { usages.append(0xE0) }
        if modifiers.option { usages.append(0xE2) }
        if modifiers.shift { usages.append(0xE1) }
        if modifiers.command { usages.append(0xE3) }
        return usages
    }

    static let buttons: [HardwareButton: (page: UInt64, code: UInt64)] = [
        .home: (0x0C, 0x40),
        .lock: (0x0C, 0x30),
        .side: (0x0C, 0x30),
        .power: (0x0C, 0x30),
        .volumeUp: (0x0C, 0xE9),
        .volumeDown: (0x0C, 0xEA),
    ]
}
