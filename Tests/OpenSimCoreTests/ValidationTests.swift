import XCTest
@testable import OpenSimCore

final class ValidationTests: XCTestCase {
    func testUDIDValidation() {
        XCTAssertTrue(IdentifierValidation.isUDID("95B3747B-7065-447E-AB1E-53065142C3FC"))
        XCTAssertFalse(IdentifierValidation.isUDID("95B3747B7065447EAB1E53065142C3FC"))
        XCTAssertFalse(IdentifierValidation.isUDID("booted"))
        XCTAssertFalse(IdentifierValidation.isUDID("95B3747B-7065-447E-AB1E-53065142C3F"))
    }

    func testBundleIDValidation() throws {
        XCTAssertNoThrow(try IdentifierValidation.validateBundleID("com.apple.Preferences"))
        XCTAssertNoThrow(try IdentifierValidation.validateBundleID("dev.opensim.OpenSimFixture"))
        XCTAssertThrowsError(try IdentifierValidation.validateBundleID("Preferences"))
        XCTAssertThrowsError(try IdentifierValidation.validateBundleID("com..apple"))
        XCTAssertThrowsError(try IdentifierValidation.validateBundleID("com.apple Preferences"))
    }

    func testDeveloperDirAllowlist() throws {
        XCTAssertNoThrow(try PathPolicy.validateDeveloperDir("/Applications/Xcode.app/Contents/Developer"))
        XCTAssertNoThrow(try PathPolicy.validateDeveloperDir("/Library/Developer/CommandLineTools"))
        XCTAssertThrowsError(try PathPolicy.validateDeveloperDir("/tmp/Xcode.app/Contents/Developer"))
        XCTAssertThrowsError(try PathPolicy.validateDeveloperDir("/Applications/Other.app/Contents/Developer"))
    }

    func testAppBundleNeedsExistingAppDirectory() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-validation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Sample.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertNoThrow(try PathPolicy.validateAppBundle(app.path))
        let file = root.appendingPathComponent("Sample.txt")
        try Data("x".utf8).write(to: file)
        XCTAssertThrowsError(try PathPolicy.validateAppBundle(file.path))
        XCTAssertThrowsError(try PathPolicy.validateAppBundle("/tmp/does-not-exist.app"))
    }

    func testPathTraversalIsRejected() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-traversal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Escape.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundle)
        XCTAssertThrowsError(try PathPolicy.validateAppBundle(link.path + "/../../../etc"))
    }

    func testDeviceResolverByUDIDAndName() throws {
        let booted = Device(
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
        XCTAssertEqual(try DeviceResolver.resolve(query: nil, in: [booted]).id, booted.id)
        XCTAssertEqual(try DeviceResolver.resolve(query: "iPhone Air", in: [booted]).id, booted.id)
        XCTAssertEqual(try DeviceResolver.resolve(query: booted.id.rawValue.lowercased(), in: [booted]).id, booted.id)
        XCTAssertThrowsError(try DeviceResolver.resolve(query: "Missing", in: [booted]))
    }

    func testDeviceResolverRejectsAmbiguousName() {
        let first = Device(
            id: DeviceID("11111111-1111-1111-1111-111111111111"),
            name: "Same",
            platform: .iOS,
            deviceType: "iPhone-Air",
            runtime: RuntimeID("iOS-27-0"),
            state: .shutdown,
            isAvailable: true,
            dataPath: nil,
            lastBootedAt: nil
        )
        let second = Device(
            id: DeviceID("22222222-2222-2222-2222-222222222222"),
            name: "Same",
            platform: .iOS,
            deviceType: "iPhone-Air",
            runtime: RuntimeID("iOS-27-0"),
            state: .shutdown,
            isAvailable: true,
            dataPath: nil,
            lastBootedAt: nil
        )
        XCTAssertThrowsError(try DeviceResolver.resolve(query: "Same", in: [first, second]))
    }
}
