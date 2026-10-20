import ArgumentParser
import Foundation
import OpenSimBridge
import OpenSimCore

public enum CLIRuntime {
    public static func makeBackend(_ globals: GlobalOptions) throws -> any CommandBackend {
        try globals.validated()
        let bridge = try SimctlBridge.live(timeout: .seconds(globals.timeout))
        let executor = BridgeOperationExecutor(
            bridge: bridge,
            crashReports: bridge,
            doctor: bridge
        )
        return DirectCommandBackend(executor: executor)
    }

    public static func run<T: Codable & Sendable>(
        globals: GlobalOptions,
        table: @escaping @Sendable (T) -> Table,
        exitCode: @escaping @Sendable (T) -> Int32 = { _ in 0 },
        body: @Sendable (any CommandBackend) async throws -> T
    ) async throws -> T {
        let renderer = OutputRenderer(json: globals.json)
        let started = Date()
        do {
            let backend = try makeBackend(globals)
            let value = try await body(backend)
            let duration = Int(Date().timeIntervalSince(started) * 1_000)
            try renderer.success(value, table: table(value), durationMs: duration)
            let code = exitCode(value)
            if code != 0 {
                throw ExitCode(code)
            }
            return value
        } catch let error as OpenSimError {
            let duration = Int(Date().timeIntervalSince(started) * 1_000)
            renderer.failure(error, durationMs: duration)
            throw ExitCode(OpenSimExitCode.forError(error.code).rawValue)
        } catch let code as ExitCode {
            throw code
        } catch {
            let duration = Int(Date().timeIntervalSince(started) * 1_000)
            let mapped = OpenSimError(
                code: .internalError,
                message: String(describing: error)
            )
            renderer.failure(mapped, durationMs: duration)
            throw ExitCode(OpenSimExitCode.internalError.rawValue)
        }
    }
}
