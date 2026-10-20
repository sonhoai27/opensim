import Darwin
import Foundation
import ObjectiveC
import OpenSimCore

public protocol SimulatorKitClassChecking: Sendable {
    func hasClass(_ name: String) -> Bool
    func responds(_ className: String, _ selector: String) -> Bool
    func indigoSymbols() -> [String]
    func sendSelectors(className: String) -> [String]
}

public struct SimulatorKitLoader: SimulatorKitClassChecking {
    private let kitExecutable: String?

    public static func live() -> SimulatorKitLoader {
        var coreExecutable: String?
        var kitExecutable: String?
        if let developerDir = try? XcodeLocator().developerDir() {
            let status = FrameworkLocator.status(developerDir: developerDir)
            coreExecutable = DynamicFramework.executablePath(for: status.coreSimulatorPath)
            kitExecutable = DynamicFramework.executablePath(for: status.simulatorKitPath)
        } else {
            coreExecutable = DynamicFramework.executablePath(
                for: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework"
            )
        }
        DynamicFramework.load(coreExecutable)
        DynamicFramework.load(kitExecutable)
        return SimulatorKitLoader(kitExecutable: kitExecutable)
    }

    public init(kitExecutable: String? = nil) {
        self.kitExecutable = kitExecutable
    }

    public static func coreSimulatorVersion() -> String? {
        guard let cls = NSClassFromString("SimDevice") else {
            return nil
        }
        return Bundle(for: cls).infoDictionary?["CFBundleVersion"] as? String
    }

    public func hasClass(_ name: String) -> Bool {
        Self.resolveClass(named: name) != nil
    }

    public func responds(_ className: String, _ selector: String) -> Bool {
        guard let cls = Self.resolveClass(named: className) else { return false }
        let selector = NSSelectorFromString(selector)
        return class_getInstanceMethod(cls, selector) != nil || class_getClassMethod(cls, selector) != nil
    }

    public func indigoSymbols() -> [String] {
        guard let kitExecutable else { return [] }
        let result = run("/usr/bin/nm", arguments: ["-gU", kitExecutable])
        guard result.status == 0 else { return [] }
        return result.stdout
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard let raw = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last else {
                    return nil
                }
                var symbol = String(raw)
                if symbol.hasPrefix("_") {
                    symbol.removeFirst()
                }
                return symbol.hasPrefix("IndigoHIDMessageFor") ? symbol : nil
            }
    }

    public func sendSelectors(className: String) -> [String] {
        selectors(className: className).filter { $0.hasPrefix("send") }
    }

    func selectors(className: String) -> [String] {
        guard let cls = Self.resolveClass(named: className) else { return [] }
        var targets: [AnyClass] = [cls]
        if let metaclass = object_getClass(cls) {
            targets.append(metaclass)
        }
        var names = Set<String>()
        for target in targets {
            var count: UInt32 = 0
            guard let methods = class_copyMethodList(target, &count) else { continue }
            defer { free(methods) }
            for index in 0..<Int(count) {
                names.insert(NSStringFromSelector(method_getName(methods[index])))
            }
        }
        return names.sorted()
    }

    static func resolveClass(named name: String) -> AnyClass? {
        if let cls = NSClassFromString(name) {
            return cls
        }
        if let cls = NSClassFromString("SimulatorKit.\(name)") {
            return cls
        }
        if let mangled = mangledNames[name], let cls = NSClassFromString(mangled) {
            return cls
        }
        return nil
    }

    static let mangledNames: [String: String] = [
        "SimDisplayView": "_TtC12SimulatorKit14SimDisplayView",
        "SimDeviceScreen": "_TtC12SimulatorKit15SimDeviceScreen",
        "SimDeviceLegacyHIDClient": "_TtC12SimulatorKit24SimDeviceLegacyHIDClient",
        "SimAccessibilityManager": "_TtC12SimulatorKit23SimAccessibilityManager",
    ]

    private func run(_ executable: String, arguments: [String]) -> (status: Int32, stdout: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        _ = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: stdout, as: UTF8.self))
    }
}

enum DynamicFramework {
    static func executablePath(for bundlePath: String?) -> String? {
        guard let bundlePath, !bundlePath.isEmpty, let bundle = Bundle(path: bundlePath) else {
            return nil
        }
        return bundle.executablePath
    }

    @discardableResult
    static func load(_ executable: String?) -> Bool {
        guard let executable else { return false }
        return dlopen(executable, RTLD_LAZY | RTLD_LOCAL) != nil
    }
}
