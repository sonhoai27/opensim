import XCTest
@testable import OpenSimCore

final class BridgeProtocolTests: XCTestCase {
    func testCapabilitiesRoundTrip() throws {
        let capabilities = BridgeCapabilities(
            render: .unknown,
            hid: .unknown,
            accessibility: .unknown,
            screenshot: .available,
            video: .available,
            watch: .unavailable,
            tv: .unavailable
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(capabilities)
        let decoded = try OpenSimJSON.decoder().decode(BridgeCapabilities.self, from: data)
        XCTAssertEqual(decoded, capabilities)
    }

    func testBridgeServiceCasesAreStable() {
        XCTAssertEqual(BridgeService.screen.rawValue, "screen")
        XCTAssertEqual(BridgeService.input.rawValue, "input")
        XCTAssertEqual(BridgeService.accessibility.rawValue, "accessibility")
    }
}
