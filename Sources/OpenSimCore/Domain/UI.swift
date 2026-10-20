import Foundation

public struct UIElement: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var role: String
    public var label: String?
    public var identifier: String?
    public var value: String?
    public var frame: Rect
    public var enabled: Bool
    public var selected: Bool
    public var children: [UIElement]

    public init(
        id: String,
        role: String,
        label: String?,
        identifier: String?,
        value: String?,
        frame: Rect,
        enabled: Bool,
        selected: Bool,
        children: [UIElement]
    ) {
        self.id = id
        self.role = role
        self.label = label
        self.identifier = identifier
        self.value = value
        self.frame = frame
        self.enabled = enabled
        self.selected = selected
        self.children = children
    }
}

public struct UITree: Codable, Sendable, Equatable {
    public var root: UIElement
    public var nodeCount: Int
    public var truncated: Bool

    public init(root: UIElement, nodeCount: Int, truncated: Bool) {
        self.root = root
        self.nodeCount = nodeCount
        self.truncated = truncated
    }
}

public struct ElementSelector: Codable, Sendable, Equatable {
    public var role: String?
    public var label: String?
    public var identifier: String?
    public var text: String?

    public init(role: String? = nil, label: String? = nil, identifier: String? = nil, text: String? = nil) {
        self.role = role
        self.label = label
        self.identifier = identifier
        self.text = text
    }
}
