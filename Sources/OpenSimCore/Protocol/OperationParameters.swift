import Foundation

public struct OperationParameters: Sendable {
    public let values: [String: String]

    public init(_ values: [String: String]) {
        self.values = values
    }

    public func validated(against operation: Operation) throws -> OperationParameters {
        var allowed = Set(operation.parameters.map(\.name))
        if operation.destructive {
            allowed.insert("confirm")
        }
        for key in values.keys where !allowed.contains(key) {
            throw OpenSimError.invalidArgument(
                "Unknown parameter \(key) for \(operation.mcpName)",
                recovery: "Remove the parameter or use `--help`"
            )
        }
        for parameter in operation.parameters where parameter.required && parameter.name != "confirm" {
            guard let value = values[parameter.name], !value.isEmpty else {
                throw OpenSimError.invalidArgument(
                    "Missing required parameter \(parameter.name) for \(operation.mcpName)"
                )
            }
        }
        return self
    }

    public func string(_ name: String) throws -> String {
        guard let value = values[name], !value.isEmpty else {
            throw OpenSimError.invalidArgument("Missing required parameter \(name)")
        }
        return value
    }

    public func optionalString(_ name: String) -> String? {
        guard let value = values[name] else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func bool(_ name: String, default defaultValue: Bool) throws -> Bool {
        guard let value = optionalString(name) else {
            return defaultValue
        }
        switch value.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            throw OpenSimError.invalidArgument("Parameter \(name) must be a boolean")
        }
    }

    public func int(_ name: String, default defaultValue: Int?) throws -> Int {
        guard let value = optionalString(name) else {
            if let defaultValue {
                return defaultValue
            }
            throw OpenSimError.invalidArgument("Missing required parameter \(name)")
        }
        guard let parsed = Int(value) else {
            throw OpenSimError.invalidArgument("Parameter \(name) must be an integer")
        }
        return parsed
    }

    public func jsonArray(_ name: String) throws -> [String]? {
        guard let value = optionalString(name) else {
            return nil
        }
        guard let data = value.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            throw OpenSimError.invalidArgument("Parameter \(name) must be a JSON string array")
        }
        return array
    }

    public func jsonObject(_ name: String) throws -> [String: String]? {
        guard let value = optionalString(name) else {
            return nil
        }
        guard let data = value.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw OpenSimError.invalidArgument("Parameter \(name) must be a JSON string map")
        }
        return object
    }
}
