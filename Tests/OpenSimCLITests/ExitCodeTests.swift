import XCTest
@testable import OpenSimCLI
@testable import OpenSimCore

final class ExitCodeTests: XCTestCase {
    func testExitCodesMatchCLIContract() {
        XCTAssertEqual(OpenSimExitCode.success.rawValue, 0)
        XCTAssertEqual(OpenSimExitCode.usage.rawValue, 2)
        XCTAssertEqual(OpenSimExitCode.notFound.rawValue, 3)
        XCTAssertEqual(OpenSimExitCode.conflict.rawValue, 4)
        XCTAssertEqual(OpenSimExitCode.unsupported.rawValue, 5)
        XCTAssertEqual(OpenSimExitCode.permission.rawValue, 6)
        XCTAssertEqual(OpenSimExitCode.confirmationRequired.rawValue, 7)
        XCTAssertEqual(OpenSimExitCode.internalError.rawValue, 10)
    }

    func testErrorToExitCode() {
        XCTAssertEqual(OpenSimExitCode.forError("invalid_argument"), .usage)
        XCTAssertEqual(OpenSimExitCode.forError("device_not_found"), .notFound)
        XCTAssertEqual(OpenSimExitCode.forError("lease_conflict"), .conflict)
        XCTAssertEqual(OpenSimExitCode.forError("capability_unavailable"), .unsupported)
        XCTAssertEqual(OpenSimExitCode.forError("xcode_not_found"), .permission)
        XCTAssertEqual(OpenSimExitCode.forError("confirmation_required"), .confirmationRequired)
        XCTAssertEqual(OpenSimExitCode.forError("internal"), .internalError)
    }
}
