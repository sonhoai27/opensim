import AppKit
import XCTest
@testable import OpenSimBridge
@testable import OpenSimBridgeUI
@testable import OpenSimCore

@MainActor
private final class FakeSurface: DisplaySurface {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
    var pixelSize = CGSize(width: 600, height: 1200)
    var screenScale: CGFloat = 3
    var onSizeChange: ((CGSize) -> Void)?
    var onError: ((OpenSimError) -> Void)?

    func connect() async throws {}
    func disconnect() {}
}

@MainActor
private struct FakeBridge: SimulatorScreenDisplaying {
    func makeDisplaySurface(for device: DeviceID) throws -> any DisplaySurface { FakeSurface() }
}

final class SimulatorScreenViewTests: XCTestCase {
    @MainActor
    func testConnectAndRotate() async throws {
        let view = try SimulatorScreenView(
            device: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            bridge: FakeBridge()
        )
        var size: CGSize?
        view.onScreenSizeChange = { size = $0 }
        try await view.connect()
        XCTAssertEqual(view.screenSize, CGSize(width: 200, height: 400))
        XCTAssertEqual(size, CGSize(width: 200, height: 400))
        view.setRotation(.landscapeLeft)
        XCTAssertEqual(view.screenSize, CGSize(width: 400, height: 200))
    }

    func testAspectFitRectCentersContent() {
        let mapper = ScreenPointerMapper()
        let rect = mapper.aspectFitRect(
            content: CGSize(width: 100, height: 200),
            in: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        XCTAssertEqual(rect, CGRect(x: 75, y: 0, width: 150, height: 300))
    }

    func testPortraitPointerMapping() {
        let mapper = ScreenPointerMapper()
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 200)
        let content = CGSize(width: 100, height: 200)
        XCTAssertEqual(
            mapper.simulatorPoint(
                fromViewPoint: CGPoint(x: 50, y: 100),
                in: bounds,
                contentSize: content,
                rotation: .portrait
            ),
            Point(x: 50, y: 100)
        )
        XCTAssertEqual(
            mapper.simulatorPoint(
                fromViewPoint: CGPoint(x: 25, y: 150),
                in: bounds,
                contentSize: content,
                rotation: .portrait
            ),
            Point(x: 25, y: 50)
        )
        XCTAssertNil(
            mapper.simulatorPoint(
                fromViewPoint: CGPoint(x: -5, y: 100),
                in: bounds,
                contentSize: content,
                rotation: .portrait
            )
        )
    }

    func testLandscapePointerMappingRoundTrips() throws {
        let mapper = ScreenPointerMapper()
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)
        let content = CGSize(width: 200, height: 400)
        let devicePoint = Point(x: 50, y: 100)
        let viewPoint = try XCTUnwrap(
            mapper.viewPoint(
                fromSimulatorPoint: devicePoint,
                in: bounds,
                contentSize: content,
                rotation: .landscapeLeft
            )
        )
        let roundTrip = try XCTUnwrap(
            mapper.simulatorPoint(
                fromViewPoint: viewPoint,
                in: bounds,
                contentSize: content,
                rotation: .landscapeLeft
            )
        )
        XCTAssertEqual(roundTrip.x, devicePoint.x, accuracy: 0.001)
        XCTAssertEqual(roundTrip.y, devicePoint.y, accuracy: 0.001)
    }
}
