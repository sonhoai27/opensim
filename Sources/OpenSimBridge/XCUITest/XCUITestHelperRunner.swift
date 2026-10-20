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

public actor XCUITestHelperRunner {
    public static let resultMarker = "OPENSIM_HELPER_RESULT:"

    public let rootDirectory: URL
    public let cacheDirectory: URL
    public let xcodebuildPath: String
    private var sessions: [SessionKey: PersistentHelperSession] = [:]

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
        let key = SessionKey(device: device, bundleID: bundleID)
        if let session = sessions[key] {
            do {
                return try session.send(action)
            } catch {
                sessions[key] = nil
                session.shutdown()
            }
        }

        let project = try await ensureProject()
        let xctestrun = try await preparedXCTestRun(project: project, device: device)
        let session = try PersistentHelperSession.start(
            xctestrun: xctestrun,
            device: device,
            bundleID: bundleID,
            xcodebuildPath: xcodebuildPath,
            cacheDirectory: cacheDirectory
        )
        sessions[key] = session
        do {
            return try session.send(action)
        } catch {
            sessions[key] = nil
            session.shutdown()
            throw error
        }
    }

    public func shutdown() {
        for session in sessions.values {
            session.shutdown()
        }
        sessions.removeAll()
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

private struct SessionKey: Hashable {
    let device: DeviceID
    let bundleID: String
}

private final class PersistentHelperSession {
    private let connection: HelperConnection
    private let process: Process
    private let logHandle: FileHandle
    private let logURL: URL

    private init(connection: HelperConnection, process: Process, logHandle: FileHandle, logURL: URL) {
        self.connection = connection
        self.process = process
        self.logHandle = logHandle
        self.logURL = logURL
    }

    deinit {
        shutdown()
    }

    static func start(
        xctestrun: URL,
        device: DeviceID,
        bundleID: String,
        xcodebuildPath: String,
        cacheDirectory: URL
    ) throws -> PersistentHelperSession {
        let listener = try HelperListener.open()
        defer { listener.close() }

        let copy = xctestrun.deletingLastPathComponent()
            .appendingPathComponent("server-\(UUID().uuidString).xctestrun")
        try FileManager.default.copyItem(at: xctestrun, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        try injectServerEnvironment(
            into: copy,
            port: listener.port,
            bundleID: bundleID
        )

        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let logURL = cacheDirectory.appendingPathComponent("server-\(device.rawValue).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let logHandle = try? FileHandle(forWritingTo: logURL) else {
            throw OpenSimError(
                code: .inputFailed,
                message: "Could not open the XCUITest helper log",
                details: ["path": logURL.path]
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcodebuildPath)
        process.arguments = [
            "test-without-building",
            "-xctestrun", copy.path,
            "-destination", "id=\(device.rawValue)",
            "-only-testing:OpenSimFixtureUITests/OpenSimFixtureUITests/testHelperServer",
        ]
        process.standardOutput = logHandle
        process.standardError = logHandle
        do {
            try process.run()
        } catch {
            try? logHandle.close()
            throw OpenSimError(
                code: .inputFailed,
                message: "Could not start the XCUITest helper server: \(error.localizedDescription)"
            )
        }

        let clientFD: Int32
        do {
            clientFD = try listener.accept(timeoutMs: 240_000)
        } catch {
            process.terminate()
            try? logHandle.close()
            throw helperError("XCUITest helper did not connect", logURL: logURL)
        }
        let connection = HelperConnection(fd: clientFD)
        do {
            let ready = try connection.readLine(timeoutMs: 60_000)
            guard ready.contains("\"ready\":true") else {
                throw OpenSimError(code: .inputFailed, message: "XCUITest helper sent an invalid handshake")
            }
        } catch {
            connection.close()
            process.terminate()
            try? logHandle.close()
            throw helperError("XCUITest helper handshake failed", logURL: logURL)
        }
        return PersistentHelperSession(
            connection: connection,
            process: process,
            logHandle: logHandle,
            logURL: logURL
        )
    }

    func send(_ action: XCUITestHelperAction) throws -> XCUITestHelperResponse {
        let payload = HelperRequestPayload(action: action)
        let data = try OpenSimJSON.encoder(pretty: false).encode(payload)
        guard let line = String(data: data, encoding: .utf8) else {
            throw OpenSimError(code: .internalError, message: "Could not encode the helper request")
        }
        try connection.sendLine(line)
        let responseLine = try connection.readLine(timeoutMs: 120_000)
        guard let responseData = responseLine.data(using: .utf8) else {
            throw OpenSimError(code: .inputFailed, message: "XCUITest helper returned invalid UTF-8")
        }
        do {
            return try JSONDecoder().decode(XCUITestHelperResponse.self, from: responseData)
        } catch {
            throw OpenSimError(
                code: .inputFailed,
                message: "XCUITest helper returned an invalid response",
                details: ["response": responseLine]
            )
        }
    }

    func shutdown() {
        if process.isRunning {
            try? connection.sendLine(#"{"action":"quit"}"#)
        }
        connection.close()
        for _ in 0..<100 where process.isRunning {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
        }
        try? logHandle.close()
    }

    private static func injectServerEnvironment(
        into url: URL,
        port: UInt16,
        bundleID: String
    ) throws {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw OpenSimError(code: .inputFailed, message: "Invalid xctestrun file")
        }
        let environment = [
            "OPENSIM_HELPER_SERVER_PORT": String(port),
            "OPENSIM_HELPER_BUNDLE_ID": bundleID,
        ]
        let updated = inject(plist, environment: environment) as? [String: Any] ?? plist
        let output = try PropertyListSerialization.data(fromPropertyList: updated, format: .xml, options: 0)
        try output.write(to: url, options: .atomic)
    }

    private static func inject(_ value: Any, environment: [String: String]) -> Any {
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

    private static func helperError(_ message: String, logURL: URL) -> OpenSimError {
        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        return OpenSimError(
            code: .inputFailed,
            message: message,
            details: ["log": String(log.suffix(2_000))],
            recovery: "Inspect the fixture UI test log and retry",
            retryable: true
        )
    }
}

private struct HelperRequestPayload: Encodable {
    let action: String
    let identifier: String?
    let x: Double?
    let y: Double?
    let fromX: Double?
    let fromY: Double?
    let toX: Double?
    let toY: Double?
    let durationMs: Int?
    let text: String?
    let scale: Double?
    let angle: Double?
    let dx: Double?
    let dy: Double?
    let key: String?
    let modifierCommand: Bool?
    let modifierShift: Bool?
    let modifierOption: Bool?
    let modifierControl: Bool?
    let button: String?

    init(action: XCUITestHelperAction) {
        self.action = action.kind.rawValue
        identifier = action.identifier
        x = action.point?.x
        y = action.point?.y
        fromX = action.from?.x
        fromY = action.from?.y
        toX = action.to?.x
        toY = action.to?.y
        durationMs = action.durationMs
        text = action.text
        scale = action.scale
        angle = action.angle
        dx = action.deltaX
        dy = action.deltaY
        key = action.key
        modifierCommand = action.modifiers?.command
        modifierShift = action.modifiers?.shift
        modifierOption = action.modifiers?.option
        modifierControl = action.modifiers?.control
        button = action.button?.rawValue
    }
}

private final class HelperConnection {
    private let fd: Int32
    private var buffer = Data()
    private var closed = false

    init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        close()
    }

    func sendLine(_ text: String) throws {
        let bytes = Array((text + "\n").utf8)
        var offset = 0
        while offset < bytes.count {
            let sent = bytes[offset...].withUnsafeBytes { raw in
                Darwin.send(fd, raw.baseAddress, raw.count, 0)
            }
            if sent <= 0 {
                throw OpenSimError(code: .inputFailed, message: "XCUITest helper connection write failed")
            }
            offset += sent
        }
    }

    func readLine(timeoutMs: Int32) throws -> String {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                return String(decoding: line, as: UTF8.self)
            }
            var pollDescriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pollDescriptor, 1, timeoutMs)
            if ready == 0 {
                throw OpenSimError(
                    code: .inputFailed,
                    message: "XCUITest helper response timed out",
                    retryable: true
                )
            }
            if ready < 0 {
                if errno == EINTR { continue }
                throw OpenSimError(code: .inputFailed, message: "XCUITest helper poll failed: \(errno)")
            }
            var chunk = [UInt8](repeating: 0, count: 4_096)
            let count = recv(fd, &chunk, chunk.count, 0)
            if count > 0 {
                buffer.append(chunk, count: count)
            } else if count == 0 {
                throw OpenSimError(code: .inputFailed, message: "XCUITest helper connection closed")
            } else if errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK {
                throw OpenSimError(code: .inputFailed, message: "XCUITest helper read failed: \(errno)")
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        Darwin.close(fd)
    }
}

private struct HelperListener {
    let fd: Int32
    let port: UInt16

    static func open() throws -> HelperListener {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw OpenSimError(code: .internalError, message: "socket failed: \(errno)")
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(fd, 1) == 0 else {
            Darwin.close(fd)
            throw OpenSimError(code: .internalError, message: "bind/listen failed: \(errno)")
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &length)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(fd)
            throw OpenSimError(code: .internalError, message: "getsockname failed: \(errno)")
        }
        return HelperListener(fd: fd, port: UInt16(bigEndian: bound.sin_port))
    }

    func accept(timeoutMs: Int32) throws -> Int32 {
        var pollDescriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pollDescriptor, 1, timeoutMs)
        if ready == 0 {
            throw OpenSimError(code: .inputFailed, message: "Timed out waiting for the XCUITest helper")
        }
        if ready < 0 {
            throw OpenSimError(code: .inputFailed, message: "accept poll failed: \(errno)")
        }
        let client = Darwin.accept(fd, nil, nil)
        guard client >= 0 else {
            throw OpenSimError(code: .inputFailed, message: "accept failed: \(errno)")
        }
        return client
    }

    func close() {
        Darwin.close(fd)
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
