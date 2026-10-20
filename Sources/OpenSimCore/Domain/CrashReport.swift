import Foundation

public struct CrashReport: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var processName: String
    public var path: String
    public var modifiedAt: Date
    public var sizeBytes: Int64

    public init(id: String, processName: String, path: String, modifiedAt: Date, sizeBytes: Int64) {
        self.id = id
        self.processName = processName
        self.path = path
        self.modifiedAt = modifiedAt
        self.sizeBytes = sizeBytes
    }
}
