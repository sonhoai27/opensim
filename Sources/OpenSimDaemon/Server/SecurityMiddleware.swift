import Foundation
import Hummingbird
import OpenSimCore

public enum RequestSecurity {
    private static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]

    public static func isLoopbackHost(_ header: String?) -> Bool {
        guard let header, !header.isEmpty else {
            return false
        }
        let host: String
        if header.hasPrefix("[") {
            let end = header.firstIndex(of: "]") ?? header.endIndex
            host = String(header[header.index(after: header.startIndex)..<end])
        } else {
            host = header.split(separator: ":").first.map(String.init) ?? header
        }
        return loopbackHosts.contains(host.lowercased())
    }

    public static func isAllowedOrigin(_ header: String?) -> Bool {
        guard let header, !header.isEmpty else {
            return true
        }
        guard let url = URL(string: header),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme),
              let host = url.host else {
            return false
        }
        return loopbackHosts.contains(host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")))
    }

    public static func isAuthorized(_ header: String?, token: String) -> Bool {
        guard let header, !token.isEmpty else {
            return false
        }
        return header == "Bearer \(token)"
    }
}

public struct SecurityMiddleware: RouterMiddleware {
    public typealias Context = BasicRequestContext
    private let token: String

    public init(token: String) {
        self.token = token
    }

    public func handle(
        _ request: Request,
        context: BasicRequestContext,
        next: (Request, BasicRequestContext) async throws -> Response
    ) async throws -> Response {
        guard RequestSecurity.isLoopbackHost(request.head.authority) else {
            return DaemonHTTP.envelopeError(
                OpenSimError(code: .permissionDenied, message: "Host is not loopback"),
                status: .forbidden
            )
        }
        guard RequestSecurity.isAllowedOrigin(request.headers[.origin]) else {
            return DaemonHTTP.envelopeError(
                OpenSimError(code: .permissionDenied, message: "Origin is not loopback"),
                status: .forbidden
            )
        }
        if request.uri.path == "/v1/health" {
            return try await next(request, context)
        }
        guard RequestSecurity.isAuthorized(request.headers[.authorization], token: token) else {
            return DaemonHTTP.envelopeError(
                OpenSimError(code: .permissionDenied, message: "Missing or invalid bearer token"),
                status: .unauthorized
            )
        }
        return try await next(request, context)
    }
}
