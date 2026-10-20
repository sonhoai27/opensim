import AppKit
import OpenSimCore

@MainActor
public protocol DisplaySurface: AnyObject {
    var view: NSView { get }
    var pixelSize: CGSize { get }
    var screenScale: CGFloat { get }
    var onSizeChange: ((CGSize) -> Void)? { get set }
    var onError: ((OpenSimError) -> Void)? { get set }

    func connect() async throws
    func disconnect()
}
