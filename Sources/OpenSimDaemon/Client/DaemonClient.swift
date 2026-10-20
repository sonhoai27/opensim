import Foundation
import OpenSimCore
import OpenSimProtocol

public struct DaemonClient: Sendable {
    public let baseURL: URL
    public let token: String
    private let session: URLSession
    private let streamSession: URLSession

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: configuration)

        // An SSE response stays open while the device is idle, so the idle timeout that is
        // right for request/response calls would drop the stream.
        let streaming = URLSessionConfiguration.ephemeral
        streaming.timeoutIntervalForRequest = 24 * 60 * 60
        streaming.timeoutIntervalForResource = 24 * 60 * 60
        self.streamSession = URLSession(configuration: streaming)
    }

    public init(state: DaemonState) {
        self.init(baseURL: URL(string: "http://127.0.0.1:\(state.port)")!, token: state.token)
    }

    public func health() async throws -> HealthResponse {
        try await request(method: "GET", path: "/v1/health", body: Optional<EmptyPayload>.none, as: HealthResponse.self)
    }

    public func devices() async throws -> [Device] {
        try await request(method: "GET", path: "/v1/devices", body: Optional<EmptyPayload>.none, as: [Device].self)
    }

    public func operation(_ operation: OperationRequest) async throws -> OperationResult {
        try await request(method: "POST", path: "/v1/operations", body: operation, as: OperationResult.self)
    }

    public func createSession(clientKind: String, clientName: String) async throws -> Session {
        try await request(
            method: "POST",
            path: "/v1/sessions",
            body: CreateSessionRequest(clientKind: clientKind, clientName: clientName),
            as: Session.self
        )
    }

    public func closeSession(_ id: SessionID) async throws {
        _ = try await rawRequest(method: "DELETE", path: "/v1/sessions/\(id.rawValue)", body: nil)
    }

    public func acquireLease(_ request: AcquireLeaseRequest) async throws -> Lease {
        try await self.request(method: "POST", path: "/v1/leases", body: request, as: Lease.self)
    }

    public func heartbeatLease(_ id: LeaseID, sessionID: SessionID, ttlSeconds: Int?) async throws -> Lease {
        try await request(
            method: "POST",
            path: "/v1/leases/\(id.rawValue)/heartbeat",
            body: HeartbeatRequest(sessionID: sessionID, ttlSeconds: ttlSeconds),
            as: Lease.self
        )
    }

    public func releaseLease(_ id: LeaseID, sessionID: SessionID) async throws -> LeaseReleaseResult {
        try await request(
            method: "DELETE",
            path: "/v1/leases/\(id.rawValue)?sessionID=\(sessionID.rawValue)",
            body: Optional<EmptyPayload>.none,
            as: LeaseReleaseResult.self
        )
    }

    public func events(lastEventID: String? = nil) -> AsyncThrowingStream<DaemonEvent, Error> {
        AsyncThrowingStream { continuation in
            let token = self.token
            let url = try? self.makeURL(path: "/v1/events")
            let task = Task {
                do {
                    guard let url else {
                        throw OpenSimError.invalidArgument("Invalid events URL")
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    if let lastEventID {
                        request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
                    }
                    let (bytes, response) = try await self.streamSession.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw OpenSimError.daemonUnavailable("SSE endpoint returned an error status")
                    }
                    for try await line in bytes.lines where line.hasPrefix("data: ") {
                        // SSEFrame.encode writes one JSON object per data line, so a data line is a
                        // complete frame; the blank terminator is not delivered until the next event.
                        let payload = Data(line.dropFirst(6).utf8)
                        continuation.yield(try OpenSimJSON.decoder().decode(DaemonEvent.self, from: payload))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func request<Body: Encodable, T: Codable & Sendable>(
        method: String,
        path: String,
        body: Body?,
        as type: T.Type
    ) async throws -> T {
        let data = try await rawRequest(
            method: method,
            path: path,
            body: body.map { try OpenSimJSON.encoder(pretty: false).encode($0) }
        )
        let envelope = try OpenSimJSON.decoder().decode(Envelope<T>.self, from: data)
        guard envelope.ok, let value = envelope.data else {
            throw envelope.error ?? OpenSimError.daemonUnavailable("Daemon returned an empty response")
        }
        return value
    }

    private func rawRequest(method: String, path: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenSimError.daemonUnavailable("Daemon returned a non-HTTP response")
            }
            if http.statusCode >= 400 {
                if let envelope = try? OpenSimJSON.decoder().decode(Envelope<EmptyPayload>.self, from: data),
                   let error = envelope.error {
                    throw error
                }
                throw OpenSimError.daemonUnavailable("Daemon returned HTTP \(http.statusCode)")
            }
            return data
        } catch let error as OpenSimError {
            throw error
        } catch {
            throw OpenSimError.daemonUnavailable(String(describing: error))
        }
    }

    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw OpenSimError.invalidArgument("Invalid daemon path: \(path)")
        }
        return url
    }
}
