import XCTest
@testable import OpenSimCore
@testable import OpenSimProtocol

final class ProtocolCodingTests: XCTestCase {
    func testDaemonStateRoundTrip() throws {
        let state = DaemonState(
            pid: 12_345,
            port: 54_321,
            token: "token-value",
            version: "0.1.0",
            xcodeVersion: "27.1",
            startedAt: Date(timeIntervalSince1970: 1_797_000_000)
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(state)
        let decoded = try OpenSimJSON.decoder().decode(DaemonState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testHealthResponseDoesNotContainToken() throws {
        let health = HealthResponse(
            status: "ok",
            version: "0.1.0",
            protocolVersion: 1,
            pid: 10,
            port: 20,
            startedAt: Date(timeIntervalSince1970: 1_797_000_000),
            capabilities: BridgeCapabilities(
                render: .unavailable,
                hid: .unavailable,
                accessibility: .unavailable,
                screenshot: .available,
                video: .available,
                watch: .unavailable,
                tv: .unavailable
            ),
            xcodeVersion: "27.1"
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(health)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("token"))
        let decoded = try OpenSimJSON.decoder().decode(HealthResponse.self, from: data)
        XCTAssertEqual(decoded.capabilities.screenshot, .available)
    }

    func testJSONValueCoding() throws {
        let value = JSONValue.object([
            "name": .string("opensim"),
            "count": .number(3),
            "enabled": .bool(true),
            "items": .array([.string("a"), .null]),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.objectValue?["name"], .string("opensim"))
    }

    func testJSONValueFromEncodable() throws {
        let device = Device(
            id: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            name: "iPhone Air",
            platform: .iOS,
            deviceType: "iPhone-Air",
            runtime: RuntimeID("iOS-27-0"),
            state: .booted,
            isAvailable: true,
            dataPath: nil,
            lastBootedAt: nil
        )
        let value = try JSONValue.from(device)
        XCTAssertEqual(value.objectValue?["id"], .string("95B3747B-7065-447E-AB1E-53065142C3FC"))
        XCTAssertEqual(value.objectValue?["state"], .string("booted"))
    }
}
