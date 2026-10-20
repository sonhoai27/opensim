import XCTest
@testable import OpenSimCore

final class ErrorTests: XCTestCase {
    func testErrorJSONShape() throws {
        let error = OpenSimError(
            code: .leaseConflict,
            message: "Device is controlled by another session",
            details: ["owner": "agent-42"],
            recovery: "Take control or wait for the lease to expire",
            retryable: true
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(error)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["code"] as? String, "lease_conflict")
        XCTAssertEqual(object["retryable"] as? Bool, true)
        XCTAssertEqual((object["details"] as? [String: String])?["owner"], "agent-42")
    }

    func testExitCodeMapping() {
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.invalidArgument.rawValue), .usage)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.deviceNotFound.rawValue), .notFound)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.leaseConflict.rawValue), .conflict)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.leaseRequired.rawValue), .conflict)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.deviceNotBooted.rawValue), .conflict)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.unsupportedXcode.rawValue), .unsupported)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.privateApiUnavailable.rawValue), .unsupported)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.capabilityUnavailable.rawValue), .unsupported)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.permissionDenied.rawValue), .permission)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.xcodeNotFound.rawValue), .permission)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.confirmationRequired.rawValue), .confirmationRequired)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.simctlFailed.rawValue), .internalError)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.internalError.rawValue), .internalError)
    }

    func testCapabilityUnavailableIsStable() {
        let error = OpenSimError.capabilityUnavailable("screen")
        XCTAssertEqual(error.code, "capability_unavailable")
        XCTAssertEqual(error.retryable, false)
        XCTAssertEqual(error.details["capability"], "screen")
    }
}
