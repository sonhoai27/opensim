import Foundation

public enum SelectorParser {
    public static func parse(_ text: String) throws -> ElementSelector {
        var selector = ElementSelector()
        var seen = Set<String>()
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace || text[index] == "," {
                index = text.index(after: index)
            }
            if index == text.endIndex { break }

            var key = ""
            while index < text.endIndex, text[index] != "=" {
                key.append(text[index])
                index = text.index(after: index)
            }
            guard index < text.endIndex else {
                throw OpenSimError.invalidArgument("Selector field \(key) is missing '='")
            }
            index = text.index(after: index)

            var value = ""
            var quote: Character?
            var escaped = false
            while index < text.endIndex {
                let character = text[index]
                if escaped {
                    value.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if let active = quote {
                    if character == active { quote = nil } else { value.append(character) }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "," {
                    break
                } else {
                    value.append(character)
                }
                index = text.index(after: index)
            }
            guard quote == nil, !escaped else {
                throw OpenSimError.invalidArgument("Selector value has an unterminated quote or escape")
            }

            var normalizedKey = key.trimmingCharacters(in: .whitespaces).lowercased()
            if normalizedKey == "id" {
                normalizedKey = "identifier"
            }
            let normalizedValue = value.trimmingCharacters(in: .whitespaces)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else {
                throw OpenSimError.invalidArgument("Selector key and value must not be empty")
            }
            guard seen.insert(normalizedKey).inserted else {
                throw OpenSimError.invalidArgument("Duplicate selector field \(normalizedKey)")
            }
            switch normalizedKey {
            case "role":
                selector.role = normalizedValue
            case "label":
                selector.label = normalizedValue
            case "identifier":
                selector.identifier = normalizedValue
            case "text":
                selector.text = normalizedValue
            default:
                throw OpenSimError.invalidArgument(
                    "Unknown selector field \(normalizedKey)",
                    details: ["allowed": "role,label,id,text"]
                )
            }
        }
        guard selector.role != nil || selector.label != nil || selector.identifier != nil || selector.text != nil else {
            throw OpenSimError.invalidArgument("Selector must contain at least one field")
        }
        return selector
    }
}
