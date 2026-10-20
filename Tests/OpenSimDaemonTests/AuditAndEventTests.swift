import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimCore

final class AuditAndEventTests: XCTestCase {
    func testAuditWriterRotatesAtMaxBytes() async throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("audit.jsonl")
        let writer = AuditWriter(fileURL: file, maxBytes: 350)
        for index in 0..<10 {
            let event = AuditEvent(
                id: "audit-\(index)",
                timestamp: Date(timeIntervalSince1970: Double(index)),
                actor: "agent",
                sessionID: SessionID("session-1"),
                leaseID: nil,
                action: "device_boot",
                target: "udid",
                result: "ok",
                durationMs: index
            )
            try await writer.append(event)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path + ".1"))
    }

    func testEventHubReplaysAfterID() async throws {
        let hub = EventHub()
        let payload = DeviceStateChangedPayload(
            deviceID: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            state: .booted,
            previousState: .booting
        )
        let first = try await hub.publish(type: .deviceStateChanged, payload: payload)
        let second = try await hub.publish(type: .deviceStateChanged, payload: payload)
        XCTAssertEqual(first.id, "1")
        XCTAssertEqual(second.id, "2")

        let (initial, _) = await hub.subscribe(after: "1")
        XCTAssertEqual(initial.map(\.id), ["2"])

        let (emptyInitial, stream) = await hub.subscribe(after: nil)
        XCTAssertTrue(emptyInitial.isEmpty)
        let third = try await hub.publish(type: .leaseChanged, payload: LeaseChangedPayload(
            lease: Lease(
                id: LeaseID("lease-1"),
                deviceID: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
                sessionID: SessionID("session-1"),
                mode: .control,
                ownerName: "agent",
                acquiredAt: Date(timeIntervalSince1970: 1),
                expiresAt: Date(timeIntervalSince1970: 2)
            ),
            reason: "acquired"
        ))
        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertEqual(received?.id, third.id)
        let count = await hub.eventCount()
        XCTAssertEqual(count, 3)
    }
}
