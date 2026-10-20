import ArgumentParser
import Foundation
import OpenSimCore

public struct DoctorCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Report environment and capabilities"
    )

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        _ = try await CLIRuntime.run(
            globals: globals.directCopy(),
            table: { report in doctorTable(report) },
            exitCode: { report in
                guard let xcode = report.xcode else {
                    return OpenSimExitCode.permission.rawValue
                }
                if !xcode.isFullXcode {
                    return OpenSimExitCode.unsupported.rawValue
                }
                return OpenSimExitCode.success.rawValue
            }
        ) { backend in
            try await backend.execute("doctor_report", parameters: [:], as: DoctorReport.self)
        }
    }
}

private func doctorTable(_ report: DoctorReport) -> Table {
    let capabilityRows: [[String]] = [
        ["capability", "render", report.capabilities.render.rawValue, report.notes["screen"] ?? ""],
        ["capability", "hid", report.capabilities.hid.rawValue, report.notes["input"] ?? ""],
        ["capability", "a11y", report.capabilities.accessibility.rawValue, report.notes["a11y"] ?? ""],
        ["capability", "screenshot", report.capabilities.screenshot.rawValue, "simctl io"],
        ["capability", "video", report.capabilities.video.rawValue, "simctl io"],
        ["capability", "runtime", report.runtime.rawValue, "simctl runtime"],
        ["capability", "watch", report.capabilities.watch.rawValue, "watchOS runtime"],
        ["capability", "tv", report.capabilities.tv.rawValue, "tvOS runtime"],
    ]
    let environmentRows: [[String]] = [
        ["environment", "macOS", report.macOSVersion, ""],
        ["environment", "architecture", report.architecture, ""],
        ["environment", "xcode", report.xcode.map { "\($0.version) (\($0.build))" } ?? "missing", report.xcode?.path ?? ""],
        ["environment", "daemon", report.daemon.status.rawValue, ""],
        ["environment", "diskFreeBytes", "\(report.diskFreeBytes)", ""],
        ["environment", "devices", "\(report.deviceCount)", ""],
        ["environment", "runtimes", "\(report.runtimeCount)", ""],
    ]
    return Table(
        headers: ["SECTION", "ITEM", "STATUS", "NOTE"],
        rows: capabilityRows + environmentRows
    )
}
