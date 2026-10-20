import Foundation
import OpenSimCore

public actor SessionManager {
    private var sessions: [SessionID: Session] = [:]
    private let now: @Sendable () -> Date
    private let idGenerator: @Sendable () -> SessionID

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> SessionID = { SessionID(UUID().uuidString) }
    ) {
        self.now = now
        self.idGenerator = idGenerator
    }

    public func create(clientKind: String, clientName: String) -> Session {
        let timestamp = now()
        let session = Session(
            id: idGenerator(),
            clientKind: clientKind,
            clientName: clientName,
            createdAt: timestamp,
            lastSeenAt: timestamp
        )
        sessions[session.id] = session
        return session
    }

    public func close(_ id: SessionID) -> Bool {
        sessions.removeValue(forKey: id) != nil
    }

    public func list() -> [Session] {
        sessions.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func session(_ id: SessionID) -> Session? {
        sessions[id]
    }

    public func touch(_ id: SessionID) -> Session? {
        guard var session = sessions[id] else {
            return nil
        }
        session.lastSeenAt = now()
        sessions[id] = session
        return session
    }
}
