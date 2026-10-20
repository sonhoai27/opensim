import Foundation

public extension OperationCatalog {
    static func plan3() -> OperationCatalog {
        var catalog = OperationCatalog.plan2()
        for operation in Plan3Operations.all {
            catalog.register(operation)
        }
        return catalog
    }
}

public enum Plan3Operations {
    public static let all: [Operation] = [
        Operation(
            cliPath: ["session", "list"],
            mcpName: "session_list",
            summary: "List sessions and active leases",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: []
        ),
        Operation(
            cliPath: ["session", "acquire"],
            mcpName: "session_acquire",
            summary: "Acquire a control or observe lease for a device",
            requiresControlLease: false,
            destructive: false,
            readOnly: false,
            parameters: [
                OperationParameter(name: "device", type: "string", required: true),
                OperationParameter(name: "mode", type: "string", required: false, defaultValue: "control"),
                OperationParameter(name: "ttlSeconds", type: "integer", required: false, defaultValue: "300"),
            ]
        ),
        Operation(
            cliPath: ["session", "release"],
            mcpName: "session_release",
            summary: "Release a lease owned by the current session",
            requiresControlLease: false,
            destructive: false,
            readOnly: false,
            parameters: [
                OperationParameter(name: "leaseID", type: "string", required: true),
            ]
        ),
    ]
}
