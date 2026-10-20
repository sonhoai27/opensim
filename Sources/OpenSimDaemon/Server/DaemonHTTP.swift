import Foundation
import Hummingbird
import NIOCore
import OpenSimCore
import OpenSimProtocol

public enum DaemonHTTP {
    public static func json<T: Codable & Sendable>(
        _ value: T,
        status: HTTPResponse.Status = .ok
    ) throws -> Response {
        let envelope = Envelope<T>.success(value, requestId: RequestID.make(), durationMs: 0)
        let data = try OpenSimJSON.encoder(pretty: false).encode(envelope)
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: [UInt8](data)))
        )
    }

    public static func envelopeError(_ error: OpenSimError, status: HTTPResponse.Status) -> Response {
        let envelope = Envelope<EmptyPayload>.failure(error, requestId: RequestID.make(), durationMs: 0)
        let data = (try? OpenSimJSON.encoder(pretty: false).encode(envelope)) ?? Data()
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: [UInt8](data)))
        )
    }

    public static func decode<T: Decodable>(_ request: Request, as type: T.Type) async throws -> T {
        let buffer = try await request.body.collect(upTo: 8 * 1_024 * 1_024)
        return try OpenSimJSON.decoder().decode(T.self, from: Data(buffer.readableBytesView))
    }

    public static func status(for error: OpenSimError) -> HTTPResponse.Status {
        switch error.code {
        case ErrorCode.invalidArgument.rawValue, ErrorCode.confirmationRequired.rawValue:
            return .badRequest
        case ErrorCode.deviceNotFound.rawValue:
            return .notFound
        case ErrorCode.deviceBusy.rawValue,
             ErrorCode.leaseRequired.rawValue,
             ErrorCode.leaseConflict.rawValue,
             ErrorCode.leaseRevoked.rawValue,
             ErrorCode.storageInUse.rawValue:
            return .conflict
        case ErrorCode.permissionDenied.rawValue:
            return .forbidden
        case ErrorCode.capabilityUnavailable.rawValue,
             ErrorCode.privateApiUnavailable.rawValue,
             ErrorCode.a11yUnavailable.rawValue,
             ErrorCode.unsupportedXcode.rawValue:
            return .notImplemented
        case ErrorCode.daemonUnavailable.rawValue:
            return .serviceUnavailable
        default:
            return .internalServerError
        }
    }
}
