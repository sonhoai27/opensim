import Foundation
import OpenSimCore

enum SimctlPlistParser {
    static func appList(from data: Data) throws -> [AppInfo] {
        let object = try propertyList(from: data)
        guard let dictionary = object as? [String: Any] else {
            throw invalidPlist("listapps root is not a dictionary")
        }
        return dictionary.compactMap { bundleID, value in
            guard let fields = value as? [String: Any] else {
                return nil
            }
            return appInfo(bundleID: bundleID, fields: fields)
        }
        .sorted { $0.id < $1.id }
    }

    static func appInfo(from data: Data, bundleID: String) throws -> AppInfo {
        let object = try propertyList(from: data)
        guard let fields = object as? [String: Any] else {
            throw invalidPlist("appinfo root is not a dictionary")
        }
        guard let info = appInfo(bundleID: bundleID, fields: fields) else {
            throw invalidPlist("appinfo does not contain bundle fields")
        }
        return info
    }

    static func bundleID(atAppPath path: String) throws -> String {
        let infoURL = URL(fileURLWithPath: path).appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL) else {
            throw OpenSimError.invalidArgument(
                "App bundle does not contain Info.plist: \(path)",
                recovery: "Pass an installable .app directory"
            )
        }
        let object = try propertyList(from: data)
        guard let dictionary = object as? [String: Any],
              let bundleID = dictionary["CFBundleIdentifier"] as? String else {
            throw invalidPlist("Info.plist has no CFBundleIdentifier")
        }
        try IdentifierValidation.validateBundleID(bundleID)
        return bundleID
    }

    private static func appInfo(bundleID: String, fields: [String: Any]) -> AppInfo? {
        guard !bundleID.isEmpty else {
            return nil
        }
        return AppInfo(
            id: bundleID,
            displayName: string(fields["CFBundleDisplayName"]) ?? string(fields["CFBundleName"]),
            version: string(fields["CFBundleShortVersionString"]),
            build: string(fields["CFBundleVersion"]),
            dataContainer: path(fields["DataContainer"]),
            appContainer: path(fields["Path"])
        )
    }

    private static func propertyList(from data: Data) throws -> Any {
        do {
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw invalidPlist("Cannot parse property list: \(error.localizedDescription)")
        }
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func path(_ value: Any?) -> String? {
        guard var text = string(value), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("file://") {
            if let url = URL(string: text) {
                text = url.path
            }
        }
        while text.count > 1 && text.hasSuffix("/") {
            text.removeLast()
        }
        return text.isEmpty ? nil : text
    }

    private static func invalidPlist(_ message: String) -> OpenSimError {
        OpenSimError(
            code: .simctlFailed,
            message: message,
            recovery: "Run `xcrun simctl listapps <device>` manually and inspect the output"
        )
    }
}
