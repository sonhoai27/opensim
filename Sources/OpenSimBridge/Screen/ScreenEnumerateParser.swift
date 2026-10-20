import Foundation

public struct IOSurfaceDescriptor: Sendable, Equatable {
    public var uuid: String
    public var portIdentifier: String?
    public var displayClass: Int
    public var width: Int
    public var height: Int
    public var powerState: String?

    public init(
        uuid: String,
        portIdentifier: String? = nil,
        displayClass: Int,
        width: Int,
        height: Int,
        powerState: String? = nil
    ) {
        self.uuid = uuid
        self.portIdentifier = portIdentifier
        self.displayClass = displayClass
        self.width = width
        self.height = height
        self.powerState = powerState
    }
}

public enum ScreenEnumerateParser {
    public static func parse(_ text: String) -> [IOSurfaceDescriptor] {
        text.components(separatedBy: "\n\n").compactMap(parseBlock)
    }

    private static func parseBlock(_ block: String) -> IOSurfaceDescriptor? {
        var values: [String: String] = [:]
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if values[key] == nil {
                values[key] = value
            }
        }
        guard values["Class"] == "Display",
              let uuid = values["UUID"], !uuid.isEmpty,
              let width = values["Default width"].flatMap(Int.init),
              let height = values["Default height"].flatMap(Int.init) else {
            return nil
        }
        return IOSurfaceDescriptor(
            uuid: uuid,
            portIdentifier: values["Port Identifier"],
            displayClass: values["Display class"].flatMap(Int.init) ?? 0,
            width: width,
            height: height,
            powerState: values["Power state"]
        )
    }
}
