import ArgumentParser
import OpenSimCore

@main
public struct OpenSimCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "opensim",
        abstract: "Control Apple simulators from the command line",
        version: OpenSimVersion.version,
        subcommands: [
            DeviceCommand.self,
            RuntimeCommand.self,
            AppCommand.self,
            UICommand.self,
            LogCommand.self,
            DoctorCommand.self,
        ]
    )

    public init() {}
}
