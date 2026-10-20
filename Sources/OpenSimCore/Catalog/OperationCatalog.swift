import Foundation

public struct OperationCatalog: Sendable {
    public private(set) var operations: [String: Operation]
    private var byCLIPath: [String: Operation]

    public init(operations: [Operation] = []) {
        self.operations = [:]
        self.byCLIPath = [:]
        for operation in operations {
            register(operation)
        }
    }

    public mutating func register(_ operation: Operation) {
        operations[operation.mcpName] = operation
        byCLIPath[OperationCatalog.cliKey(operation.cliPath)] = operation
    }

    public func operation(forCLI path: [String]) -> Operation? {
        byCLIPath[OperationCatalog.cliKey(path)]
    }

    public func operation(forMCP name: String) -> Operation? {
        operations[name]
    }

    public func mcpOperations() -> [Operation] {
        operations.values
            .filter(\.mcpExposed)
            .sorted { $0.mcpName < $1.mcpName }
    }

    public func cliOperations() -> [Operation] {
        operations.values.sorted { $0.cliPath.joined(separator: " ") < $1.cliPath.joined(separator: " ") }
    }

    public func validate() -> [String] {
        var issues: [String] = []
        var cliKeys: Set<String> = []
        var mcpNames: Set<String> = []
        for operation in operations.values {
            let cliKey = OperationCatalog.cliKey(operation.cliPath)
            if !cliKeys.insert(cliKey).inserted {
                issues.append("duplicate cli path: \(cliKey)")
            }
            if !mcpNames.insert(operation.mcpName).inserted {
                issues.append("duplicate mcp name: \(operation.mcpName)")
            }
            if operation.cliPath.isEmpty {
                issues.append("empty cli path: \(operation.mcpName)")
            }
            if operation.mcpName.isEmpty {
                issues.append("empty mcp name: \(cliKey)")
            }
            if operation.readOnly && operation.requiresControlLease {
                issues.append("read-only operation requires lease: \(operation.mcpName)")
            }
            if operation.destructive {
                let hasConfirm = operation.parameters.contains { $0.name == "confirm" && $0.required }
                if !hasConfirm {
                    issues.append("destructive operation lacks confirm: \(operation.mcpName)")
                }
            }
        }
        return issues.sorted()
    }

    private static func cliKey(_ path: [String]) -> String {
        path.joined(separator: "/")
    }
}
