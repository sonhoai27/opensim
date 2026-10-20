import Foundation

public struct OperationParameter: Sendable, Equatable {
    public var name: String
    public var type: String
    public var required: Bool
    public var defaultValue: String?

    public init(name: String, type: String, required: Bool, defaultValue: String? = nil) {
        self.name = name
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
    }
}

public struct Operation: Sendable, Equatable {
    public var cliPath: [String]
    public var mcpName: String
    public var summary: String
    public var requiresControlLease: Bool
    public var destructive: Bool
    public var readOnly: Bool
    public var parameters: [OperationParameter]
    public var mcpExposed: Bool
    public var requiredService: BridgeService?

    public init(
        cliPath: [String],
        mcpName: String,
        summary: String,
        requiresControlLease: Bool,
        destructive: Bool,
        readOnly: Bool,
        parameters: [OperationParameter],
        mcpExposed: Bool = true,
        requiredService: BridgeService? = nil
    ) {
        self.cliPath = cliPath
        self.mcpName = mcpName
        self.summary = summary
        self.requiresControlLease = requiresControlLease
        self.destructive = destructive
        self.readOnly = readOnly
        self.parameters = parameters
        self.mcpExposed = mcpExposed
        self.requiredService = requiredService
    }
}
