import Foundation

public enum PathPolicy {
    public static let developerRoots: [String] = ["/Applications", "/Library/Developer"]

    public static var clientRoots: [String] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .resolvingSymlinksInPath()
            .path
        return [home, "/tmp", "/private/tmp", "/Applications", "/Library/Developer"]
    }

    public static func validateDeveloperDir(_ path: String) throws -> String {
        let url = try standardized(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw OpenSimError.invalidArgument("Developer directory does not exist: \(path)")
        }
        guard url.lastPathComponent == "Developer" || url.lastPathComponent == "CommandLineTools" else {
            throw OpenSimError.invalidArgument(
                "Developer directory must end with Developer or CommandLineTools: \(url.path)",
                recovery: "Run `xcode-select -p` and pass that path"
            )
        }
        guard isContained(url.path, in: developerRoots) else {
            throw OpenSimError(
                code: .permissionDenied,
                message: "Developer directory is outside the allowed roots: \(url.path)",
                details: ["allowed": developerRoots.joined(separator: ",")],
                recovery: "Use an Xcode installation under /Applications or /Library/Developer"
            )
        }
        return url.path
    }

    public static func validateAppBundle(_ path: String) throws -> String {
        try validateExistingFile(path, allowedExtensions: ["app"], requireDirectory: true)
    }

    public static func validateRuntimeImage(_ path: String) throws -> String {
        try validateExistingFile(path, allowedExtensions: ["dmg", "simruntime"], requireDirectory: false)
    }

    public static func validateExistingFile(
        _ path: String,
        allowedExtensions: [String],
        requireDirectory: Bool
    ) throws -> String {
        guard path.hasPrefix("/") else {
            throw OpenSimError.invalidArgument("Path must be absolute: \(path)")
        }
        let url = try standardized(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OpenSimError.invalidArgument("Path does not exist: \(url.path)")
        }
        guard isContained(url.path, in: clientRoots) else {
            throw OpenSimError(
                code: .permissionDenied,
                message: "Path is outside the allowed roots: \(url.path)",
                details: ["allowed": clientRoots.joined(separator: ",")],
                recovery: "Move the file under your home directory, /tmp, or /Applications"
            )
        }
        let extensionName = url.pathExtension.lowercased()
        guard allowedExtensions.map({ $0.lowercased() }).contains(extensionName) else {
            throw OpenSimError.invalidArgument(
                "Unsupported path extension: \(extensionName)",
                details: ["allowed": allowedExtensions.joined(separator: ",")]
            )
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else {
            throw OpenSimError.invalidArgument("Path does not exist: \(url.path)")
        }
        if requireDirectory && !isDirectory.boolValue {
            throw OpenSimError.invalidArgument("Path must be a directory: \(url.path)")
        }
        if !requireDirectory && isDirectory.boolValue && extensionName != "simruntime" {
            throw OpenSimError.invalidArgument("Path must be a file: \(url.path)")
        }
        return url.path
    }

    public static func isContained(_ path: String, in roots: [String]) -> Bool {
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.path
        return roots.contains { root in
            let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
            return candidate == normalizedRoot || candidate.hasPrefix(normalizedRoot + "/")
        }
    }

    private static func standardized(_ path: String) throws -> URL {
        guard path.hasPrefix("/") else {
            throw OpenSimError.invalidArgument("Path must be absolute: \(path)")
        }
        if path.contains("\0") {
            throw OpenSimError.invalidArgument("Path contains a null byte")
        }
        return URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }
}
