import Foundation
import Hummingbird

public struct DaemonRouteContext: Sendable {
    public var services: DaemonServices
    public var token: String
    public var baseURL: URL

    public init(services: DaemonServices, token: String, baseURL: URL) {
        self.services = services
        self.token = token
        self.baseURL = baseURL
    }
}

public protocol DaemonRouteProvider: Sendable {
    func registerRoutes(on router: Router<BasicRequestContext>, context: DaemonRouteContext) throws
}
