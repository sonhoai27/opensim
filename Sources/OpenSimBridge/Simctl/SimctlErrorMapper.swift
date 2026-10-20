import Foundation
import OpenSimCore

public enum SimctlErrorMapper {
    public static func requireSuccess(command: SimctlCommand, output: SimctlOutput) throws {
        guard output.status == 0 else {
            throw error(for: command, output: output)
        }
    }

    public static func error(for command: SimctlCommand, output: SimctlOutput) -> OpenSimError {
        let stderr = String(decoding: output.stderr, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = String(decoding: output.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = stderr.isEmpty ? "simctl exited with status \(output.status)" : stderr
        var details = [
            "command": command.displayString,
            "exitStatus": "\(output.status)",
        ]
        if !stdout.isEmpty {
            details["stdout"] = stdout
        }

        if message.localizedCaseInsensitiveContains("Invalid device") ||
            message.localizedCaseInsensitiveContains("No devices are booted") {
            return OpenSimError(
                code: .deviceNotFound,
                message: message,
                details: details,
                recovery: "Run `opensim device list` to find the device",
                retryable: false
            )
        }
        if message.localizedCaseInsensitiveContains("current state: Booted") {
            return OpenSimError(
                code: .deviceBusy,
                message: message,
                details: details,
                recovery: "Shut down the device before this operation",
                retryable: false
            )
        }
        if message.localizedCaseInsensitiveContains("current state: Shutdown") ||
            message.localizedCaseInsensitiveContains("found nothing to terminate") {
            return OpenSimError(
                code: .deviceNotBooted,
                message: message,
                details: details,
                recovery: "Boot the device before this operation",
                retryable: false
            )
        }
        if message.localizedCaseInsensitiveContains("Unable to delete") {
            return OpenSimError(
                code: .deviceBusy,
                message: message,
                details: details,
                recovery: "Shut down the device before deleting it",
                retryable: false
            )
        }
        return OpenSimError(
            code: .simctlFailed,
            message: message,
            details: details,
            recovery: "Run `xcrun simctl help` and check the device state",
            retryable: false
        )
    }
}
