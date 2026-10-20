import Darwin
import Foundation
import OpenSimCore

public struct SimctlOutput: Sendable, Equatable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data

    public init(status: Int32, stdout: Data, stderr: Data) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol SimctlExecuting: Sendable {
    func run(_ command: SimctlCommand, timeout: Duration) async throws -> SimctlOutput
}

public struct ProcessSimctlExecutor: SimctlExecuting {
    public let xcrunPath: String

    public init(xcrunPath: String = "/usr/bin/xcrun") {
        self.xcrunPath = xcrunPath
    }

    public func run(_ command: SimctlCommand, timeout: Duration) async throws -> SimctlOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrunPath)
        process.arguments = ["simctl"] + command.arguments
        if !command.environment.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in command.environment {
                environment[key] = value
            }
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let stdoutTask = Task.detached { stdoutHandle.readDataToEndOfFile() }
        let stderrTask = Task.detached { stderrHandle.readDataToEndOfFile() }

        let deadline = ContinuousClock.now + timeout
        while process.isRunning {
            if ContinuousClock.now >= deadline {
                process.terminate()
                try await Task.sleep(for: .milliseconds(200))
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                let stdout = await stdoutTask.value
                let stderr = await stderrTask.value
                throw OpenSimError(
                    code: .simctlFailed,
                    message: "simctl timed out after \(timeout)",
                    details: [
                        "command": command.displayString,
                        "stdout": String(decoding: stdout, as: UTF8.self),
                        "stderr": String(decoding: stderr, as: UTF8.self),
                    ],
                    recovery: "Increase --timeout or check the simulator state",
                    retryable: true
                )
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        let stdout = await stdoutTask.value
        let stderr = await stderrTask.value
        return SimctlOutput(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
