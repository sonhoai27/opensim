import Foundation
import OpenSimCore

public struct SimctlAppService: AppControlling {
    private let executor: any SimctlExecuting
    private let timeout: Duration

    public init(executor: any SimctlExecuting, timeout: Duration) {
        self.executor = executor
        self.timeout = timeout
    }

    public func listApps(on device: DeviceID, filter: String?) async throws -> [AppInfo] {
        let command = SimctlArguments.listApps(device)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let apps = try SimctlPlistParser.appList(from: output.stdout)
        guard let filter, !filter.isEmpty else {
            return apps
        }
        return apps.filter { app in
            app.id.localizedCaseInsensitiveContains(filter) ||
                (app.displayName ?? "").localizedCaseInsensitiveContains(filter)
        }
    }

    public func installApp(on device: DeviceID, at path: String) async throws -> AppInfo {
        let validated = try PathPolicy.validateAppBundle(path)
        let bundleID = try SimctlPlistParser.bundleID(atAppPath: validated)
        let command = SimctlArguments.installApp(device, path: validated)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        return try await appInfo(on: device, bundleID: bundleID)
    }

    public func uninstallApp(on device: DeviceID, bundleID: String) async throws {
        try IdentifierValidation.validateBundleID(bundleID)
        let command = SimctlArguments.uninstallApp(device, bundleID: bundleID)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
    }

    public func launchApp(
        on device: DeviceID,
        bundleID: String,
        args: [String],
        environment: [String: String]
    ) async throws -> Int32 {
        try IdentifierValidation.validateBundleID(bundleID)
        for key in environment.keys {
            try IdentifierValidation.validateName(key, field: "environment key")
        }
        let command = SimctlArguments.launchApp(device, bundleID: bundleID, args: args, environment: environment)
        let output = try await executor.run(command, timeout: timeout)
        guard output.status == 0 else {
            throw SimctlErrorMapper.error(for: command, output: output)
        }
        let text = String(decoding: output.stdout, as: UTF8.self)
        let lastLine = text
            .split(separator: "\n")
            .last
            .map(String.init) ?? ""
        guard let pidText = lastLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
              let pid = Int32(pidText) else {
            throw OpenSimError(
                code: .simctlFailed,
                message: "simctl launch did not return a pid",
                details: ["stdout": text],
                recovery: "Check that the bundle identifier is installed"
            )
        }
        return pid
    }

    public func terminateApp(on device: DeviceID, bundleID: String) async throws {
        try IdentifierValidation.validateBundleID(bundleID)
        let command = SimctlArguments.terminateApp(device, bundleID: bundleID)
        let output = try await executor.run(command, timeout: timeout)
        if output.status == 0 {
            return
        }
        let text = String(decoding: output.stderr, as: UTF8.self)
        if text.localizedCaseInsensitiveContains("found nothing to terminate") {
            return
        }
        throw SimctlErrorMapper.error(for: command, output: output)
    }

    public func appInfo(on device: DeviceID, bundleID: String) async throws -> AppInfo {
        try IdentifierValidation.validateBundleID(bundleID)
        let command = SimctlArguments.appInfo(device, bundleID: bundleID)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        return try SimctlPlistParser.appInfo(from: output.stdout, bundleID: bundleID)
    }

    public func containerPath(on device: DeviceID, bundleID: String, kind: ContainerKind) async throws -> String {
        try IdentifierValidation.validateBundleID(bundleID)
        let command = SimctlArguments.getAppContainer(device, bundleID: bundleID, kind: kind)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let text = String(decoding: output.stdout, as: UTF8.self)
        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "(null)" }
        guard let path = lines.first(where: { $0.hasPrefix("/") }) else {
            throw OpenSimError(
                code: .simctlFailed,
                message: "No \(kind.rawValue) container for \(bundleID)",
                details: ["stdout": text, "kind": kind.rawValue],
                recovery: "Check `xcrun simctl get_app_container <device> <bundle> <container>` manually"
            )
        }
        return path
    }
}
