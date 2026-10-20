import Darwin
import Foundation
import OpenSimCore

public struct XCUITestHelperAction: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case tree
        case tapIdentifier
        case tapPoint
        case typeText
        case swipe
        case longPress
        case drag
        case pinch
        case rotate
        case scroll
        case key
        case button
    }

    public var kind: Kind
    public var identifier: String?
    public var point: Point?
    public var from: Point?
    public var to: Point?
    public var durationMs: Int?
    public var text: String?
    public var scale: Double?
    public var angle: Double?
    public var deltaX: Double?
    public var deltaY: Double?
    public var key: String?
    public var modifiers: KeyModifiers?
    public var button: HardwareButton?

    public init(
        kind: Kind,
        identifier: String? = nil,
        point: Point? = nil,
        from: Point? = nil,
        to: Point? = nil,
        durationMs: Int? = nil,
        text: String? = nil,
        scale: Double? = nil,
        angle: Double? = nil,
        deltaX: Double? = nil,
        deltaY: Double? = nil,
        key: String? = nil,
        modifiers: KeyModifiers? = nil,
        button: HardwareButton? = nil
    ) {
        self.kind = kind
        self.identifier = identifier
        self.point = point
        self.from = from
        self.to = to
        self.durationMs = durationMs
        self.text = text
        self.scale = scale
        self.angle = angle
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.key = key
        self.modifiers = modifiers
        self.button = button
    }

    public static let tree = XCUITestHelperAction(kind: .tree)
}

public struct XCUITestHelperResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var error: String?
    public var node: HelperNode?

    public init(ok: Bool, error: String?, node: HelperNode?) {
        self.ok = ok
        self.error = error
        self.node = node
    }
}

public struct XCUITestHelperRunner: Sendable {
    public static let resultMarker = "OPENSIM_HELPER_RESULT:"

    public let rootDirectory: URL
    public let cacheDirectory: URL
    public let xcodebuildPath: String

    public init(
        rootDirectory: URL = XCUITestHelperRunner.defaultRootDirectory,
        cacheDirectory: URL = XCUITestHelperRunner.defaultCacheDirectory,
        xcodebuildPath: String = "/usr/bin/xcodebuild"
    ) {
        self.rootDirectory = rootDirectory
        self.cacheDirectory = cacheDirectory
        self.xcodebuildPath = xcodebuildPath
    }

    public static var defaultRootDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["OPENSIM_FIXTURE_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Fixtures/OpenSimFixture", isDirectory: true)
    }

    public static var defaultCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenSim/xcuitest", isDirectory: true)
    }

    public static var isConfigured: Bool {
        let root = defaultRootDirectory
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("project.yml").path) else {
            return false
        }
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("OpenSimFixture.xcodeproj/project.pbxproj").path) {
            return true
        }
        return findExecutable("xcodegen") != nil
    }

    public func run(
        device: DeviceID,
        bundleID: String,
        action: XCUITestHelperAction
    ) async throws -> XCUITestHelperResponse {
        guard !bundleID.isEmpty else {
            throw OpenSimError.invalidArgument("A bundle identifier is required for the XCUITest helper")
        }
        let project = try await ensureProject()
        let xctestrun = try await preparedXCTestRun(project: project, device: device)
        let copy = xctestrun.deletingLastPathComponent()
            .appendingPathComponent("helper-\(UUID().uuidString).xctestrun")
        try FileManager.default.copyItem(at: xctestrun, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        try injectEnvironment(
            into: copy,
            environment: environment(bundleID: bundleID, action: action)
        )

        let result = try await HelperProcess.run(
            executable: xcodebuildPath,
            arguments: [
                "test-without-building",
                "-xctestrun", copy.path,
                "-destination", "id=\(device.rawValue)",
                "-only-testing:OpenSimFixtureUITests/OpenSimFixtureUITests/testHelper",
            ],
            timeout: 300
        )
        guard result.status == 0 else {
            throw OpenSimError(
                code: .inputFailed,
                message: "XCUITest helper exited with status \(result.status)",
                details: ["stderr": String(result.stderr.suffix(2_000))],
                recovery: "Run `xcodebuild test-without-building` against the fixture to inspect the failure"
            )
        }
        guard let response = parseResult(result.stdout + "\n" + result.stderr) else {
            throw OpenSimError(
                code: .inputFailed,
                message: "XCUITest helper did not emit a result",
                details: ["stdout": String(result.stdout.suffix(2_000))],
                recovery: "Check the fixture UI test logs in Xcode"
            )
        }
        return response
    }

    private func ensureProject() async throws -> URL {
        let project = rootDirectory.appendingPathComponent("OpenSimFixture.xcodeproj", isDirectory: true)
        if FileManager.default.fileExists(atPath: project.appendingPathComponent("project.pbxproj").path) {
            return project
        }
        guard let xcodegen = Self.findExecutable("xcodegen") else {
            throw OpenSimError(
                code: .capabilityUnavailable,
                message: "xcodegen is required to build the XCUITest helper",
                details: ["fixture": rootDirectory.path],
                recovery: "Install xcodegen with `brew install xcodegen` and retry"
            )
        }
        let result = try await HelperProcess.run(
            executable: xcodegen,
            arguments: ["generate", "--spec", "project.yml", "--project", "."],
            workingDirectory: rootDirectory,
            timeout: 120
        )
        guard result.status == 0,
              FileManager.default.fileExists(atPath: project.appendingPathComponent("project.pbxproj").path) else {
            throw OpenSimError(
                code: .capabilityUnavailable,
                message: "Could not generate the fixture Xcode project",
                details: ["stderr": String(result.stderr.suffix(2_000))],
                recovery: "Run xcodegen manually in Fixtures/OpenSimFixture"
            )
        }
        return project
    }

    private func preparedXCTestRun(project: URL, device: DeviceID) async throws -> URL {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let stampFile = cacheDirectory.appendingPathComponent("fixture.stamp")
        let latestSource = latestModification(in: rootDirectory)
        if let stamp = try? String(contentsOf: stampFile, encoding: .utf8),
           let stampValue = Double(stamp.trimmingCharacters(in: .whitespacesAndNewlines)),
           stampValue >= latestSource,
           let cached = xctestrunFiles().first {
            return cached
        }

        let result = try await HelperProcess.run(
            executable: xcodebuildPath,
            arguments: [
                "build-for-testing",
                "-project", project.path,
                "-scheme", "OpenSimFixture",
                "-configuration", "Debug",
                "-sdk", "iphonesimulator",
                "-destination", "id=\(device.rawValue)",
                "-derivedDataPath", cacheDirectory.path,
                "CODE_SIGNING_ALLOWED=NO",
            ],
            timeout: 600
        )
        guard result.status == 0 else {
            throw OpenSimError(
                code: .inputFailed,
                message: "Could not build the XCUITest helper",
                details: ["stderr": String(result.stderr.suffix(2_000))],
                recovery: "Build Fixtures/OpenSimFixture manually and retry"
            )
        }
        guard let xctestrun = xctestrunFiles().first else {
            throw OpenSimError(
                code: .inputFailed,
                message: "xcodebuild produced no .xctestrun file",
                details: ["cache": cacheDirectory.path]
            )
        }
        try String(latestSource).write(to: stampFile, atomically: true, encoding: .utf8)
        return xctestrun
    }

    private func xctestrunFiles() -> [URL] {
        let products = cacheDirectory.appendingPathComponent("Build/Products", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: products,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "xctestrun" }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
    }

    private func latestModification(in directory: URL) -> Double {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var latest: Double = 0
        for case let url as URL in enumerator {
            if url.path.contains(".xcodeproj") || url.path.contains("/build/") {
                continue
            }
            let date = (try? url.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            latest = max(latest, date.timeIntervalSince1970)
        }
        return latest
    }

    private func injectEnvironment(into url: URL, environment: [String: String]) throws {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw OpenSimError(code: .inputFailed, message: "Invalid xctestrun file")
        }
        let updated = inject(plist, environment: environment) as? [String: Any] ?? plist
        let output = try PropertyListSerialization.data(fromPropertyList: updated, format: .xml, options: 0)
        try output.write(to: url, options: .atomic)
    }

    private func inject(_ value: Any, environment: [String: String]) -> Any {
        if var dictionary = value as? [String: Any] {
            if dictionary["TestBundlePath"] != nil {
                var merged = dictionary["EnvironmentVariables"] as? [String: String] ?? [:]
                for (key, value) in environment {
                    merged[key] = value
                }
                dictionary["EnvironmentVariables"] = merged
            }
            for (key, value) in dictionary {
                dictionary[key] = inject(value, environment: environment)
            }
            return dictionary
        }
        if let array = value as? [Any] {
            return array.map { inject($0, environment: environment) }
        }
        return value
    }

    private func environment(bundleID: String, action: XCUITestHelperAction) -> [String: String] {
        var environment = [
            "OPENSIM_HELPER_ACTION": action.kind.rawValue,
            "OPENSIM_HELPER_BUNDLE_ID": bundleID,
        ]
        if let identifier = action.identifier {
            environment["OPENSIM_HELPER_IDENTIFIER"] = identifier
        }
        if let point = action.point {
            environment["OPENSIM_HELPER_X"] = "\(point.x)"
            environment["OPENSIM_HELPER_Y"] = "\(point.y)"
        }
        if let from = action.from {
            environment["OPENSIM_HELPER_FROMX"] = "\(from.x)"
            environment["OPENSIM_HELPER_FROMY"] = "\(from.y)"
        }
        if let to = action.to {
            environment["OPENSIM_HELPER_TOX"] = "\(to.x)"
            environment["OPENSIM_HELPER_TOY"] = "\(to.y)"
        }
        if let durationMs = action.durationMs {
            environment["OPENSIM_HELPER_DURATION_MS"] = "\(durationMs)"
        }
        if let text = action.text {
            environment["OPENSIM_HELPER_TEXT"] = text
        }
        if let scale = action.scale {
            environment["OPENSIM_HELPER_SCALE"] = "\(scale)"
        }
        if let angle = action.angle {
            environment["OPENSIM_HELPER_ANGLE"] = "\(angle)"
        }
        if let deltaX = action.deltaX {
            environment["OPENSIM_HELPER_DX"] = "\(deltaX)"
        }
        if let deltaY = action.deltaY {
            environment["OPENSIM_HELPER_DY"] = "\(deltaY)"
        }
        if let key = action.key {
            environment["OPENSIM_HELPER_KEY"] = key
        }
        if let modifiers = action.modifiers {
            environment["OPENSIM_HELPER_MODIFIER_COMMAND"] = modifiers.command ? "1" : "0"
            environment["OPENSIM_HELPER_MODIFIER_SHIFT"] = modifiers.shift ? "1" : "0"
            environment["OPENSIM_HELPER_MODIFIER_OPTION"] = modifiers.option ? "1" : "0"
            environment["OPENSIM_HELPER_MODIFIER_CONTROL"] = modifiers.control ? "1" : "0"
        }
        if let button = action.button {
            environment["OPENSIM_HELPER_BUTTON"] = button.rawValue
        }
        return environment
    }

    private func parseResult(_ output: String) -> XCUITestHelperResponse? {
        let lines = output.split(separator: "\n").reversed()
        for line in lines {
            guard let range = line.range(of: Self.resultMarker) else { continue }
            let encoded = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = Data(base64Encoded: String(encoded)) else { continue }
            if let response = try? JSONDecoder().decode(XCUITestHelperResponse.self, from: data) {
                return response
            }
        }
        return nil
    }

    private static func findExecutable(_ name: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

private struct HelperProcessResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

private enum HelperProcess {
    static func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        timeout: TimeInterval
    ) async throws -> HelperProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let workingDirectory {
                process.currentDirectoryURL = workingDirectory
            }
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            try process.run()

            let stdoutTask = Task.detached { stdoutPipe.fileHandleForReading.readDataToEndOfFile() }
            let stderrTask = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                if Date() >= deadline {
                    process.terminate()
                    usleep(200_000)
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                    _ = await stdoutTask.value
                    _ = await stderrTask.value
                    throw OpenSimError(
                        code: .inputFailed,
                        message: "XCUITest helper command timed out",
                        details: ["executable": executable],
                        recovery: "Retry with a booted simulator and a built fixture",
                        retryable: true
                    )
                }
                usleep(50_000)
            }
            let stdout = await stdoutTask.value
            let stderr = await stderrTask.value
            return HelperProcessResult(
                status: process.terminationStatus,
                stdout: String(decoding: stdout, as: UTF8.self),
                stderr: String(decoding: stderr, as: UTF8.self)
            )
        }.value
    }
}
