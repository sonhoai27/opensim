import Foundation

public struct Table: Sendable, Equatable {
    public var headers: [String]
    public var rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }

    public func rendered() -> String {
        guard !headers.isEmpty else {
            return rows.map { $0.joined(separator: "  ") }.joined(separator: "\n")
        }
        let widths = headers.indices.map { index in
            ([headers] + rows)
                .map { row in row.indices.contains(index) ? row[index].count : 0 }
                .max() ?? 0
        }
        func line(_ row: [String]) -> String {
            let text = headers.indices.map { index in
                let value = row.indices.contains(index) ? row[index] : ""
                return value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }
            .joined(separator: "  ")
            var trimmed = text
            while trimmed.hasSuffix(" ") {
                trimmed.removeLast()
            }
            return trimmed
        }
        return ([line(headers)] + rows.map(line)).joined(separator: "\n")
    }
}
