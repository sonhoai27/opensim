import Hummingbird

public enum HealthRoutes {
    public static func register(on router: Router<BasicRequestContext>, services: DaemonServices) {
        router.get("/v1/health") { _, _ in
            try DaemonHTTP.json(services.healthResponse())
        }
    }
}
