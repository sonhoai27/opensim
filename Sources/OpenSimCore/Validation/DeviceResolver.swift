import Foundation

public enum DeviceResolver {
    public static func resolve(query: String?, in devices: [Device]) throws -> Device {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            let booted = devices.filter { $0.state == .booted }
            if booted.count == 1 {
                return booted[0]
            }
            if booted.isEmpty {
                throw OpenSimError(
                    code: .deviceNotFound,
                    message: "No booted device found",
                    recovery: "Boot a device or pass --device <udid|name>"
                )
            }
            throw OpenSimError.invalidArgument(
                "More than one booted device; pass --device",
                details: ["devices": booted.map(\.id.rawValue).joined(separator: ",")]
            )
        }

        if trimmed.lowercased().range(of: "^[0-9a-f-]{36}$", options: .regularExpression) != nil {
            if let match = devices.first(where: { $0.id.rawValue.lowercased() == trimmed.lowercased() }) {
                return match
            }
            throw OpenSimError.deviceNotFound(DeviceID(trimmed))
        }

        let matches = devices.filter { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        if matches.count == 1 {
            return matches[0]
        }
        if matches.isEmpty {
            throw OpenSimError(
                code: .deviceNotFound,
                message: "No device named \(trimmed)",
                recovery: "Run `opensim device list` to see device names"
            )
        }
        throw OpenSimError.invalidArgument(
            "Device name is ambiguous: \(trimmed)",
            details: ["devices": matches.map(\.id.rawValue).joined(separator: ",")],
            recovery: "Pass --device with a UDID"
        )
    }
}
