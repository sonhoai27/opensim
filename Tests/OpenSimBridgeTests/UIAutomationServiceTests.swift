import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

private struct FakeAccessibility: AccessibilityReading {
    let tree: UITree

    func tree(on device: DeviceID, maxDepth: Int, maxNodes: Int) async throws -> UITree { tree }

    func find(on device: DeviceID, selector: ElementSelector) async throws -> [UIElement] {
        UIElementMatcher.find(in: tree.root, selector: selector)
    }
}

private actor TapRecorder {
    private(set) var points: [Point] = []
    func add(_ point: Point) { points.append(point) }
}

private struct FakeInput: InputControlling {
    let recorder: TapRecorder

    func tap(on device: DeviceID, at point: Point, settle: Bool) async throws { await recorder.add(point) }
    func swipe(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {}
    func longPress(on device: DeviceID, at point: Point, durationMs: Int) async throws {}
    func drag(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {}
    func pinch(on device: DeviceID, center: Point, scale: Double, durationMs: Int) async throws {}
    func rotate(on device: DeviceID, center: Point, angle: Double, durationMs: Int) async throws {}
    func scroll(on device: DeviceID, deltaX: Double, deltaY: Double, at point: Point?) async throws {}
    func typeText(on device: DeviceID, text: String) async throws {}
    func key(on device: DeviceID, key: Key, modifiers: KeyModifiers) async throws {}
    func button(on device: DeviceID, button: HardwareButton) async throws {}
}

final class UIAutomationServiceTests: XCTestCase {
    func testTapSelectorUsesCenter() async throws {
        let button = UIElement(
            id: "e",
            role: "button",
            label: "Go",
            identifier: "go",
            value: nil,
            frame: Rect(x: 10, y: 20, width: 100, height: 40),
            enabled: true,
            selected: false,
            children: []
        )
        let tree = UITree(
            root: UIElement(
                id: "root",
                role: "application",
                label: nil,
                identifier: nil,
                value: nil,
                frame: Rect(x: 0, y: 0, width: 390, height: 844),
                enabled: true,
                selected: false,
                children: [button]
            ),
            nodeCount: 2,
            truncated: false
        )
        let recorder = TapRecorder()
        let service = UIAutomationService(
            screen: nil,
            input: FakeInput(recorder: recorder),
            accessibility: FakeAccessibility(tree: tree)
        )
        let result = try await service.tap(
            on: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            selector: ElementSelector(identifier: "go"),
            settle: false
        )
        XCTAssertEqual(result.point, Point(x: 60, y: 40))
        XCTAssertEqual(result.matchedCount, 1)
        let points = await recorder.points
        XCTAssertEqual(points, [Point(x: 60, y: 40)])
    }

    func testMissingServicesReturnCapabilityUnavailable() async {
        let service = UIAutomationService(screen: nil, input: nil, accessibility: nil)
        do {
            _ = try await service.tap(
                on: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
                selector: ElementSelector(identifier: "missing"),
                settle: false
            )
            XCTFail("expected capability_unavailable")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "capability_unavailable")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testTapSelectorWithoutFrameThrows() async throws {
        let element = UIElement(
            id: "empty",
            role: "button",
            label: "Go",
            identifier: "go",
            value: nil,
            frame: Rect(x: 0, y: 0, width: 0, height: 0),
            enabled: true,
            selected: false,
            children: []
        )
        let tree = UITree(root: element, nodeCount: 1, truncated: false)
        let service = UIAutomationService(
            screen: nil,
            input: FakeInput(recorder: TapRecorder()),
            accessibility: FakeAccessibility(tree: tree)
        )
        do {
            _ = try await service.tap(
                on: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
                selector: ElementSelector(identifier: "go"),
                settle: false
            )
            XCTFail("expected invalid_argument")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "invalid_argument")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
