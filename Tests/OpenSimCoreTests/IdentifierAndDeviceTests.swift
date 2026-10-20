import XCTest
@testable import OpenSimCore

final class IdentifierAndDeviceTests: XCTestCase {
    func testDeviceIDEncodesAsSingleString() throws {
        let device = Device(
            id: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            name: "iPhone Air",
            platform: .iOS,
            deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-Air",
            runtime: RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"),
            state: .booted,
            isAvailable: true,
            dataPath: "/tmp/device-data",
            lastBootedAt: nil
        )
        let data = try JSONEncoder().encode(device)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["id"] as? String, "95B3747B-7065-447E-AB1E-53065142C3FC")
        XCTAssertEqual(object["runtime"] as? String, "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
        XCTAssertEqual(object["state"] as? String, "booted")
    }

    func testDeviceStateParsing() {
        XCTAssertEqual(Device.parseState("Shutdown"), .shutdown)
        XCTAssertEqual(Device.parseState("Booted"), .booted)
        XCTAssertEqual(Device.parseState("Booting"), .booting)
        XCTAssertEqual(Device.parseState("Shutting Down"), .shuttingDown)
        XCTAssertEqual(Device.parseState("Erasing"), .erasing)
        XCTAssertEqual(Device.parseState("Deleting"), .deleting)
        XCTAssertEqual(Device.parseState("Unavailable"), .unknown)
    }

    func testPlatformFromRuntimeIdentifier() {
        XCTAssertEqual(Device.platform(forRuntimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0"), .iOS)
        XCTAssertEqual(Device.platform(forRuntimeIdentifier: "com.apple.CoreSimulator.SimRuntime.watchOS-27-0"), .watchOS)
        XCTAssertEqual(Device.platform(forRuntimeIdentifier: "com.apple.CoreSimulator.SimRuntime.tvOS-27-0"), .tvOS)
        XCTAssertEqual(Device.platform(forRuntimeIdentifier: "com.apple.CoreSimulator.SimRuntime.xrOS-27-0"), .visionOS)
        XCTAssertEqual(Device.platform(forRuntimeIdentifier: "custom"), .unknown)
    }
}
