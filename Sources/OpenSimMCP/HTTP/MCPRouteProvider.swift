import HTTPTypes
import Hummingbird
import Foundation
import NIOCore
import OpenSimCore
import OpenSimDaemon
import OpenSimProtocol

public struct MCPRouteProvider: DaemonRouteProvider {
    private static let sessionHeaderName = "Mcp-Session-Id"
    private static let lastEventHeaderName = "Last-Event-ID"

    private let catalog: OperationCatalog

    public init(catalog: OperationCatalog) {
        self.catalog = catalog
    }

    public func registerRoutes(
        on router: Router<BasicRequestContext>,
        context: DaemonRouteContext
    ) throws {
        let store = MCPHTTPSessionStore(
            catalog: catalog,
            baseURL: context.baseURL,
            token: context.token
        )
        let events = context.services.events

        router.post("/mcp") { request, _ in
            let rpc: JSONRPCRequest
            do {
                rpc = try await DaemonHTTP.decode(request, as: JSONRPCRequest.self)
            } catch {
                return MCPRouteProvider.errorResponse(
                    status: .badRequest,
                    code: JSONRPCErrorCode.parseError,
                    message: "Parse error"
                )
            }
            if rpc.method == "initialize" {
                let clientName = rpc.params?["clientInfo"]?["name"]?.stringValue ?? "mcp-client"
                let (sessionID, handler) = await store.create(clientName: clientName)
                guard let response = await handler.handle(rpc) else {
                    return Response(status: .accepted)
                }
                return try MCPRouteProvider.jsonResponse(response, sessionID: sessionID)
            }
            guard let sessionID = MCPRouteProvider.header(request, MCPRouteProvider.sessionHeaderName),
                  let handler = await store.handler(for: sessionID) else {
                return MCPRouteProvider.errorResponse(
                    status: .badRequest,
                    code: JSONRPCErrorCode.invalidRequest,
                    message: "Mcp-Session-Id is required"
                )
            }
            guard let response = await handler.handle(rpc) else {
                return Response(status: .accepted)
            }
            return try MCPRouteProvider.jsonResponse(response, sessionID: sessionID)
        }

        router.get("/mcp") { request, _ in
            guard let sessionID = MCPRouteProvider.header(request, MCPRouteProvider.sessionHeaderName) else {
                return MCPRouteProvider.errorResponse(
                    status: .badRequest,
                    code: JSONRPCErrorCode.invalidRequest,
                    message: "Mcp-Session-Id is required"
                )
            }
            guard await store.handler(for: sessionID) != nil else {
                return MCPRouteProvider.errorResponse(
                    status: .badRequest,
                    code: JSONRPCErrorCode.invalidRequest,
                    message: "Unknown Mcp-Session-Id"
                )
            }
            let (initial, stream) = await events.subscribe(
                after: MCPRouteProvider.header(request, MCPRouteProvider.lastEventHeaderName)
            )
            return MCPRouteProvider.sseResponse(initial: initial, stream: stream)
        }

        router.delete("/mcp") { request, _ in
            guard let sessionID = MCPRouteProvider.header(request, MCPRouteProvider.sessionHeaderName) else {
                return MCPRouteProvider.errorResponse(
                    status: .badRequest,
                    code: JSONRPCErrorCode.invalidRequest,
                    message: "Mcp-Session-Id is required"
                )
            }
            await store.close(id: sessionID)
            return Response(status: .ok)
        }
    }

    private static func header(_ request: Request, _ name: String) -> String? {
        guard let field = HTTPField.Name(name) else {
            return nil
        }
        return request.headers[field]
    }

    private static func jsonResponse(_ response: JSONRPCResponse, sessionID: String?) throws -> Response {
        let data = try OpenSimJSON.encoder(pretty: false).encode(response)
        var httpResponse = Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: [UInt8](data)))
        )
        if let sessionID, let field = HTTPField.Name(sessionHeaderName) {
            httpResponse.headers[field] = sessionID
        }
        return httpResponse
    }

    private static func errorResponse(
        status: HTTPResponse.Status,
        code: Int,
        message: String
    ) -> Response {
        let response = JSONRPCResponse(
            id: .null,
            result: nil,
            error: JSONRPCError(code: code, message: message)
        )
        let data = (try? OpenSimJSON.encoder(pretty: false).encode(response)) ?? Data()
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: [UInt8](data)))
        )
    }

    private static func sseResponse(initial: [DaemonEvent], stream: AsyncStream<DaemonEvent>) -> Response {
        let body = AsyncThrowingStream<ByteBuffer, Error> { continuation in
            let task = Task {
                do {
                    for event in initial {
                        continuation.yield(ByteBuffer(string: try notificationFrame(event)))
                    }
                    for await event in stream {
                        continuation.yield(ByteBuffer(string: try notificationFrame(event)))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        return Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache",
            ],
            body: .init(asyncSequence: body)
        )
    }

    private static func notificationFrame(_ event: DaemonEvent) throws -> String {
        let payload = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "method": .string("notifications/message"),
            "params": .object([
                "level": .string("info"),
                "data": try JSONValue.from(event),
            ]),
        ])
        let data = try OpenSimJSON.encoder(pretty: false).encode(payload)
        return "id: \(event.id)\ndata: \(String(decoding: data, as: UTF8.self))\n\n"
    }
}
