import Foundation
import OpenSimCore
import OpenSimProtocol

public struct StdioTransport: Sendable {
    private let handler: MCPHandler

    public init(handler: MCPHandler) {
        self.handler = handler
    }

    public func run() async {
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                if let output = await handleLine(line) {
                    FileHandle.standardOutput.write(Data((output + "\n").utf8))
                }
            }
        } catch {
            FileHandle.standardError.write(Data("stdio read failed: \(error)\n".utf8))
        }
    }

    public func handleLine(_ line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let data = trimmed.data(using: .utf8),
              let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
            return parseErrorResponse()
        }
        guard let response = await handler.handle(request) else {
            return nil
        }
        guard let encoded = try? OpenSimJSON.encoder(pretty: false).encode(response) else {
            return nil
        }
        return String(decoding: encoded, as: UTF8.self)
    }

    private func parseErrorResponse() -> String {
        let response = JSONRPCResponse(
            id: .null,
            result: nil,
            error: JSONRPCError(code: JSONRPCErrorCode.parseError, message: "Parse error")
        )
        let data = (try? OpenSimJSON.encoder(pretty: false).encode(response)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
