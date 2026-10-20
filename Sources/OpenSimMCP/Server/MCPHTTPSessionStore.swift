import Foundation
import OpenSimCore
import OpenSimDaemon
import OpenSimProtocol

public actor MCPHTTPSessionStore {
    private struct StoredSession: Sendable {
        var handler: MCPHandler
        var tool: MCPToolSession
    }

    private let catalog: OperationCatalog
    private let baseURL: URL
    private let token: String
    private var sessions: [String: StoredSession] = [:]

    public init(catalog: OperationCatalog, baseURL: URL, token: String) {
        self.catalog = catalog
        self.baseURL = baseURL
        self.token = token
    }

    public func create(clientName: String) -> (id: String, handler: MCPHandler) {
        let client = DaemonClient(baseURL: baseURL, token: token)
        let tool = MCPToolSession(client: client, catalog: catalog, clientName: clientName)
        let handler = MCPHandler(catalog: catalog, caller: tool, serverVersion: OpenSimVersion.version)
        let id = UUID().uuidString
        sessions[id] = StoredSession(handler: handler, tool: tool)
        return (id, handler)
    }

    public func handler(for id: String) -> MCPHandler? {
        sessions[id]?.handler
    }

    public func close(id: String) async {
        guard let stored = sessions.removeValue(forKey: id) else {
            return
        }
        await stored.tool.close()
    }

    public func sessionCount() -> Int {
        sessions.count
    }
}
