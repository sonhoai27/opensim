import AppKit
import OpenSimCore

public struct ScreenPointerMapper: Sendable {
    public init() {}

    public func aspectFitRect(content: CGSize, in bounds: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    public func simulatorPoint(
        fromViewPoint point: CGPoint,
        in bounds: CGRect,
        contentSize: CGSize,
        rotation: ScreenRotation
    ) -> Point? {
        guard contentSize.width > 0, contentSize.height > 0 else { return nil }
        let displaySize = rotation.isSideways
            ? CGSize(width: contentSize.height, height: contentSize.width)
            : contentSize
        let rect = aspectFitRect(content: displaySize, in: bounds)
        guard rect.width > 0, rect.height > 0 else { return nil }

        let normalizedX = (point.x - rect.minX) / rect.width
        let normalizedTopY = 1 - (point.y - rect.minY) / rect.height
        guard (-0.001...1.001).contains(normalizedX),
              (-0.001...1.001).contains(normalizedTopY) else {
            return nil
        }
        let x = min(max(normalizedX, 0), 1)
        let y = min(max(normalizedTopY, 0), 1)

        let portrait: (x: Double, y: Double)
        switch rotation {
        case .portrait:
            portrait = (x, y)
        case .landscapeLeft:
            portrait = (y, 1 - x)
        case .portraitUpsideDown:
            portrait = (1 - x, 1 - y)
        case .landscapeRight:
            portrait = (1 - y, x)
        }
        return Point(
            x: portrait.x * contentSize.width,
            y: portrait.y * contentSize.height
        )
    }

    public func viewPoint(
        fromSimulatorPoint point: Point,
        in bounds: CGRect,
        contentSize: CGSize,
        rotation: ScreenRotation
    ) -> CGPoint? {
        guard contentSize.width > 0, contentSize.height > 0 else { return nil }
        let u = point.x / contentSize.width
        let v = point.y / contentSize.height
        guard (0...1).contains(u), (0...1).contains(v) else { return nil }

        let display: (x: Double, y: Double)
        switch rotation {
        case .portrait:
            display = (u, v)
        case .landscapeLeft:
            display = (1 - v, u)
        case .portraitUpsideDown:
            display = (1 - u, 1 - v)
        case .landscapeRight:
            display = (v, 1 - u)
        }

        let displaySize = rotation.isSideways
            ? CGSize(width: contentSize.height, height: contentSize.width)
            : contentSize
        let rect = aspectFitRect(content: displaySize, in: bounds)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return CGPoint(
            x: rect.minX + display.x * rect.width,
            y: rect.minY + (1 - display.y) * rect.height
        )
    }
}
