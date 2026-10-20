import Foundation

public struct MetricSample: Codable, Sendable, Equatable {
    public var deviceID: DeviceID
    public var timestamp: Date
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var processCount: Int
    public var diskReadBytes: UInt64
    public var diskWriteBytes: UInt64

    public init(
        deviceID: DeviceID,
        timestamp: Date,
        cpuPercent: Double,
        memoryBytes: UInt64,
        processCount: Int,
        diskReadBytes: UInt64,
        diskWriteBytes: UInt64
    ) {
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.processCount = processCount
        self.diskReadBytes = diskReadBytes
        self.diskWriteBytes = diskWriteBytes
    }
}

public struct ProcessSample: Codable, Sendable, Equatable {
    public var pid: Int32
    public var parentPID: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64

    public init(pid: Int32, parentPID: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}
