import Hummingbird
import OpenSimCore

public struct ErrorEnvelopeMiddleware: RouterMiddleware {
    public typealias Context = BasicRequestContext

    public init() {}

    public func handle(
        _ request: Request,
        context: BasicRequestContext,
        next: (Request, BasicRequestContext) async throws -> Response
    ) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as OpenSimError {
            return DaemonHTTP.envelopeError(error, status: DaemonHTTP.status(for: error))
        } catch {
            return DaemonHTTP.envelopeError(
                OpenSimError(code: .internalError, message: String(describing: error)),
                status: .internalServerError
            )
        }
    }
}
