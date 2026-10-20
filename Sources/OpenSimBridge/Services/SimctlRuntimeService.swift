import Foundation
import OpenSimCore

public struct SimctlRuntimeService: RuntimeControlling {
    private let executor: any SimctlExecuting
    private let timeout: Duration
    private let downloader: any RuntimeDownloading

    public init(
        executor: any SimctlExecuting,
        timeout: Duration,
        downloader: any RuntimeDownloading = XcodebuildRuntimeDownloader()
    ) {
        self.executor = executor
        self.timeout = timeout
        self.downloader = downloader
    }

    public func listRuntimes() async throws -> [Runtime] {
        let command = SimctlArguments.listRuntimesJSON()
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let payload = try OpenSimJSON.decoder().decode(SimctlRuntimeListPayload.self, from: output.stdout)
        let runtimes = payload.runtimes.map { entry in
            Runtime(
                id: RuntimeID(entry.identifier),
                name: entry.name,
                platform: entry.platform.flatMap { Platform(rawValue: $0) }
                    ?? Device.platform(forRuntimeIdentifier: entry.identifier),
                version: entry.version,
                build: entry.buildversion ?? "",
                isAvailable: entry.isAvailable ?? true,
                path: entry.bundlePath ?? entry.runtimeRoot,
                source: .system
            )
        }
        return runtimes.sorted {
            if $0.platform.rawValue == $1.platform.rawValue {
                return $0.version.localizedStandardCompare($1.version) == .orderedAscending
            }
            return $0.platform.rawValue < $1.platform.rawValue
        }
    }

    public func downloadRuntime(platform: Platform, version: String) async throws -> Runtime {
        try await downloader.download(platform: platform, version: version)
        let runtimes = try await listRuntimes()
        guard let runtime = runtimes.first(where: { $0.platform == platform && $0.version == version }) else {
            throw OpenSimError(
                code: .runtimeVersionUnavailable,
                message: "Runtime \(platform.rawValue) \(version) was not found after download",
                details: ["platform": platform.rawValue, "version": version],
                recovery: "Run `opensim runtime list` and verify the installed version"
            )
        }
        return runtime
    }

    public func installRuntime(at path: String) async throws -> Runtime {
        let validated = try PathPolicy.validateRuntimeImage(path)
        let before = Set(try await listRuntimes().map(\.id))
        let command = SimctlArguments.runtimeAdd(path: validated)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let after = try await listRuntimes()
        guard let added = after.first(where: { !before.contains($0.id) }) else {
            throw OpenSimError(
                code: .simctlFailed,
                message: "Runtime was added but did not appear in the runtime list",
                details: ["path": validated],
                recovery: "Run `opensim runtime list` and verify the runtime manually"
            )
        }
        return added
    }

    public func deleteRuntime(_ id: RuntimeID) async throws {
        let command = SimctlArguments.runtimeDelete(identifier: id)
        let output = try await executor.run(command, timeout: timeout)
        guard output.status == 0 else {
            let mapped = SimctlErrorMapper.error(for: command, output: output)
            let text = String(decoding: output.stderr, as: UTF8.self)
            if text.localizedCaseInsensitiveContains("in use") || text.localizedCaseInsensitiveContains("booted") {
                throw OpenSimError(
                    code: .deviceBusy,
                    message: "Runtime is in use: \(id.rawValue)",
                    details: ["runtime": id.rawValue, "stderr": text],
                    recovery: "Shut down devices that use this runtime and retry",
                    retryable: false
                )
            }
            throw mapped
        }
    }

    public func verifyRuntime(_ id: RuntimeID) async throws {
        let command = SimctlArguments.runtimeVerify(identifier: id)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
    }
}
