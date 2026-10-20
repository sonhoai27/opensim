import XCTest
@testable import OpenSimCore

final class EnvelopeTests: XCTestCase {
    func testSuccessEnvelope() throws {
        let envelope = Envelope<[Device]>.success(
            [],
            requestId: "REQ-1",
            durationMs: 12
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(envelope)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertEqual((object["meta"] as? [String: Any])?["requestId"] as? String, "REQ-1")
        XCTAssertTrue(object["error"] is NSNull)
    }

    func testFailureEnvelopeDecodesError() throws {
        let error = OpenSimError.invalidArgument("bad value")
        let envelope = Envelope<EmptyPayload>.failure(error, requestId: "REQ-2", durationMs: 4)
        let data = try OpenSimJSON.encoder(pretty: false).encode(envelope)
        let decoded = try OpenSimJSON.decoder().decode(Envelope<EmptyPayload>.self, from: data)
        XCTAssertFalse(decoded.ok)
        XCTAssertNil(decoded.data)
        XCTAssertEqual(decoded.error?.code, "invalid_argument")
        XCTAssertEqual(decoded.meta.requestId, "REQ-2")
    }

    func testDateUsesISO8601WithFractionalSeconds() throws {
        let date = Date(timeIntervalSince1970: 1_797_000_000.25)
        let text = OpenSimDate.string(from: date)
        XCTAssertTrue(text.contains("."))
        let parsed = try XCTUnwrap(OpenSimDate.date(from: text))
        XCTAssertEqual(parsed.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }
}
