import ArgumentParser
import XCTest
@testable import OpenSimCLI
@testable import OpenSimCore

final class CatalogCLIParityTests: XCTestCase {
    private let localOnlyPaths = ["log/stream"]

    private var leafPaths: Set<String> {
        OpenSimCommand.configuration.subcommands.reduce(into: Set<String>()) { result, subcommand in
            result.formUnion(collect(subcommand, prefix: []))
        }
    }

    func testEveryCatalogOperationHasCLICommand() {
        let paths = leafPaths
        for operation in OperationCatalog.plan3().mcpOperations() {
            XCTAssertTrue(
                paths.contains(operation.cliPath.joined(separator: "/")),
                "Missing CLI command for \(operation.mcpName): \(operation.cliPath)"
            )
        }
    }

    func testEveryCLILeafIsCatalogBackedOrDaemonControl() {
        let catalogPaths = Set(
            OperationCatalog.plan3().operations.values.map { $0.cliPath.joined(separator: "/") }
        )
        let unmanaged = leafPaths.filter { !catalogPaths.contains($0) && !localOnlyPaths.contains($0) }
        for path in unmanaged {
            XCTAssertTrue(
                path.hasPrefix("daemon/") || path == "mcp",
                "CLI command without catalog entry: \(path)"
            )
        }
    }

    private func collect(_ command: any ParsableCommand.Type, prefix: [String]) -> Set<String> {
        let configuration = command.configuration
        let path = prefix + [configuration.commandName ?? "\(command)"]
        if configuration.subcommands.isEmpty {
            return [path.joined(separator: "/")]
        }
        return configuration.subcommands.reduce(into: Set<String>()) { result, subcommand in
            result.formUnion(collect(subcommand, prefix: path))
        }
    }
}
