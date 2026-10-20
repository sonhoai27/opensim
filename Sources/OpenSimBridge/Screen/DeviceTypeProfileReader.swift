import Foundation
import OpenSimCore

public struct ScreenProfile: Sendable, Equatable {
    public var scale: Double
    public var orientation: Double
    public var width: Int
    public var height: Int

    public init(scale: Double, orientation: Double, width: Int, height: Int) {
        self.scale = scale
        self.orientation = orientation
        self.width = width
        self.height = height
    }
}

public protocol ScreenProfileProviding: Sendable {
    func profile(for deviceType: String) async throws -> ScreenProfile
}

public actor SimctlDeviceTypeProfileProvider: ScreenProfileProviding {
    private let executor: any SimctlExecuting
    private let timeout: Duration
    private var cache: [String: ScreenProfile] = [:]

    public init(executor: any SimctlExecuting, timeout: Duration) {
        self.executor = executor
        self.timeout = timeout
    }

    public func profile(for deviceType: String) async throws -> ScreenProfile {
        if let cached = cache[deviceType] {
            return cached
        }
        guard !deviceType.isEmpty else {
            throw OpenSimError(
                code: .capabilityUnavailable,
                message: "Device type is missing for the device",
                recovery: "Recreate the device or refresh `simctl list devices -j`"
            )
        }
        let command = SimctlArguments.listDeviceTypesJSON()
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let payload = try OpenSimJSON.decoder().decode(SimctlDeviceTypeListPayload.self, from: output.stdout)
        guard let entry = payload.devicetypes.first(where: { $0.identifier == deviceType }) else {
            throw OpenSimError(
                code: .capabilityUnavailable,
                message: "Unknown device type: \(deviceType)",
                details: ["deviceType": deviceType],
                recovery: "Check `xcrun simctl list devicetypes`"
            )
        }
        let profile = try readProfile(bundlePath: entry.bundlePath, deviceType: deviceType)
        cache[deviceType] = profile
        return profile
    }

    private func readProfile(bundlePath: String, deviceType: String) throws -> ScreenProfile {
        let url = URL(fileURLWithPath: bundlePath)
            .appendingPathComponent("Contents/Resources/capabilities.plist")
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw OpenSimError(
                code: .capabilityUnavailable,
                message: "Could not read device type capabilities: \(url.path)",
                details: ["deviceType": deviceType],
                recovery: "Reinstall Xcode or verify the device type bundle"
            )
        }
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = object as? [String: Any],
              let capabilities = root["capabilities"] as? [String: Any],
              let dimensions = capabilities["ScreenDimensionsCapability"] as? [String: Any],
              let scale = dimensions["main-screen-scale"] as? NSNumber,
              let width = dimensions["main-screen-width"] as? NSNumber,
              let height = dimensions["main-screen-height"] as? NSNumber else {
            throw OpenSimError(
                code: .capabilityUnavailable,
                message: "Device type has no screen dimensions: \(deviceType)",
                details: ["deviceType": deviceType],
                recovery: "Use a device type supported by the installed runtime"
            )
        }
        let orientation = (dimensions["main-screen-orientation"] as? NSNumber)?.doubleValue ?? 0
        return ScreenProfile(
            scale: scale.doubleValue,
            orientation: orientation,
            width: width.intValue,
            height: height.intValue
        )
    }
}

private struct SimctlDeviceTypeListPayload: Decodable {
    let devicetypes: [SimctlDeviceTypePayload]
}

private struct SimctlDeviceTypePayload: Decodable {
    let identifier: String
    let bundlePath: String
}
