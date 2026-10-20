import Foundation
import Hummingbird
import OpenSimCore
import OpenSimProtocol

public final class RunningDaemonServer: @unchecked Sendable {
    public let port: Int
    private let task: Task<Void, Error>

    init(port: Int, task: Task<Void, Error>) {
        self.port = port
        self.task = task
    }

    public func stop() {
        task.cancel()
    }
}

public enum DaemonServer {
    public static func start(
        services: DaemonServices,
        token: String,
        port: Int,
        routeProviders: [any DaemonRouteProvider] = []
    ) async throws -> RunningDaemonServer {
        let router = Router<BasicRequestContext>()
        router.add(middleware: SecurityMiddleware(token: token))
        router.add(middleware: ErrorEnvelopeMiddleware())
        HealthRoutes.register(on: router, services: services)
        DeviceRoutes.register(on: router, services: services)
        SessionRoutes.register(on: router, services: services)
        OperationRoutes.register(on: router, services: services)

        let baseURL = try loopbackURL("http://127.0.0.1:\(port)")
        let context = DaemonRouteContext(services: services, token: token, baseURL: baseURL)
        for provider in routeProviders {
            try provider.registerRoutes(on: router, context: context)
        }

        let application = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )
        let task = Task {
            try await application.runService()
        }
        try await waitUntilHealthy(port: port)
        return RunningDaemonServer(port: port, task: task)
    }

    private static func waitUntilHealthy(port: Int) async throws {
        let url = try loopbackURL("http://127.0.0.1:\(port)/v1/health")
        for _ in 0..<40 {
            if let (_, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw OpenSimError(
            code: .daemonUnavailable,
            message: "Daemon HTTP server did not become healthy",
            details: ["port": "\(port)"],
            recovery: "Check the daemon log"
        )
    }

    private static func loopbackURL(_ value: String) throws -> URL {
        guard let url = URL(string: value) else {
            throw OpenSimError(code: .internalError, message: "Invalid URL: \(value)")
        }
        return url
    }
}
