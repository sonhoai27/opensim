import XCTest
@testable import OpenSimCLI
@testable import OpenSimCore

final class LockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func append(_ text: String) {
        lock.lock()
        value += text
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class OutputRendererTests: XCTestCase {
    func testTableAlignment() {
        let table = Table(headers: ["A", "BB"], rows: [["1", "22"], ["333", "4"]])
        XCTAssertEqual(table.rendered(), "A    BB\n1    22\n333  4")
    }

    func testJSONSuccessEnvelope() throws {
        let output = LockedText()
        let errorOutput = LockedText()
        let renderer = OutputRenderer(
            json: true,
            writeOut: { output.append($0) },
            writeErr: { errorOutput.append($0) }
        )
        try renderer.success(["one", "two"], table: nil, durationMs: 9)
        let data = try XCTUnwrap(output.text.data(using: .utf8))
        let envelope = try OpenSimJSON.decoder().decode(Envelope<[String]>.self, from: data)
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.data, ["one", "two"])
        XCTAssertEqual(envelope.meta.durationMs, 9)
        XCTAssertEqual(errorOutput.text, "")
    }

    func testHumanFailureGoesToStderr() {
        let output = LockedText()
        let errorOutput = LockedText()
        let renderer = OutputRenderer(
            json: false,
            writeOut: { output.append($0) },
            writeErr: { errorOutput.append($0) }
        )
        renderer.failure(.invalidArgument("bad value", recovery: "Use a good value"), durationMs: 1)
        XCTAssertEqual(output.text, "")
        XCTAssertTrue(errorOutput.text.contains("error[invalid_argument]"))
        XCTAssertTrue(errorOutput.text.contains("Use a good value"))
    }

    func testJSONFailureEnvelope() throws {
        let errorOutput = LockedText()
        let renderer = OutputRenderer(
            json: true,
            writeOut: { _ in },
            writeErr: { errorOutput.append($0) }
        )
        renderer.failure(.deviceNotFound(DeviceID("11111111-1111-1111-1111-111111111111")), durationMs: 2)
        let data = try XCTUnwrap(errorOutput.text.data(using: .utf8))
        let envelope = try OpenSimJSON.decoder().decode(Envelope<EmptyPayload>.self, from: data)
        XCTAssertFalse(envelope.ok)
        XCTAssertEqual(envelope.error?.code, "device_not_found")
    }
}
