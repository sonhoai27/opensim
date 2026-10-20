import Foundation

public struct ResponseMeta: Codable, Sendable, Equatable {
    public var requestId: String
    public var durationMs: Int

    public init(requestId: String, durationMs: Int) {
        self.requestId = requestId
        self.durationMs = durationMs
    }
}

public struct EmptyPayload: Codable, Sendable, Equatable {
    public init() {}
}

public struct Envelope<T: Codable & Sendable>: Codable, Sendable {
    public var schemaVersion: Int
    public var ok: Bool
    public var data: T?
    public var error: OpenSimError?
    public var meta: ResponseMeta

    public init(
        schemaVersion: Int = 1,
        ok: Bool,
        data: T?,
        error: OpenSimError?,
        meta: ResponseMeta
    ) {
        self.schemaVersion = schemaVersion
        self.ok = ok
        self.data = data
        self.error = error
        self.meta = meta
    }

    public static func success(_ data: T, requestId: String, durationMs: Int) -> Envelope<T> {
        Envelope(
            ok: true,
            data: data,
            error: nil,
            meta: ResponseMeta(requestId: requestId, durationMs: durationMs)
        )
    }

    public static func failure(_ error: OpenSimError, requestId: String, durationMs: Int) -> Envelope<T> {
        Envelope(
            ok: false,
            data: nil,
            error: error,
            meta: ResponseMeta(requestId: requestId, durationMs: durationMs)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(ok, forKey: .ok)
        try container.encode(data, forKey: .data)
        try container.encode(error, forKey: .error)
        try container.encode(meta, forKey: .meta)
    }
}

public enum RequestID {
    public static func make() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
    }
}
