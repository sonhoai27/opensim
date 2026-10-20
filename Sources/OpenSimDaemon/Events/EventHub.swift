import Foundation
import OpenSimCore
import OpenSimProtocol

public actor EventHub {
    private var nextID = 1
    private var buffer: [DaemonEvent] = []
    private var subscribers: [UUID: AsyncStream<DaemonEvent>.Continuation] = [:]
    private let maxBuffer = 256
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func publish<T: Encodable & Sendable>(type: EventType, payload: T) throws -> DaemonEvent {
        let event = DaemonEvent(
            id: "\(nextID)",
            type: type,
            timestamp: now(),
            data: try JSONValue.from(payload)
        )
        nextID += 1
        buffer.append(event)
        if buffer.count > maxBuffer {
            buffer.removeFirst(buffer.count - maxBuffer)
        }
        for continuation in subscribers.values {
            continuation.yield(event)
        }
        return event
    }

    public func subscribe(
        after lastEventID: String?
    ) -> (initial: [DaemonEvent], stream: AsyncStream<DaemonEvent>) {
        let initial = lastEventID == nil ? [] : replay(after: lastEventID)
        let (stream, continuation) = AsyncStream<DaemonEvent>.makeStream()
        let identifier = UUID()
        subscribers[identifier] = continuation
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeSubscriber(identifier)
            }
        }
        return (initial, stream)
    }

    public func replay(after lastEventID: String?) -> [DaemonEvent] {
        guard let lastEventID, let last = Int(lastEventID) else {
            return buffer
        }
        return buffer.filter { event in
            guard let identifier = Int(event.id) else {
                return false
            }
            return identifier > last
        }
    }

    public func eventCount() -> Int {
        buffer.count
    }

    private func removeSubscriber(_ identifier: UUID) {
        subscribers.removeValue(forKey: identifier)
    }
}
