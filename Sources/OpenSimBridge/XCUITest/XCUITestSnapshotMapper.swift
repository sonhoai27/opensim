import Foundation
import OpenSimCore

public struct HelperNode: Codable, Sendable, Equatable {
    public var role: String
    public var identifier: String?
    public var label: String?
    public var value: String?
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var enabled: Bool
    public var selected: Bool
    public var children: [HelperNode]

    public init(
        role: String,
        identifier: String?,
        label: String?,
        value: String?,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        enabled: Bool,
        selected: Bool,
        children: [HelperNode]
    ) {
        self.role = role
        self.identifier = identifier
        self.label = label
        self.value = value
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.enabled = enabled
        self.selected = selected
        self.children = children
    }
}

public enum XCUITestSnapshotMapper {
    public static func toUIElement(_ node: HelperNode, path: String) -> UIElement {
        UIElement(
            id: "xct-\(path)",
            role: node.role,
            label: node.label,
            identifier: node.identifier,
            value: node.value,
            frame: Rect(x: node.x, y: node.y, width: node.width, height: node.height),
            enabled: node.enabled,
            selected: node.selected,
            children: node.children.enumerated().map { index, child in
                toUIElement(child, path: "\(path).\(index)")
            }
        )
    }

    public static func limited(_ root: UIElement, maxDepth: Int, maxNodes: Int) -> UITree {
        guard maxNodes > 0 else {
            var stripped = root
            stripped.children = []
            return UITree(root: stripped, nodeCount: 0, truncated: !root.children.isEmpty)
        }
        var count = 0
        var truncated = false

        func visit(_ element: UIElement, depth: Int) -> UIElement? {
            guard count < maxNodes else {
                truncated = true
                return nil
            }
            count += 1
            var children: [UIElement] = []
            if !element.children.isEmpty {
                if depth >= maxDepth {
                    truncated = true
                } else {
                    for child in element.children {
                        if let limited = visit(child, depth: depth + 1) {
                            children.append(limited)
                        } else {
                            truncated = true
                        }
                    }
                }
            }
            var copy = element
            copy.children = children
            return copy
        }

        guard let limitedRoot = visit(root, depth: 0) else {
            return UITree(root: root, nodeCount: 0, truncated: true)
        }
        return UITree(root: limitedRoot, nodeCount: count, truncated: truncated)
    }
}
