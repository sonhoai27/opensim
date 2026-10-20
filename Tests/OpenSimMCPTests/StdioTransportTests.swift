import XCTest
@testable import OpenSimMCP
@testable import OpenSimProtocol
@testable import OpenSimCore

final class StdioTransportTests: XCTestCase {
    private func makeTransport() -> StdioTransport {
        StdioTransport(handler: MCPHandler(catalog: .plan3(), caller: FakeToolCaller(), serverVersion: "0.1.0"))
    }

    func testInitializeLineProducesResponse() async throws {
        let line = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#
        let lineOutput = await makeTransport().handleLine(line)
        let output = try XCTUnwrap(lineOutput)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(output.utf8))
        XCTAssertEqual(response.id, .number(1))
        XCTAssertEqual(response.result?["protocolVersion"], .string("2025-06-18"))
    }

    func testMalformedLineProducesParseError() async throws {
        let lineOutput = await makeTransport().handleLine("not json")
        let output = try XCTUnwrap(lineOutput)
        // JSON-RPC requires an explicit null id when the request id could not be read.
        XCTAssertTrue(output.contains(#""id":null"#), output)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(output.utf8))
        XCTAssertEqual(response.error?.code, -32700)
        XCTAssertNil(response.result)
    }

    func testNotificationProducesNoResponse() async {
        let line = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        let output = await makeTransport().handleLine(line)
        XCTAssertNil(output)
    }

    func testBlankLineProducesNoResponse() async {
        let output = await makeTransport().handleLine("   ")
        XCTAssertNil(output)
    }

    func testToolCallRoundTripsThroughLine() async throws {
        let line = #"{"jsonrpc":"2.0","id":"a","method":"tools/call","params":{"name":"device_list","arguments":{"limit":5}}}"#
        let lineOutput = await makeTransport().handleLine(line)
        let output = try XCTUnwrap(lineOutput)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(output.utf8))
        XCTAssertEqual(response.id, .string("a"))
        XCTAssertEqual(response.result?["isError"], .bool(false))
    }
}
