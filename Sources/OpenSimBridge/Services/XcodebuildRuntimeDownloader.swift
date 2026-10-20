import Foundation
import OpenSimCore

public protocol RuntimeDownloading: Sendable {
    func download(platform: Platform, version: String) async throws
}

public struct XcodebuildRuntimeDownloader: RuntimeDownloading {
    public let xcodebuildPath: String

    public init(xcodebuildPath: String = "/usr/bin/xcodebuild") {
        self.xcodebuildPath = xcodebuildPath
    }

    public func download(platform: Platform, version: String) async throws {
        let platformName: String
        switch platform {
        case .iOS:
            platformName = "iOS"
        case .watchOS:
            platformName = "watchOS"
        case .tvOS:
            platformName = "tvOS"
        case .visionOS:
            platformName = "visionOS"
        default:
            throw OpenSimError(
                code: .invalidArgument,
                message: "Runtime download is not supported for \(platform.rawValue)",
                recovery: "Use `opensim runtime list` to see supported platforms"
            )
        }
        guard !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenSimError.invalidArgument("version must not be empty")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcodebuildPath)
        process.arguments = ["-downloadPlatform", platformName, "-buildVersion", version]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw OpenSimError(
                code: .runtimeVersionUnavailable,
                message: String(decoding: error, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                details: [
                    "platform": platformName,
                    "version": version,
                    "exitStatus": "\(process.terminationStatus)",
                    "stdout": String(decoding: output, as: UTF8.self),
                ],
                recovery: "Check `xcodebuild -downloadPlatform \(platformName) -buildVersion \(version)` manually"
            )
        }
    }
}
