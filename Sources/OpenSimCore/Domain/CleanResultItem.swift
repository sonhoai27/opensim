import Foundation

public struct CleanResultItem: Codable, Sendable, Equatable {
    public var itemID: String
    public var success: Bool
    public var error: OpenSimError?

    public init(itemID: String, success: Bool, error: OpenSimError?) {
        self.itemID = itemID
        self.success = success
        self.error = error
    }
}
