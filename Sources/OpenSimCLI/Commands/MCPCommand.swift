import ArgumentParser
import Foundation
import OpenSimCore
import OpenSimDaemon
import OpenSimMCP
import OpenSimProtocol

public struct MCPCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Run the MCP server for AI agents"
    )

    @Flag(name: .long, help: "Serve JSON-RPC over stdin/stdout")
    public var stdio: Bool = false

    @Flag(name: .long, help: "Report the daemon MCP HTTP endpoint instead of serving stdio")
    public var http: Bool = false

    public init() {}

    public func run() async throws {
        guard stdio != http else {
            throw OpenSimError.invalidArgument("Choose exactly one of --stdio or --http")
        }
        let paths = OpenSimPaths()
        let client = try await DaemonLauncher(paths: paths).ensureRunning()
        let catalog = OperationCatalog.plan3()
        if stdio {
            let session = MCPToolSession(client: client, catalog: catalog)
            let handler = MCPHandler(
                catalog: catalog,
                caller: session,
                serverVersion: OpenSimVersion.version
            )
            await StdioTransport(handler: handler).run()
            await session.close()
            return
        }
        let state = try DaemonStateStore(paths: paths).read()
        print("http://127.0.0.1:\(state.port)/mcp")
    }
}
