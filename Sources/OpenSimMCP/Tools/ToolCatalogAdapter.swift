import Foundation
import OpenSimCore
import OpenSimProtocol

public enum ToolCatalogAdapter {
    public static func tools(from catalog: OperationCatalog) -> [MCPToolDefinition] {
        catalog.mcpOperations().map { operation in
            var properties: [String: JSONValue] = [:]
            var required: [JSONValue] = []
            for parameter in operation.parameters {
                var schema: [String: JSONValue] = ["type": .string(parameter.type)]
                if let defaultValue = parameter.defaultValue {
                    schema["default"] = typedDefault(defaultValue, type: parameter.type)
                }
                properties[parameter.name] = .object(schema)
                if parameter.required {
                    required.append(.string(parameter.name))
                }
            }
            let inputSchema = JSONValue.object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required),
                "additionalProperties": .bool(false),
            ])
            return MCPToolDefinition(
                name: operation.mcpName,
                description: operation.summary,
                inputSchema: inputSchema
            )
        }
    }

    private static func typedDefault(_ value: String, type: String) -> JSONValue {
        switch type {
        case "boolean":
            return .bool(value.lowercased() == "true")
        case "integer":
            return .number(Double(Int(value) ?? 0))
        case "number":
            return .number(Double(value) ?? 0)
        default:
            return .string(value)
        }
    }
}
