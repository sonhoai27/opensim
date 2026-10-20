import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class SimctlRuntimeServiceTests: XCTestCase {
    func testListRuntimesParsesPlatformAndBuild() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("""
        {"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","buildversion":"24A434","isAvailable":true,"platform":"iOS","bundlePath":"/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.0.simruntime"}]}
        """))
        let service = SimctlRuntimeService(executor: executor, timeout: .seconds(5))
        let runtimes = try await service.listRuntimes()
        XCTAssertEqual(runtimes.count, 1)
        XCTAssertEqual(runtimes[0].platform, .iOS)
        XCTAssertEqual(runtimes[0].build, "24A434")
        XCTAssertEqual(runtimes[0].version, "27.0")
    }

    func testInstallRuntimeDiffsRuntimeList() async throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("iOS.dmg")
        try Data("runtime".utf8).write(to: image)

        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("""
        {"runtimes":[]}
        """))
        await executor.enqueue(jsonOutput(""))
        await executor.enqueue(jsonOutput("""
        {"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","buildversion":"24A434","isAvailable":true,"platform":"iOS","bundlePath":"/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.0.simruntime"}]}
        """))
        let service = SimctlRuntimeService(executor: executor, timeout: .seconds(5))
        let runtime = try await service.installRuntime(at: image.path)
        XCTAssertEqual(runtime.id, RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"))
        let commands = await executor.commands
        XCTAssertEqual(commands.map(\.arguments), [
            ["list", "runtimes", "-j"],
            ["runtime", "add", image.path],
            ["list", "runtimes", "-j"],
        ])
    }

    func testDeleteRuntimeUsesRuntimeDelete() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(""))
        let service = SimctlRuntimeService(executor: executor, timeout: .seconds(5))
        try await service.deleteRuntime(RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"))
        let commands = await executor.commands
        XCTAssertEqual(commands[0].arguments, ["runtime", "delete", "com.apple.CoreSimulator.SimRuntime.iOS-27-0"])
    }
}
