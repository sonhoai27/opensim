import Foundation
import OpenSimBridge
import OpenSimCore

public protocol CommandBackend: Sendable {
    func execute<T: Decodable & Sendable>(
        _ operation: String,
        parameters: [String: String],
        as type: T.Type
    ) async throws -> T
}

public struct DirectCommandBackend: CommandBackend {
    private let executor: BridgeOperationExecutor

    public init(executor: BridgeOperationExecutor) {
        self.executor = executor
    }

    public func execute<T: Decodable & Sendable>(
        _ operation: String,
        parameters: [String: String],
        as type: T.Type
    ) async throws -> T {
        let data = try await executor.execute(operation: operation, parameters: parameters)
        return try OpenSimJSON.decoder().decode(T.self, from: data)
    }
}
