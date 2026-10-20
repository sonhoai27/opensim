import XCTest
import OpenSimMCP
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimCore
@testable import OpenSimBridge

final class MCPHTTPTests: XCTestCase {
    private func post(
        _ request: JSONRPCRequest,
        sessionID: String?,
        baseURL: URL,
        token: String
    ) async throws -> (HTTPURLResponse, Data) {
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let sessionID {
            urlRequest.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        urlRequest.httpBody = try OpenSimJSON.encoder(pretty: false).encode(request)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        return (try XCTUnwrap(response as? HTTPURLResponse), data)
    }

    private func initializeSession(
        baseURL: URL,
        token: String,
        clientName: String = "mcp-test"
    ) async throws -> String {
        let request = JSONRPCRequest(
            id: .number(1),
            method: "initialize",
            params: .object([
                "protocolVersion": .string("2025-06-18"),
                "clientInfo": .object(["name": .string(clientName)]),
            ])
        )
        let (response, data) = try await post(request, sessionID: nil, baseURL: baseURL, token: token)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(try JSONDecoder().decode(JSONRPCResponse.self, from: data).result?["protocolVersion"], .string("2025-06-18"))
        return try XCTUnwrap(response.value(forHTTPHeaderField: "Mcp-Session-Id"))
    }

    func testInitializeReturnsSessionIDAndToolsListUsesIt() async throws {
        let harness = try await RouteTestHarness.start(
            executor: DaemonStubSimctlExecutor(),
            routeProviders: [MCPRouteProvider(catalog: .plan3())]
        )
        defer { harness.server.stop() }
        let base = URL(string: "http://127.0.0.1:\(harness.server.port)/mcp")!
        let sessionID = try await initializeSession(baseURL: base, token: harness.token)

        let (listResponse, listData) = try await post(
            JSONRPCRequest(id: .number(2), method: "tools/list", params: nil),
            sessionID: sessionID,
            baseURL: base,
            token: harness.token
        )
        XCTAssertEqual(listResponse.statusCode, 200)
        XCTAssertEqual(listResponse.value(forHTTPHeaderField: "Mcp-Session-Id"), sessionID)
        let listed = try JSONDecoder().decode(JSONRPCResponse.self, from: listData)
        let tools = try XCTUnwrap(listed.result?["tools"]?.arrayValue)
        let names = Set(tools.compactMap { $0["name"]?.stringValue })
        XCTAssertTrue(names.contains("ui_tap"))
        XCTAssertTrue(names.contains("session_acquire"))
    }

    func testRequestWithoutSessionHeaderIsRejected() async throws {
        let harness = try await RouteTestHarness.start(
            executor: DaemonStubSimctlExecutor(),
            routeProviders: [MCPRouteProvider(catalog: .plan3())]
        )
        defer { harness.server.stop() }
        let (response, data) = try await post(
            JSONRPCRequest(id: .number(3), method: "tools/list", params: nil),
            sessionID: nil,
            baseURL: URL(string: "http://127.0.0.1:\(harness.server.port)/mcp")!,
            token: harness.token
        )
        XCTAssertEqual(response.statusCode, 400)
        let error = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        XCTAssertEqual(error.error?.code, -32600)
    }

    func testMalformedBodyIsParseError() async throws {
        let harness = try await RouteTestHarness.start(
            executor: DaemonStubSimctlExecutor(),
            routeProviders: [MCPRouteProvider(catalog: .plan3())]
        )
        defer { harness.server.stop() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(harness.server.port)/mcp")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(harness.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("not json".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 400)
        XCTAssertEqual(
            try JSONDecoder().decode(JSONRPCResponse.self, from: data).error?.code,
            JSONRPCErrorCode.parseError
        )
    }

    func testDeleteClosesSessionAndRejectsLaterRequests() async throws {
        let harness = try await RouteTestHarness.start(
            executor: DaemonStubSimctlExecutor(),
            routeProviders: [MCPRouteProvider(catalog: .plan3())]
        )
        defer { harness.server.stop() }
        let base = URL(string: "http://127.0.0.1:\(harness.server.port)/mcp")!
        let sessionID = try await initializeSession(baseURL: base, token: harness.token)

        var delete = URLRequest(url: base)
        delete.httpMethod = "DELETE"
        delete.setValue("Bearer \(harness.token)", forHTTPHeaderField: "Authorization")
        delete.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        let (_, deleteResponse) = try await URLSession.shared.data(for: delete)
        XCTAssertEqual((deleteResponse as? HTTPURLResponse)?.statusCode, 200)

        let (response, _) = try await post(
            JSONRPCRequest(id: .number(4), method: "tools/list", params: nil),
            sessionID: sessionID,
            baseURL: base,
            token: harness.token
        )
        XCTAssertEqual(response.statusCode, 400)
    }

    func testEventStreamDeliversNotificationFrame() async throws {
        let harness = try await RouteTestHarness.start(
            executor: DaemonStubSimctlExecutor(),
            routeProviders: [MCPRouteProvider(catalog: .plan3())]
        )
        defer { harness.server.stop() }
        let sessionID = try await initializeSession(
            baseURL: URL(string: "http://127.0.0.1:\(harness.server.port)/mcp")!,
            token: harness.token
        )
        _ = try await harness.services.events.publish(
            type: .daemonHealth,
            payload: DaemonHealthPayload(status: "ok", pid: 5, port: 4000)
        )

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(harness.server.port)/mcp")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(harness.token)", forHTTPHeaderField: "Authorization")
        request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        request.setValue("0", forHTTPHeaderField: "Last-Event-ID")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"), "text/event-stream")

        var lines: [String] = []
        for try await line in bytes.lines {
            lines.append(line)
            if line.hasPrefix("data: ") {
                break
            }
        }
        let payload = try XCTUnwrap(lines.first { $0.hasPrefix("data: ") }?.dropFirst(6))
        let notification = try JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8))
        XCTAssertEqual(notification["method"]?.stringValue, "notifications/message")
        XCTAssertEqual(notification["params"]?["data"]?["type"]?.stringValue, "daemon.health")
    }
}
