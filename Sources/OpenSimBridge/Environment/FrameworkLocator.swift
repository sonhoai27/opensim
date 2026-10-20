import Foundation
import OpenSimCore

public enum FrameworkLocator {
    public static func status(developerDir: String) -> FrameworkStatus {
        let contents = URL(fileURLWithPath: developerDir).deletingLastPathComponent()
        let simulatorKit = contents
            .appendingPathComponent("SharedFrameworks", isDirectory: true)
            .appendingPathComponent("SimulatorKit.framework", isDirectory: true)
        let coreSimulator = URL(fileURLWithPath: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework", isDirectory: true)
        return FrameworkStatus(
            coreSimulatorPath: coreSimulator.path,
            simulatorKitPath: simulatorKit.path,
            coreSimulatorPresent: FileManager.default.fileExists(atPath: coreSimulator.path),
            simulatorKitPresent: FileManager.default.fileExists(atPath: simulatorKit.path)
        )
    }
}
