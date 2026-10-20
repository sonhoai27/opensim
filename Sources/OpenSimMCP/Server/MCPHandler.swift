import Foundation
import OpenSimCore
import OpenSimProtocol

public protocol MCPToolCalling: Sendable {
    func call(tool: OpenSimCore.Operation, arguments: JSONValue) async throws -> JSONValue
}

public struct MCPHandler: Sendable {
    public static let protocolVersion = "2025-06-18"
    private let catalog: OperationCatalog
    private let caller: any MCPToolCalling
    private let serverVersion: String

    public init(catalog: OperationCatalog, caller: any MCPToolCalling, serverVersion: String) {
        self.catalog = catalog
        self.caller = caller
        self.serverVersion = serverVersion
    }

    public func handle(_ request: JSONRPCRequest) async -> JSONRPCResponse? {
        let identifier = request.id
        guard request.jsonrpc == "2.0" else {
            return errorResponse(id: identifier, error: JSONRPCError(
                code: JSONRPCErrorCode.invalidRequest,
                message: "jsonrpc must be 2.0"
            ))
        }
        switch request.method {
        case "initialize":
            return resultResponse(id: identifier, result: .object([
                "protocolVersion": .string(MCPHandler.protocolVersion),
                "capabilities": .object([
                    "tools": .object(["listChanged": .bool(false)]),
                ]),
                "serverInfo": .object([
                    "name": .string("opensim"),
                    "version": .string(serverVersion),
                ]),
            ]))

        case "notifications/initialized":
            return nil

        case "ping":
            return resultResponse(id: identifier, result: .object([:]))

        case "tools/list":
            let tools = ToolCatalogAdapter.tools(from: catalog).map { tool in
                JSONValue.object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "inputSchema": tool.inputSchema,
                ])
            }
            return resultResponse(id: identifier, result: .object(["tools": .array(tools)]))

        case "tools/call":
            return await handleToolCall(request: request, identifier: identifier)

        default:
            return errorResponse(id: identifier, error: JSONRPCError(
                code: JSONRPCErrorCode.methodNotFound,
                message: "Method not found: \(request.method)"
            ))
        }
    }

    private func handleToolCall(
        request: JSONRPCRequest,
        identifier: JSONRPCID?
    ) async -> JSONRPCResponse? {
        guard let params = request.params?.objectValue,
              let name = params["name"]?.stringValue else {
            return errorResponse(id: identifier, error: JSONRPCError(
                code: JSONRPCErrorCode.invalidParams,
                message: "tools/call requires name"
            ))
        }
        guard let tool = catalog.operation(forMCP: name), tool.mcpExposed else {
            return errorResponse(id: identifier, error: JSONRPCError(
                code: JSONRPCErrorCode.invalidParams,
                message: "Unknown tool: \(name)"
            ))
        }
        let arguments = params["arguments"] ?? .object([:])
        do {
            let value = try await caller.call(tool: tool, arguments: arguments)
            return resultResponse(id: identifier, result: toolResult(value: value, error: nil))
        } catch let error as OpenSimError {
            return resultResponse(id: identifier, result: toolResult(value: nil, error: error))
        } catch {
            let mapped = OpenSimError(code: .internalError, message: String(describing: error))
            return resultResponse(id: identifier, result: toolResult(value: nil, error: mapped))
        }
    }

    private func toolResult(value: JSONValue?, error: OpenSimError?) -> JSONValue {
        if let error {
            let structured = (try? JSONValue.from(error)) ?? .object([:])
            return .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("\(error.code): \(error.message)"),
                    ]),
                ]),
                "structuredContent": .object(["error": structured]),
                "isError": .bool(true),
            ])
        }
        return .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string("ok"),
                ]),
            ]),
            "structuredContent": value ?? .null,
            "isError": .bool(false),
        ])
    }

    private func resultResponse(id: JSONRPCID?, result: JSONValue) -> JSONRPCResponse? {
        guard id != nil else {
            return nil
        }
        return JSONRPCResponse(id: id, result: result, error: nil)
    }

    private func errorResponse(id: JSONRPCID?, error: JSONRPCError) -> JSONRPCResponse? {
        JSONRPCResponse(id: id ?? .null, result: nil, error: error)
    }
}
