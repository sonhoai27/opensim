import Hummingbird
import OpenSimProtocol

public enum OperationRoutes {
    public static func register(on router: Router<BasicRequestContext>, services: DaemonServices) {
        router.post("/v1/operations") { request, _ in
            let body = try await DaemonHTTP.decode(request, as: OperationRequest.self)
            let result = try await services.dispatcher.dispatch(body)
            return try DaemonHTTP.json(result)
        }
    }
}
