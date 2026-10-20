import Darwin
import Foundation
import OpenSimCore

public protocol RecordingProcessHandle: Sendable {
    var processIdentifier: Int32 { get }
    func sendInterrupt() throws
    func waitForExit(timeout: Duration) async -> Bool
    func isRunning() -> Bool
}

public protocol RecordingProcessLaunching: Sendable {
    func launch(arguments: [String], path: String) async throws -> any RecordingProcessHandle
}

public final class ProcessRecordingHandle: RecordingProcessHandle, @unchecked Sendable {
    private let process: Process
    private let stderrPipe: Pipe

    init(process: Process, stderrPipe: Pipe) {
        self.process = process
        self.stderrPipe = stderrPipe
    }

    public var processIdentifier: Int32 { process.processIdentifier }

    public func sendInterrupt() throws {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGINT)
    }

    public func waitForExit(timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while process.isRunning {
            if ContinuousClock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        return true
    }

    public func isRunning() -> Bool { process.isRunning }
}

public struct ProcessRecordingLauncher: RecordingProcessLaunching {
    private let xcrunPath: String

    public init(xcrunPath: String = "/usr/bin/xcrun") {
        self.xcrunPath = xcrunPath
    }

    public func launch(arguments: [String], path: String) async throws -> any RecordingProcessHandle {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrunPath)
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            throw OpenSimError(
                code: .inputFailed,
                message: "Could not start simctl recordVideo: \(error.localizedDescription)",
                recovery: "Check that Xcode command line tools are installed"
            )
        }

        let waiter = RecordingStartWaiter()
        let started = await waiter.wait(handle: stderrPipe.fileHandleForReading, timeout: .seconds(15))
        guard started else {
            kill(process.processIdentifier, SIGINT)
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw OpenSimError(
                code: .inputFailed,
                message: "simctl recordVideo did not report 'Recording started'",
                details: ["path": path],
                recovery: "Check that the device is booted and retry",
                retryable: true
            )
        }
        return ProcessRecordingHandle(process: process, stderrPipe: stderrPipe)
    }
}

private final class RecordingStartWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var buffer = Data()
    private var finished = false

    func wait(handle: FileHandle, timeout: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            handle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let self else { return }
                if data.isEmpty {
                    self.finish(false)
                    handle.readabilityHandler = nil
                } else {
                    self.consume(data)
                }
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(false)
            }
        }
    }

    private func consume(_ data: Data) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        buffer.append(data)
        if String(decoding: buffer, as: UTF8.self).contains("Recording started") {
            finished = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: true)
        } else {
            lock.unlock()
        }
    }

    private func finish(_ value: Bool) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

public actor SimctlRecordingController {
    private let launcher: any RecordingProcessLaunching
    private let store: RecordingStateStore
    private let paths: OpenSimPaths
    private let now: @Sendable () -> Date
    private var handles: [RecordingID: any RecordingProcessHandle] = [:]
    private var activeDevices: [DeviceID: RecordingID] = [:]

    public init(
        launcher: any RecordingProcessLaunching,
        store: RecordingStateStore,
        paths: OpenSimPaths,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.launcher = launcher
        self.store = store
        self.paths = paths
        self.now = now
    }

    public func start(on device: DeviceID, to out: String?, codec: VideoCodec) async throws -> RecordingID {
        if let activeID = activeDevices[device] {
            if let handle = handles[activeID], handle.isRunning() {
                throw recordingBusy(device: device, id: activeID, path: nil)
            }
            activeDevices[device] = nil
            handles[activeID] = nil
        }
        if let active = try await store.active(for: device) {
            throw recordingBusy(device: device, id: active.id, path: active.path)
        }

        let path: String
        if let out {
            path = try PathPolicy.validateOutputPath(out, allowedExtensions: ["mov"])
        } else {
            try paths.ensureMediaDirectories()
            path = paths.recordingsDirectory
                .appendingPathComponent("\(UUID().uuidString).mov")
                .path
        }

        let id = RecordingID(UUID().uuidString)
        let command = SimctlArguments.ioRecordVideo(device, path: path, codec: codec)
        let handle = try await launcher.launch(
            arguments: ["simctl"] + command.arguments,
            path: path
        )
        let state = RecordingState(
            id: id,
            deviceID: device,
            path: path,
            pid: handle.processIdentifier,
            codec: codec,
            startedAt: now()
        )
        do {
            try await store.save(state)
        } catch {
            try? handle.sendInterrupt()
            throw error
        }
        handles[id] = handle
        activeDevices[device] = id
        return id
    }

    public func stop(_ id: RecordingID) async throws -> RecordingStopResult {
        guard let state = try await store.load(id) else {
            throw OpenSimError.invalidArgument("Unknown recording: \(id.rawValue)")
        }

        if let handle = handles[id] {
            try? handle.sendInterrupt()
            let exited = await handle.waitForExit(timeout: .seconds(10))
            guard exited else {
                throw stopTimeout(state)
            }
            handles[id] = nil
            activeDevices[state.deviceID] = nil
        } else {
            kill(state.pid, SIGINT)
            guard await waitForProcessExit(state.pid, timeout: .seconds(10)) else {
                throw stopTimeout(state)
            }
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: state.path))
            .flatMap { $0[.size] as? NSNumber }
            .map(\.intValue) ?? 0
        guard size > 0 else {
            handles[id] = nil
            activeDevices[state.deviceID] = nil
            try? await store.remove(id)
            throw OpenSimError(
                code: .inputFailed,
                message: "Recording produced no video data",
                details: ["recording": id.rawValue, "path": state.path],
                recovery: "Check that the device stayed booted during recording"
            )
        }

        try await store.remove(id)
        let durationMs = max(0, Int(now().timeIntervalSince(state.startedAt) * 1000))
        return RecordingStopResult(id: id, path: state.path, durationMs: durationMs)
    }

    public func info(_ id: RecordingID) async throws -> RecordingInfo {
        guard let state = try await store.load(id) else {
            throw OpenSimError.invalidArgument("Unknown recording: \(id.rawValue)")
        }
        return RecordingInfo(
            id: state.id,
            deviceID: state.deviceID,
            path: state.path,
            codec: state.codec,
            startedAt: state.startedAt
        )
    }

    private func recordingBusy(device: DeviceID, id: RecordingID, path: String?) -> OpenSimError {
        var details = ["udid": device.rawValue, "recording": id.rawValue]
        if let path {
            details["path"] = path
        }
        return OpenSimError(
            code: .deviceBusy,
            message: "A recording is already active for this device",
            details: details,
            recovery: "Stop recording \(id.rawValue) before starting another",
            retryable: false
        )
    }

    private func stopTimeout(_ state: RecordingState) -> OpenSimError {
        OpenSimError(
            code: .deviceBusy,
            message: "Recording did not stop within 10 seconds",
            details: ["recording": state.id.rawValue, "pid": "\(state.pid)"],
            recovery: "Retry the stop command or terminate the simctl process",
            retryable: true
        )
    }

    private func waitForProcessExit(_ pid: Int32, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while processExists(pid) {
            if ContinuousClock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    private func processExists(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        let result = kill(pid, 0)
        return result == 0 || errno == EPERM
    }
}
