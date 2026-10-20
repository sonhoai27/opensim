import Foundation

public enum RuntimeSource: String, Codable, Sendable {
    case system
    case xcodeCatalog = "xcode_catalog"
    case file
}

public struct Runtime: Codable, Sendable, Identifiable, Equatable {
    public let id: RuntimeID
    public var name: String
    public var platform: Platform
    public var version: String
    public var build: String
    public var isAvailable: Bool
    public var path: String?
    public var sizeBytes: Int64?
    public var source: RuntimeSource?
    public var deviceCount: Int?

    public init(
        id: RuntimeID,
        name: String,
        platform: Platform,
        version: String,
        build: String,
        isAvailable: Bool,
        path: String?,
        sizeBytes: Int64? = nil,
        source: RuntimeSource? = nil,
        deviceCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.version = version
        self.build = build
        self.isAvailable = isAvailable
        self.path = path
        self.sizeBytes = sizeBytes
        self.source = source
        self.deviceCount = deviceCount
    }
}
