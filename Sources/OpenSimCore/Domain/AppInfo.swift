import Foundation

public enum ContainerKind: String, Codable, Sendable, CaseIterable {
    case app
    case data
    case group
}

public struct AppInfo: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var displayName: String?
    public var version: String?
    public var build: String?
    public var dataContainer: String?
    public var appContainer: String?

    public init(
        id: String,
        displayName: String?,
        version: String?,
        build: String?,
        dataContainer: String?,
        appContainer: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.build = build
        self.dataContainer = dataContainer
        self.appContainer = appContainer
    }
}
