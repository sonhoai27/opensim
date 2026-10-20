import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

actor FakeRuntimeDownloader: RuntimeDownloading {
    private(set) var calls: [(Platform, String)] = []

    func download(platform: Platform, version: String) async throws {
        calls.append((platform, version))
    }
}

final class RuntimeDownloadTests: XCTestCase {
    func testDownloadCallsDownloaderAndReturnsMatchingRuntime() async throws {
        let stub = StubSimctlExecutor()
        await stub.enqueue(jsonOutput("""
        {"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-4","name":"iOS 26.4","version":"26.4","buildversion":"23E200","isAvailable":true,"platform":"iOS","bundlePath":"/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.4.simruntime"}]}
        """))
        let downloader = FakeRuntimeDownloader()
        let service = SimctlRuntimeService(
            executor: stub,
            timeout: .seconds(5),
            downloader: downloader
        )
        let runtime = try await service.downloadRuntime(platform: .iOS, version: "26.4")
        XCTAssertEqual(runtime.id, RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-26-4"))
        XCTAssertEqual(runtime.version, "26.4")
        let calls = await downloader.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].0, .iOS)
        XCTAssertEqual(calls[0].1, "26.4")
    }

    func testDownloadWithoutMatchingRuntimeFails() async throws {
        let stub = StubSimctlExecutor()
        await stub.enqueue(jsonOutput("{\"runtimes\":[]}"))
        let downloader = FakeRuntimeDownloader()
        let service = SimctlRuntimeService(
            executor: stub,
            timeout: .seconds(5),
            downloader: downloader
        )
        do {
            _ = try await service.downloadRuntime(platform: .iOS, version: "26.4")
            XCTFail("expected runtime_version_unavailable")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, ErrorCode.runtimeVersionUnavailable.rawValue)
        }
    }
}
