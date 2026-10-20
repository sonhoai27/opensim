import XCTest
@testable import OpenSimDaemon

final class SecurityTests: XCTestCase {
    func testHostPolicy() {
        XCTAssertTrue(RequestSecurity.isLoopbackHost("127.0.0.1:5555"))
        XCTAssertTrue(RequestSecurity.isLoopbackHost("localhost:1234"))
        XCTAssertTrue(RequestSecurity.isLoopbackHost("[::1]:1234"))
        XCTAssertTrue(RequestSecurity.isLoopbackHost("127.0.0.1"))
        XCTAssertFalse(RequestSecurity.isLoopbackHost("evil.example:1234"))
        XCTAssertFalse(RequestSecurity.isLoopbackHost(nil))
    }

    func testOriginPolicy() {
        XCTAssertTrue(RequestSecurity.isAllowedOrigin(nil))
        XCTAssertTrue(RequestSecurity.isAllowedOrigin("http://127.0.0.1:5555"))
        XCTAssertTrue(RequestSecurity.isAllowedOrigin("http://localhost:9090"))
        XCTAssertFalse(RequestSecurity.isAllowedOrigin("https://evil.example"))
        XCTAssertFalse(RequestSecurity.isAllowedOrigin("file:///tmp/page.html"))
    }

    func testTokenPolicy() {
        XCTAssertTrue(RequestSecurity.isAuthorized("Bearer secret", token: "secret"))
        XCTAssertFalse(RequestSecurity.isAuthorized("Bearer wrong", token: "secret"))
        XCTAssertFalse(RequestSecurity.isAuthorized(nil, token: "secret"))
        XCTAssertFalse(RequestSecurity.isAuthorized("secret", token: "secret"))
    }
}
