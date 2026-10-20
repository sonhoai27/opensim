import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimCore

final class SSETests: XCTestCase {
    func testFrameContainsIDEventAndData() throws {
        let event = DaemonEvent(
            id: "42",
            type: .deviceStateChanged,
            timestamp: Date(timeIntervalSince1970: 1_797_000_000),
            data: try JSONValue.from(DeviceStateChangedPayload(
                deviceID: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
                state: .booted,
                previousState: .booting
            ))
        )
        let frame = try SSEFrame.encode(event)
        XCTAssertTrue(frame.hasPrefix("id: 42\n"))
        XCTAssertTrue(frame.contains("event: device.state.changed\n"))
        XCTAssertTrue(frame.contains("data: {"))
        XCTAssertTrue(frame.hasSuffix("\n\n"))
    }

    func testEventHubReconnectReplay() async throws {
        let hub = EventHub()
        for index in 0..<3 {
            _ = try await hub.publish(
                type: .daemonHealth,
                payload: DaemonHealthPayload(status: "ok", pid: Int32(index), port: 5000 + index)
            )
        }
        let (initial, stream) = await hub.subscribe(after: "1")
        XCTAssertEqual(initial.map(\.id), ["2", "3"])
        let (empty, secondStream) = await hub.subscribe(after: nil)
        XCTAssertTrue(empty.isEmpty)
        var iterator = secondStream.makeAsyncIterator()
        let next = try await hub.publish(type: .daemonHealth, payload: DaemonHealthPayload(status: "ok", pid: 9, port: 6000))
        let received = await iterator.next()
        XCTAssertEqual(received?.id, next.id)
        _ = stream
    }

    func testEventStreamReplaysBufferedEventsOverHTTP() async throws {
        let harness = try await RouteTestHarness.start(executor: DaemonStubSimctlExecutor())
        defer { harness.server.stop() }
        _ = try await harness.services.events.publish(
            type: .daemonHealth,
            payload: DaemonHealthPayload(status: "ok", pid: 7, port: 5555)
        )

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(harness.server.port)/v1/events")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(harness.token)", forHTTPHeaderField: "Authorization")
        request.setValue("0", forHTTPHeaderField: "Last-Event-ID")

        let (bytes, response) = try await URLSession(configuration: configuration).bytes(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"), "text/event-stream")

        var received: [String] = []
        for try await line in bytes.lines {
            received.append(line)
            if line.hasPrefix("data: ") {
                break
            }
        }
        XCTAssertEqual(received.first, "id: 1")
        XCTAssertTrue(received.contains("event: daemon.health"))
        XCTAssertTrue(received.contains { $0.hasPrefix("data: {") })
    }
}
