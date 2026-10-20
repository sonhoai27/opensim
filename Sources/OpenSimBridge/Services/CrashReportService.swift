import Foundation
import OpenSimCore

public struct CrashReportScanner: Sendable {
    public static func scan(directory: URL, limit: Int) throws -> [CrashReport] {
        guard limit > 0 && limit <= 500 else {
            throw OpenSimError.invalidArgument("limit must be between 1 and 500")
        }
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey,
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        let allowed = Set(["ips", "crash", "panic"])
        let reports: [CrashReport] = urls.compactMap { url in
            guard allowed.contains(url.pathExtension.lowercased()) else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else {
                return nil
            }
            let name = url.deletingPathExtension().lastPathComponent
            let process = name.split(separator: "-").first.map(String.init) ?? name
            return CrashReport(
                id: url.path,
                processName: process,
                path: url.path,
                modifiedAt: values?.contentModificationDate ?? Date(timeIntervalSince1970: 0),
                sizeBytes: Int64(values?.fileSize ?? 0)
            )
        }
        return reports
            .sorted {
                if $0.modifiedAt == $1.modifiedAt {
                    return $0.path > $1.path
                }
                return $0.modifiedAt > $1.modifiedAt
            }
            .prefix(limit)
            .map { $0 }
    }
}

public struct CrashReportService: CrashReportReading {
    private let devices: any DeviceControlling

    public init(devices: any DeviceControlling, fileManager: FileManager = .default) {
        _ = fileManager
        self.devices = devices
    }

    public func crashReports(on device: DeviceID, limit: Int) async throws -> [CrashReport] {
        let info = try await devices.device(device)
        guard let dataPath = info.dataPath else {
            throw OpenSimError(
                code: .deviceNotFound,
                message: "Device has no data path: \(device.rawValue)",
                details: ["udid": device.rawValue]
            )
        }
        let directory = URL(fileURLWithPath: dataPath)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("CrashReporter", isDirectory: true)
        return try CrashReportScanner.scan(directory: directory, limit: limit)
    }
}
