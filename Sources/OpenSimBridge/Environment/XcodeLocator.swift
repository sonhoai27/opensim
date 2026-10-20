import Foundation
import OpenSimCore

public struct XcodeLocator: Sendable {
    public init() {}

    public func developerDir() throws -> String {
        let result = try run(executable: "/usr/bin/xcode-select", arguments: ["-p"], environment: [:])
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !path.isEmpty else {
            throw OpenSimError(
                code: .xcodeNotFound,
                message: "Full Xcode was not found",
                details: ["stderr": result.stderr],
                recovery: "Install Xcode 27.1 and run `sudo xcode-select -s /Applications/Xcode.app`"
            )
        }
        return try PathPolicy.validateDeveloperDir(path)
    }

    public func version(developerDir: String) throws -> XcodeInfo {
        let result = try run(
            executable: "/usr/bin/xcodebuild",
            arguments: ["-version"],
            environment: ["DEVELOPER_DIR": developerDir]
        )
        guard result.status == 0 else {
            throw OpenSimError(
                code: .xcodeNotFound,
                message: "xcodebuild could not read the Xcode version",
                details: ["stderr": result.stderr],
                recovery: "Run `sudo xcode-select -s /Applications/Xcode.app` and retry"
            )
        }
        let lines = result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var version = ""
        var build = ""
        for line in lines {
            if line.hasPrefix("Xcode ") {
                version = String(line.dropFirst("Xcode ".count))
            }
            if line.hasPrefix("Build version ") {
                build = String(line.dropFirst("Build version ".count))
            }
        }
        guard !version.isEmpty else {
            throw OpenSimError(
                code: .unsupportedXcode,
                message: "Could not parse Xcode version",
                details: ["stdout": result.stdout]
            )
        }
        guard let major = Int(version.split(separator: ".").first ?? ""), major >= 27 else {
            throw OpenSimError(
                code: .unsupportedXcode,
                message: "Xcode 27 or newer is required; found \(version)",
                details: ["version": version, "build": build],
                recovery: "Select Xcode 27.1 with xcode-select"
            )
        }
        return XcodeInfo(
            path: developerDir,
            version: version,
            build: build,
            isFullXcode: developerDir.contains(".app/Contents/Developer")
        )
    }

    private func run(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if !environment.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
        let stderrData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: stdoutData, as: UTF8.self),
            String(decoding: stderrData, as: UTF8.self)
        )
    }
}
