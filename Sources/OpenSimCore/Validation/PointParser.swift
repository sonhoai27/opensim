import Foundation

public enum PointParser {
    public static func parse(_ text: String, label: String = "point") throws -> Point {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let x = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let y = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              x.isFinite,
              y.isFinite else {
            throw OpenSimError.invalidArgument(
                "\(label) must be two finite numbers in x,y form",
                recovery: "Pass a value such as 12.5,-4"
            )
        }
        return Point(x: x, y: y)
    }

    public static func parse(x: String?, y: String?) throws -> Point {
        guard let x, let y,
              let xValue = Double(x), let yValue = Double(y),
              xValue.isFinite, yValue.isFinite else {
            throw OpenSimError.invalidArgument(
                "x and y must both be finite numbers",
                recovery: "Pass both --x and --y"
            )
        }
        return Point(x: xValue, y: yValue)
    }
}
