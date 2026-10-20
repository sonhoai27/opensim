import Foundation

public enum StorageCategory: String, Codable, Sendable, CaseIterable {
    case simulatorDevice
    case simulatorCache
    case simulatorLog
    case runtime
    case derivedData
    case archive
    case appData
}

public struct StorageItem: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var category: StorageCategory
    public var path: String
    public var sizeBytes: Int64
    public var lastUsedAt: Date?
    public var safeToDelete: Bool
    public var reason: String?
    public var children: [StorageItem]

    public init(
        id: String,
        category: StorageCategory,
        path: String,
        sizeBytes: Int64,
        lastUsedAt: Date?,
        safeToDelete: Bool,
        reason: String?,
        children: [StorageItem]
    ) {
        self.id = id
        self.category = category
        self.path = path
        self.sizeBytes = sizeBytes
        self.lastUsedAt = lastUsedAt
        self.safeToDelete = safeToDelete
        self.reason = reason
        self.children = children
    }
}

public struct StorageScan: Codable, Sendable, Equatable {
    public var id: String
    public var createdAt: Date
    public var approximate: Bool
    public var items: [StorageItem]
    public var totalBytes: Int64
    public var reclaimableBytes: Int64

    public init(
        id: String,
        createdAt: Date,
        approximate: Bool,
        items: [StorageItem],
        totalBytes: Int64,
        reclaimableBytes: Int64
    ) {
        self.id = id
        self.createdAt = createdAt
        self.approximate = approximate
        self.items = items
        self.totalBytes = totalBytes
        self.reclaimableBytes = reclaimableBytes
    }
}

public struct CleanPlan: Codable, Sendable, Equatable {
    public var token: String
    public var expiresAt: Date
    public var itemIDs: [String]
    public var reclaimableBytes: Int64

    public init(token: String, expiresAt: Date, itemIDs: [String], reclaimableBytes: Int64) {
        self.token = token
        self.expiresAt = expiresAt
        self.itemIDs = itemIDs
        self.reclaimableBytes = reclaimableBytes
    }
}
