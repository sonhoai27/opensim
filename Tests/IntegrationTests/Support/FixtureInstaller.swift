import Foundation
import OpenSimBridge
import OpenSimCore

enum FixtureInstaller {
    static let bundleID = "dev.opensim.fixture"

    static func build() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Fixtures/OpenSimFixture", isDirectory: true)
        let script = root.appendingPathComponent("build.sh")
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            throw OpenSimError(
                code: .inputFailed,
                message: "Fixture build script is missing",
                details: ["path": script.path]
            )
        }
        let process = Process()
        process.executableURL = script
        process.currentDirectoryURL = root
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw OpenSimError(
                code: .inputFailed,
                message: "Fixture build failed with status \(process.terminationStatus)",
                details: ["stderr": String(decoding: err.suffix(2_000), as: UTF8.self)]
            )
        }
        let output = String(decoding: out, as: UTF8.self)
        guard let appPath = output
            .split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { $0.hasSuffix(".app") }) else {
            throw OpenSimError(
                code: .inputFailed,
                message: "Fixture build did not print the app path",
                details: ["stdout": String(output.suffix(2_000))]
            )
        }
        return URL(fileURLWithPath: appPath)
    }

    static func installAndLaunch(
        bridge: any AppControlling,
        device: DeviceID
    ) async throws -> String {
        let app = try build()
        _ = try await bridge.installApp(on: device, at: app.path)
        _ = try await bridge.launchApp(
            on: device,
            bundleID: bundleID,
            args: [],
            environment: [:]
        )
        return bundleID
    }
}
