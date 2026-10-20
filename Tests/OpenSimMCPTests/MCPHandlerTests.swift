import XCTest
@testable import OpenSimMCP
@testable import OpenSimProtocol
@testable import OpenSimCore

struct FakeToolCaller: MCPToolCalling {
    var result: JSONValue? = nil
    var error: OpenSimError? = nil

    func call(tool: OpenSimCore.Operation, arguments: JSONValue) async throws -> JSONValue {
        if let error {
            throw error
        }
        return result ?? .object([:])
    }
}

final class MCPHandlerTests: XCTestCase {
    private func handler(caller: FakeToolCaller) -> MCPHandler {
        MCPHandler(catalog: .plan3(), caller: caller, serverVersion: "0.1.0")
    }

    func testInitializeProtocolVersionAndCapabilities() async throws {
        let response = await handler(caller: FakeToolCaller()).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(1),
            method: "initialize",
            params: .object(["protocolVersion": .string("2025-06-18")])
        ))
        XCTAssertEqual(response?.id, .number(1))
        XCTAssertEqual(response?.result?["protocolVersion"], .string("2025-06-18"))
        XCTAssertEqual(response?.result?["capabilities"]?["tools"]?["listChanged"], .bool(false))
        XCTAssertEqual(response?.result?["serverInfo"]?["name"], .string("opensim"))
    }

    func testToolsListComesFromCatalog() async throws {
        let response = await handler(caller: FakeToolCaller()).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(2),
            method: "tools/list",
            params: nil
        ))
        let tools = try XCTUnwrap(response?.result?["tools"]?.arrayValue)
        let names = Set(tools.compactMap { $0["name"]?.stringValue })
        XCTAssertTrue(names.contains("device_boot"))
        XCTAssertTrue(names.contains("session_acquire"))
        XCTAssertTrue(names.contains("ui_tap"))
        XCTAssertTrue(names.contains("ui_tree"))
        XCTAssertTrue(names.contains("screen_screenshot"))
        XCTAssertFalse(names.contains("log_crash"))
    }

    func testUnknownToolReturnsInvalidParams() async throws {
        let response = await handler(caller: FakeToolCaller()).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(3),
            method: "tools/call",
            params: .object(["name": .string("missing_tool"), "arguments": .object([:])])
        ))
        XCTAssertEqual(response?.error?.code, -32602)
        XCTAssertNil(response?.result)
    }

    func testHiddenCatalogToolIsNotCallable() async throws {
        let response = await handler(caller: FakeToolCaller()).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(6),
            method: "tools/call",
            params: .object(["name": .string("log_crash"), "arguments": .object([:])])
        ))
        XCTAssertEqual(response?.error?.code, -32602)
    }

    func testToolCallSuccessAndBusinessError() async throws {
        let success = await handler(caller: FakeToolCaller(result: .object(["ok": .bool(true)]))).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(4),
            method: "tools/call",
            params: .object(["name": .string("device_list"), "arguments": .object([:])])
        ))
        XCTAssertEqual(success?.result?["isError"], .bool(false))
        XCTAssertEqual(success?.result?["structuredContent"]?["ok"], .bool(true))

        let failure = await handler(caller: FakeToolCaller(error: .invalidArgument("bad"))).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(5),
            method: "tools/call",
            params: .object(["name": .string("device_list"), "arguments": .object([:])])
        ))
        XCTAssertEqual(failure?.result?["isError"], .bool(true))
        XCTAssertEqual(failure?.result?["structuredContent"]?["error"]?["code"], .string("invalid_argument"))
    }

    func testNotificationHasNoResponse() async throws {
        let response = await handler(caller: FakeToolCaller()).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: nil,
            method: "notifications/initialized",
            params: nil
        ))
        XCTAssertNil(response)
    }

    func testMethodNotFound() async throws {
        let response = await handler(caller: FakeToolCaller()).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(7),
            method: "resources/list",
            params: nil
        ))
        XCTAssertEqual(response?.error?.code, -32601)
    }
}
