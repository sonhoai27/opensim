import Foundation

public extension OperationCatalog {
    static func plan1() -> OperationCatalog {
        OperationCatalog(operations: Plan1Operations.all)
    }
}

public enum Plan1Operations {
    private static func parameter(
        _ name: String,
        _ type: String,
        required: Bool = true,
        default defaultValue: String? = nil
    ) -> OperationParameter {
        OperationParameter(name: name, type: type, required: required, defaultValue: defaultValue)
    }

    private static let device = parameter("device", "string", required: false)
    private static let bundleID = parameter("bundleID", "string")
    private static let path = parameter("path", "string")
    private static let identifier = parameter("identifier", "string")
    private static let confirm = parameter("confirm", "boolean")
    private static let wait = parameter("wait", "boolean", required: false, default: "false")
    private static let limit = parameter("limit", "integer", required: false, default: "100")

    public static let all: [Operation] = [
        Operation(
            cliPath: ["device", "list"],
            mcpName: "device_list",
            summary: "List simulator devices",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [
                parameter("platform", "string", required: false),
                parameter("state", "string", required: false),
            ]
        ),
        Operation(
            cliPath: ["device", "get"],
            mcpName: "device_get",
            summary: "Get one simulator device",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [device]
        ),
        Operation(
            cliPath: ["device", "create"],
            mcpName: "device_create",
            summary: "Create a simulator device",
            requiresControlLease: false,
            destructive: false,
            readOnly: false,
            parameters: [
                parameter("name", "string"),
                parameter("deviceType", "string"),
                parameter("runtime", "string", required: false),
            ]
        ),
        Operation(
            cliPath: ["device", "clone"],
            mcpName: "device_clone",
            summary: "Clone a simulator device",
            requiresControlLease: false,
            destructive: false,
            readOnly: false,
            parameters: [device, parameter("name", "string")]
        ),
        Operation(
            cliPath: ["device", "boot"],
            mcpName: "device_boot",
            summary: "Boot a simulator device",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [device, wait]
        ),
        Operation(
            cliPath: ["device", "shutdown"],
            mcpName: "device_shutdown",
            summary: "Shut down a simulator device",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [device, wait]
        ),
        Operation(
            cliPath: ["device", "erase"],
            mcpName: "device_erase",
            summary: "Erase all content from a simulator device",
            requiresControlLease: true,
            destructive: true,
            readOnly: false,
            parameters: [device, confirm]
        ),
        Operation(
            cliPath: ["device", "delete"],
            mcpName: "device_delete",
            summary: "Delete a simulator device",
            requiresControlLease: true,
            destructive: true,
            readOnly: false,
            parameters: [device, confirm]
        ),
        Operation(
            cliPath: ["device", "rename"],
            mcpName: "device_rename",
            summary: "Rename a simulator device",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [device, parameter("name", "string")]
        ),
        Operation(
            cliPath: ["device", "status"],
            mcpName: "device_status",
            summary: "Read simulator device state",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [device]
        ),
        Operation(
            cliPath: ["runtime", "list"],
            mcpName: "runtime_list",
            summary: "List installed simulator runtimes",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [parameter("platform", "string", required: false)]
        ),
        Operation(
            cliPath: ["runtime", "install"],
            mcpName: "runtime_install",
            summary: "Install a simulator runtime from a disk image",
            requiresControlLease: false,
            destructive: false,
            readOnly: false,
            parameters: [path]
        ),
        Operation(
            cliPath: ["runtime", "delete"],
            mcpName: "runtime_delete",
            summary: "Delete an installed simulator runtime",
            requiresControlLease: false,
            destructive: true,
            readOnly: false,
            parameters: [identifier, confirm]
        ),
        Operation(
            cliPath: ["runtime", "verify"],
            mcpName: "runtime_verify",
            summary: "Verify the signature of an installed runtime",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [identifier],
            mcpExposed: false
        ),
        Operation(
            cliPath: ["app", "list"],
            mcpName: "app_list",
            summary: "List applications installed on a device",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [device, parameter("filter", "string", required: false)]
        ),
        Operation(
            cliPath: ["app", "install"],
            mcpName: "app_install",
            summary: "Install an application bundle on a device",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [device, path]
        ),
        Operation(
            cliPath: ["app", "uninstall"],
            mcpName: "app_uninstall",
            summary: "Uninstall an application from a device",
            requiresControlLease: true,
            destructive: true,
            readOnly: false,
            parameters: [device, bundleID, confirm]
        ),
        Operation(
            cliPath: ["app", "launch"],
            mcpName: "app_launch",
            summary: "Launch an application on a device",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [
                device,
                bundleID,
                parameter("args", "array", required: false),
                parameter("env", "object", required: false),
            ]
        ),
        Operation(
            cliPath: ["app", "terminate"],
            mcpName: "app_terminate",
            summary: "Terminate an application on a device",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [device, bundleID]
        ),
        Operation(
            cliPath: ["app", "info"],
            mcpName: "app_info",
            summary: "Read application metadata",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [device, bundleID]
        ),
        Operation(
            cliPath: ["app", "container"],
            mcpName: "app_container",
            summary: "Resolve an application container path",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [device, bundleID, parameter("kind", "string", required: false, default: "app")]
        ),
        Operation(
            cliPath: ["log", "tail"],
            mcpName: "log_tail",
            summary: "Read a page of unified log entries from a device",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [
                device,
                parameter("cursor", "string", required: false),
                limit,
                parameter("filter", "string", required: false),
            ]
        ),
        Operation(
            cliPath: ["log", "crash"],
            mcpName: "log_crash",
            summary: "List crash reports for a device",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [device, parameter("limit", "integer", required: false, default: "20")],
            mcpExposed: false
        ),
        Operation(
            cliPath: ["doctor"],
            mcpName: "doctor_report",
            summary: "Report environment and capability status",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: []
        ),
    ]
}
