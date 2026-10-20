import AppKit
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

struct SurfaceChecker: SimulatorKitClassChecking {
    var classes: Set<String> = []
    var selectors: Set<String> = []

    func hasClass(_ name: String) -> Bool { classes.contains(name) }
    func responds(_ className: String, _ selector: String) -> Bool { selectors.contains("\(className).\(selector)") }
    func indigoSymbols() -> [String] { [] }
    func sendSelectors(className: String) -> [String] { [] }
}

final class FallbackTests: XCTestCase {
    func testIOSurfaceSupport() {
        var checker = SurfaceChecker()
        checker.classes = ["SimServiceContext", "SimDeviceScreen"]
        checker.selectors = ["SimDeviceScreen.screen"]
        XCTAssertTrue(IOSurfaceDisplaySurface.isSupported(checker: checker))

        checker.selectors = []
        XCTAssertFalse(IOSurfaceDisplaySurface.isSupported(checker: checker))

        var missingDeviceClass = SurfaceChecker()
        missingDeviceClass.classes = ["SimServiceContext"]
        missingDeviceClass.selectors = ["SimDeviceScreen.screen"]
        XCTAssertFalse(IOSurfaceDisplaySurface.isSupported(checker: missingDeviceClass))
    }

    @MainActor
    func testIOSurfaceConnectsToBootedDevice() async throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_GATE"] == "1" else {
            throw XCTSkip("set OPENSIM_GATE=1 to connect to a booted simulator")
        }
        let service = SimctlDeviceService(executor: ProcessSimctlExecutor(), timeout: .seconds(30))
        guard let booted = try await service.listDevices().first(where: { $0.state == .booted }) else {
            throw XCTSkip("no booted simulator")
        }
        let surface = IOSurfaceDisplaySurface(device: booted.id)
        try await surface.connect()
        defer { surface.disconnect() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(surface.pixelSize.width, 0)
        XCTAssertGreaterThan(surface.pixelSize.height, 0)
        XCTAssertNotNil(surface.view.layer?.contents)
    }
}
