import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

private struct Checker: SimulatorKitClassChecking {
    var classes: Set<String> = []
    var selectors: Set<String> = []
    var symbols: [String] = []
    var sends: [String] = []

    func hasClass(_ name: String) -> Bool { classes.contains(name) }
    func responds(_ className: String, _ selector: String) -> Bool { selectors.contains("\(className).\(selector)") }
    func indigoSymbols() -> [String] { symbols }
    func sendSelectors(className: String) -> [String] { sends }
}

final class Plan2CapabilityGateTests: XCTestCase {
    func testPrimaryNeedsDisplaySelectorsAndAccessibilityGetter() {
        var checker = Checker()
        checker.classes = ["SimServiceContext", "SimDisplayView", "SimDeviceScreen", "SimAccessibilityManager"]
        checker.selectors = [
            "SimDisplayView.setDevice:",
            "SimDisplayView.connectedScreen",
            "SimDisplayView.pixelSize",
            "SimDeviceScreen.unmaskedSurface",
            "SimAccessibilityManager.rootElement",
        ]
        let result = Plan2CapabilityGate.evaluate(checker: checker, helperConfigured: true)
        XCTAssertEqual(result.render, .simDisplayView)
        XCTAssertEqual(result.input, .simulatorKit)
        XCTAssertEqual(result.accessibility, .simAccessibilityManager)
    }

    func testFallbacksAndUnavailable() {
        var checker = Checker()
        checker.classes = ["SimServiceContext", "SimDeviceScreen"]
        checker.selectors = ["SimDeviceScreen.screen"]
        XCTAssertEqual(Plan2CapabilityGate.evaluate(checker: checker, helperConfigured: true).render, .ioSurface)

        let empty = Plan2CapabilityGate.evaluate(checker: Checker(), helperConfigured: true)
        XCTAssertEqual(empty.render, .screenshotPolling)
        XCTAssertEqual(empty.input, .xcuiTest)
        XCTAssertEqual(empty.accessibility, .xcuiTest)

        let unavailable = Plan2CapabilityGate.evaluate(checker: Checker(), helperConfigured: false)
        XCTAssertEqual(unavailable.input, .unavailable)
        XCTAssertEqual(unavailable.accessibility, .unavailable)
    }

    func testSurfaceWithoutDisplaySelectorsUsesIOSurface() {
        var checker = Checker()
        checker.classes = ["SimServiceContext", "SimDisplayView", "SimDeviceScreen"]
        checker.selectors = ["SimDisplayView.setDevice:", "SimDeviceScreen.screen"]
        let result = Plan2CapabilityGate.evaluate(checker: checker, helperConfigured: false)
        XCTAssertEqual(result.render, .ioSurface)
        XCTAssertEqual(result.input, .unavailable)
    }

    func testDTUHIDBackendIsSelected() {
        let result = Plan2CapabilityGate.evaluate(
            checker: Checker(),
            helperConfigured: false,
            supportsDTUHID: true
        )
        XCTAssertEqual(result.input, .dtuhid)
        XCTAssertEqual(result.multiTouch, .available)
        XCTAssertEqual(result.hardwareButtons, .available)
        XCTAssertEqual(result.notes["input"], "dtuhid")
    }

    func testIndigoSymbolsMarkGesturesUnknownNotAvailable() {
        var checker = Checker()
        checker.classes = ["SimServiceContext", "SimDeviceScreen"]
        checker.selectors = ["SimDeviceScreen.screen"]
        checker.symbols = ["IndigoHIDMessageForMouseNSEvent"]
        checker.sends = ["sendWithMessage:freeWhenDone:completionQueue:completion:"]
        let result = Plan2CapabilityGate.evaluate(checker: checker, helperConfigured: false)
        XCTAssertEqual(result.multiTouch, .unknown)
        XCTAssertEqual(result.hardwareButtons, .unknown)
        XCTAssertEqual(result.notes["indigoSymbolCount"], "1")
    }
}
