import Foundation

public enum IdentifierValidation {
    public static func isUDID(_ value: String) -> Bool {
        let pattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    public static func validateUDID(_ value: String) throws -> DeviceID {
        guard isUDID(value) else {
            throw OpenSimError.invalidArgument(
                "Invalid device UDID: \(value)",
                recovery: "Use a UDID returned by `opensim device list`"
            )
        }
        return DeviceID(value)
    }

    public static func validateBundleID(_ value: String) throws {
        let pattern = "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$"
        guard value.count <= 255, value.range(of: pattern, options: .regularExpression) != nil else {
            throw OpenSimError.invalidArgument(
                "Invalid bundle identifier: \(value)",
                recovery: "Use a reverse-DNS bundle identifier such as com.example.app"
            )
        }
    }

    public static func validateName(_ value: String, field: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else {
            throw OpenSimError.invalidArgument(
                "\(field) must contain 1 to 128 characters",
                recovery: "Pass a non-empty \(field)"
            )
        }
        guard trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw OpenSimError.invalidArgument("\(field) contains control characters")
        }
    }

    public static func validateRuntimeIdentifier(_ value: String) throws -> RuntimeID {
        let pattern = "^[A-Za-z0-9._-]+$"
        guard value.count <= 255, value.range(of: pattern, options: .regularExpression) != nil else {
            throw OpenSimError.invalidArgument(
                "Invalid runtime identifier: \(value)",
                recovery: "Use an identifier returned by `opensim runtime list`"
            )
        }
        return RuntimeID(value)
    }
}
