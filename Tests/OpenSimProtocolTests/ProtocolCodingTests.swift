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

    func testOperationRequestRoundTrip() throws {
        let request = OperationRequest(
            operation: "device_boot",
            parameters: ["device": "95B3747B-7065-447E-AB1E-53065142C3FC", "wait": "true"],
            sessionID: SessionID("session-1"),
            leaseID: LeaseID("lease-1"),
            dryRun: nil
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(request)
        let decoded = try OpenSimJSON.decoder().decode(OperationRequest.self, from: data)
        XCTAssertEqual(decoded, request)
    }

    func testOperationResultDataRoundTrip() throws {
        let payload = try OpenSimJSON.encoder(pretty: false).encode(["ok": true])
        let result = OperationResult(operation: "device_list", data: payload, auditID: "audit-1")
        let data = try OpenSimJSON.encoder(pretty: false).encode(result)
        let decoded = try OpenSimJSON.decoder().decode(OperationResult.self, from: data)
        XCTAssertEqual(decoded.data, payload)
        XCTAssertEqual(decoded.auditID, "audit-1")
    }

    func testDaemonEventRoundTrip() throws {
        let payload = DeviceStateChangedPayload(
            deviceID: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            state: .booted,
            previousState: .booting
        )
        let event = DaemonEvent(
            id: "7",
            type: .deviceStateChanged,
            timestamp: Date(timeIntervalSince1970: 1_797_000_000),
            data: try JSONValue.from(payload)
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(event)
        let decoded = try OpenSimJSON.decoder().decode(DaemonEvent.self, from: data)
        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.type.rawValue, "device.state.changed")
    }

    func testPlan3CatalogAddsSessionAndUITools() {
        let catalog = OperationCatalog.plan3()
        let names = Set(catalog.mcpOperations().map(\.mcpName))
        XCTAssertTrue(names.isSuperset(of: [
            "session_acquire", "session_release", "ui_tap", "ui_tree", "screen_screenshot"
        ]))
        XCTAssertNotNil(catalog.operation(forMCP: "session_acquire"))
        XCTAssertEqual(catalog.operation(forCLI: ["session", "release"])?.mcpName, "session_release")
    }
}
