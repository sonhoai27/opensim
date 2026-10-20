import Foundation
import OpenSimCore

public struct UIAutomationService: Sendable {
    private let screen: (any ScreenControlling)?
    private let input: (any InputControlling)?
    private let accessibility: (any AccessibilityReading)?

    public init(
        screen: (any ScreenControlling)?,
        input: (any InputControlling)?,
        accessibility: (any AccessibilityReading)?
    ) {
        self.screen = screen
        self.input = input
        self.accessibility = accessibility
    }

    public func find(on device: DeviceID, selector: ElementSelector) async throws -> [UIElement] {
        guard let accessibility else {
            throw OpenSimError.capabilityUnavailable("accessibility")
        }
        return try await accessibility.find(on: device, selector: selector)
    }

    public func tap(
        on device: DeviceID,
        selector: ElementSelector,
        settle: Bool
    ) async throws -> UIActionResult {
        guard let accessibility else {
            throw OpenSimError.capabilityUnavailable("accessibility")
        }
        guard let input else {
            throw OpenSimError.capabilityUnavailable("input")
        }
        let matches = try await accessibility.find(on: device, selector: selector)
        guard let element = matches.first(where: { $0.frame.width > 0 && $0.frame.height > 0 }) else {
            throw OpenSimError.invalidArgument(
                "Selector matched no element with a non-empty frame",
                details: ["matched": String(matches.count)]
            )
        }
        let point = Point(
            x: element.frame.x + element.frame.width / 2,
            y: element.frame.y + element.frame.height / 2
        )
        try await input.tap(on: device, at: point, settle: settle)
        let settleMs = settle
            ? try await waitForIdle(on: device, idleMs: 250, timeoutMs: 2_000)
            : 0
        return UIActionResult(
            action: "tap",
            point: point,
            matchedElementID: element.id,
            matchedCount: matches.count,
            settleMs: settleMs
        )
    }

    public func wait(
        on device: DeviceID,
        selector: ElementSelector?,
        idleMs: Int,
        timeoutMs: Int
    ) async throws -> UIWaitResult {
        let started = Date()
        if let selector {
            guard let accessibility else {
                throw OpenSimError.capabilityUnavailable("accessibility")
            }
            while elapsedMilliseconds(since: started) < timeoutMs {
                let matches = try await accessibility.find(on: device, selector: selector)
                if let match = matches.first {
                    return UIWaitResult(
                        matched: true,
                        idle: false,
                        waitedMs: elapsedMilliseconds(since: started),
                        element: match
                    )
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            return UIWaitResult(
                matched: false,
                idle: false,
                waitedMs: elapsedMilliseconds(since: started)
            )
        }

        guard screen != nil else {
            throw OpenSimError.capabilityUnavailable("screen")
        }
        var lastHash: Int?
        var stableSince = Date()
        while elapsedMilliseconds(since: started) < timeoutMs {
            let hash = try await screenshotHash(on: device)
            if hash != lastHash {
                lastHash = hash
                stableSince = Date()
            } else if elapsedMilliseconds(since: stableSince) >= idleMs {
                return UIWaitResult(
                    matched: true,
                    idle: true,
                    waitedMs: elapsedMilliseconds(since: started)
                )
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return UIWaitResult(
            matched: false,
            idle: false,
            waitedMs: elapsedMilliseconds(since: started)
        )
    }

    public func act(
        on device: DeviceID,
        steps: [UIActStep],
        stopOnError: Bool
    ) async throws -> UIActResult {
        var results: [UIActStepResult] = []
        var stopped = false
        for (index, step) in steps.enumerated() {
            do {
                let outcome = try await perform(step, on: device)
                results.append(
                    UIActStepResult(
                        index: index,
                        type: step.type,
                        ok: true,
                        action: outcome.action,
                        wait: outcome.wait,
                        screenshot: outcome.screenshot
                    )
                )
            } catch let error as OpenSimError {
                results.append(UIActStepResult(index: index, type: step.type, ok: false, error: error))
                if stopOnError {
                    stopped = true
                    break
                }
            } catch {
                let mapped = OpenSimError(code: .internalError, message: String(describing: error))
                results.append(UIActStepResult(index: index, type: step.type, ok: false, error: mapped))
                if stopOnError {
                    stopped = true
                    break
                }
            }
        }
        return UIActResult(steps: results, stopped: stopped)
    }

    private struct Outcome {
        var action: UIActionResult?
        var wait: UIWaitResult?
        var screenshot: Screenshot?
    }

    private func perform(_ step: UIActStep, on device: DeviceID) async throws -> Outcome {
        switch step.type {
        case "tap":
            if let selector = step.on {
                let result = try await tap(on: device, selector: selector, settle: step.settle ?? false)
                return Outcome(action: result)
            }
            let point = try point(step)
            let input = try requireInput()
            try await input.tap(on: device, at: point, settle: step.settle ?? false)
            return Outcome(action: UIActionResult(action: "tap", point: point, matchedCount: 0, settleMs: 0))

        case "swipe":
            guard let from = step.from, let to = step.to else {
                throw OpenSimError.invalidArgument("swipe requires from and to")
            }
            try await requireInput().swipe(on: device, from: from, to: to, durationMs: step.durationMs ?? 300)
            return Outcome(action: UIActionResult(action: "swipe", point: from, matchedCount: 0))

        case "long-press", "longPress":
            let point = try point(step)
            try await requireInput().longPress(on: device, at: point, durationMs: step.durationMs ?? 800)
            return Outcome(action: UIActionResult(action: "long-press", point: point, matchedCount: 0))

        case "drag":
            guard let from = step.from, let to = step.to else {
                throw OpenSimError.invalidArgument("drag requires from and to")
            }
            try await requireInput().drag(on: device, from: from, to: to, durationMs: step.durationMs ?? 300)
            return Outcome(action: UIActionResult(action: "drag", point: from, matchedCount: 0))

        case "pinch":
            guard let center = step.center, let scale = step.scale else {
                throw OpenSimError.invalidArgument("pinch requires center and scale")
            }
            try await requireInput().pinch(
                on: device,
                center: center,
                scale: scale,
                durationMs: step.durationMs ?? 300
            )
            return Outcome(action: UIActionResult(action: "pinch", point: center, matchedCount: 0))

        case "rotate":
            guard let center = step.center, let angle = step.angle else {
                throw OpenSimError.invalidArgument("rotate requires center and angle")
            }
            try await requireInput().rotate(
                on: device,
                center: center,
                angle: angle,
                durationMs: step.durationMs ?? 300
            )
            return Outcome(action: UIActionResult(action: "rotate", point: center, matchedCount: 0))

        case "scroll":
            try await requireInput().scroll(
                on: device,
                deltaX: step.deltaX ?? 0,
                deltaY: step.deltaY ?? 0,
                at: step.at
            )
            return Outcome(action: UIActionResult(action: "scroll", point: step.at, matchedCount: 0))

        case "type", "typeText":
            guard let text = step.text else {
                throw OpenSimError.invalidArgument("type requires text")
            }
            try await requireInput().typeText(on: device, text: text)
            return Outcome(action: UIActionResult(action: "type", matchedCount: 0))

        case "key":
            guard let key = step.key else {
                throw OpenSimError.invalidArgument("key requires a key name")
            }
            try await requireInput().key(
                on: device,
                key: Key(name: key),
                modifiers: step.modifiers ?? KeyModifiers()
            )
            return Outcome(action: UIActionResult(action: "key", matchedCount: 0))

        case "button":
            guard let raw = step.button, let button = HardwareButton(rawValue: raw) else {
                throw OpenSimError.invalidArgument("button requires a supported HardwareButton")
            }
            try await requireInput().button(on: device, button: button)
            return Outcome(action: UIActionResult(action: "button", matchedCount: 0))

        case "wait":
            if let ms = step.ms {
                try await Task.sleep(for: .milliseconds(ms))
                return Outcome(wait: UIWaitResult(matched: true, idle: true, waitedMs: ms))
            }
            let wait = try await wait(
                on: device,
                selector: step.on,
                idleMs: step.idleMs ?? 250,
                timeoutMs: step.timeoutMs ?? 5_000
            )
            return Outcome(wait: wait)

        case "screenshot":
            guard let screen else {
                throw OpenSimError.capabilityUnavailable("screen")
            }
            let format = step.format ?? .png
            let shot: Screenshot
            if let out = step.out, let writer = screen as? any ScreenshotOutWriting {
                shot = try await writer.screenshot(
                    on: device,
                    format: format,
                    scale: 1,
                    quality: step.quality,
                    out: out
                )
            } else {
                shot = try await screen.screenshot(
                    on: device,
                    format: format,
                    scale: 1,
                    quality: step.quality
                )
            }
            return Outcome(screenshot: shot)

        default:
            throw OpenSimError.invalidArgument("Unknown UI act step type: \(step.type)")
        }
    }

    private func requireInput() throws -> any InputControlling {
        guard let input else {
            throw OpenSimError.capabilityUnavailable("input")
        }
        return input
    }

    private func point(_ step: UIActStep) throws -> Point {
        if let at = step.at {
            return at
        }
        if let x = step.x, let y = step.y {
            return Point(x: x, y: y)
        }
        throw OpenSimError.invalidArgument("\(step.type) requires x and y or at")
    }

    private func waitForIdle(on device: DeviceID, idleMs: Int, timeoutMs: Int) async throws -> Int {
        guard screen != nil else {
            throw OpenSimError.capabilityUnavailable("screen")
        }
        var lastHash: Int?
        var stableSince = Date()
        let started = Date()
        while elapsedMilliseconds(since: started) < timeoutMs {
            let hash = try await screenshotHash(on: device)
            if hash != lastHash {
                lastHash = hash
                stableSince = Date()
            } else if elapsedMilliseconds(since: stableSince) >= idleMs {
                return elapsedMilliseconds(since: started)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return elapsedMilliseconds(since: started)
    }

    private func screenshotHash(on device: DeviceID) async throws -> Int {
        guard let screen else {
            throw OpenSimError.capabilityUnavailable("screen")
        }
        let screenshot = try await screen.screenshot(
            on: device,
            format: .png,
            scale: 0.25,
            quality: nil
        )
        let data: Data?
        if let inline = screenshot.data {
            data = inline
        } else if let path = screenshot.path {
            data = try? Data(contentsOf: URL(fileURLWithPath: path))
        } else {
            data = nil
        }
        guard let data else {
            throw OpenSimError(
                code: .inputFailed,
                message: "Screenshot polling could not read a frame",
                details: ["udid": device.rawValue]
            )
        }
        return data.hashValue
    }

    private func elapsedMilliseconds(since date: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(date) * 1_000))
    }
}
