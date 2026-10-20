import ArgumentParser
import OpenSimCore

public struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Device UDID or name")
    public var device: String?

    @Option(name: .long, help: "Timeout in seconds")
    public var timeout: Int = 60

    @Flag(name: .long, help: "Emit a JSON envelope")
    public var json: Bool = false

    @Flag(name: .long, help: "Confirm destructive operations")
    public var yes: Bool = false

    public init() {}

    public func validate() throws {
        guard timeout > 0 && timeout <= 3_600 else {
            throw OpenSimError.invalidArgument(
                "timeout must be between 1 and 3600 seconds"
            )
        }
    }

    public func parameters(_ base: [String: String] = [:]) -> [String: String] {
        var values = base
        if let device, !device.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values["device"] = device
        }
        return values
    }
}
