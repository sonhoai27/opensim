import Foundation

public enum UIElementMatcher {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    public static func matches(_ element: UIElement, selector: ElementSelector) -> Bool {
        if let role = selector.role,
           !equals(element.role, role) {
            return false
        }
        if let label = selector.label,
           !equals(element.label ?? "", label) {
            return false
        }
        if let identifier = selector.identifier,
           !equals(element.identifier ?? "", identifier) {
            return false
        }
        if let text = selector.text {
            let fields = [element.label, element.value, element.identifier].compactMap { $0 }
            guard fields.contains(where: { contains($0, text) }) else {
                return false
            }
        }
        return true
    }

    public static func find(
        in root: UIElement,
        selector: ElementSelector,
        limit: Int = 100
    ) -> [UIElement] {
        guard limit > 0 else { return [] }
        var results: [UIElement] = []
        func visit(_ element: UIElement) {
            guard results.count < limit else { return }
            if matches(element, selector: selector) {
                results.append(element)
            }
            for child in element.children {
                guard results.count < limit else { return }
                visit(child)
            }
        }
        visit(root)
        return results
    }

    private static func equals(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: options) == .orderedSame
    }

    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: options) != nil
    }
}
