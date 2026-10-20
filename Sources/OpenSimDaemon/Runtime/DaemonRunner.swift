import Darwin
import Dispatch
import Foundation
import Logging
import OpenSimBridge
import OpenSimCore
import OpenSimProtocol

public struct DaemonRunConfiguration: Sendable {
    public var paths: OpenSimPaths
    public var port: Int?
    public var routeProviders: [any DaemonRouteProvider]

    public init(
        paths: OpenSimPaths = OpenSimPaths(),
        port: Int? = nil,
        routeProviders: [any DaemonRouteProvider] = []
    ) {
        self.paths = paths
        self.port = port
        self.routeProviders = routeProviders
    }
}

public enum DaemonRunner {
    public static func run(configuration: DaemonRunConfiguration) async throws {
        let paths = configuration.paths
        try paths.ensureDirectories()
        let logger = DaemonLogger.makeLogger(paths: paths)
        let lock = try ProcessLock(path: paths.lockFile)
        defer { lock.release() }

        let locator = XcodeLocator()
        let developerDir = try locator.developerDir()
        let xcode = try locator.version(developerDir: developerDir)
        let bridge = try SimctlBridge.live(timeout: .seconds(120))
        let catalog = OperationCatalog.plan3()
        let automation = UIAutomationService(
            screen: bridge.screen,
            input: bridge.input,
            accessibility: bridge.accessibility
        )
        let sessions = SessionManager()
        let leases = LeaseManager()
        let events = EventHub()
        let audit = AuditWriter(fileURL: paths.auditFile)
        let dispatcher = OperationDispatcher(
            catalog: catalog,
            executor: BridgeOperationExecutor(
                bridge: bridge,
                crashReports: bridge,
                doctor: bridge,
                catalog: catalog,
                automation: automation
            ),
            bridge: bridge,
            sessions: sessions,
            leases: leases,
            audit: audit,
            events: events,
            logger: logger
        )
        let port = try configuration.port ?? PortAllocator.freePort()
        let token = try TokenGenerator.make()
        let state = DaemonState(
            pid: getpid(),
            port: port,
            token: token,
            version: OpenSimVersion.version,
            xcodeVersion: xcode.version,
            startedAt: Date()
        )
        let services = DaemonServices(
            bridge: bridge,
            dispatcher: dispatcher,
            sessions: sessions,
            leases: leases,
            events: events,
            audit: audit,
            state: state,
            capabilities: await bridge.capabilities
        )
        let server = try await DaemonServer.start(
            services: services,
            token: token,
            port: port,
            routeProviders: configuration.routeProviders
        )
        let store = DaemonStateStore(paths: paths)
        do {
            try store.write(state)
        } catch {
            server.stop()
            throw error
        }
        _ = try? await events.publish(
            type: .daemonHealth,
            payload: DaemonHealthPayload(status: "running", pid: state.pid, port: state.port)
        )
        logger.info("Daemon listening on 127.0.0.1:\(port)")

        let trap = SignalTrap()
        await trap.wait()

        logger.info("Daemon shutting down")
        _ = try? await events.publish(
            type: .daemonHealth,
            payload: DaemonHealthPayload(status: "stopping", pid: state.pid, port: state.port)
        )
        store.remove()
        server.stop()
    }
}

private final class SignalTrap: @unchecked Sendable {
    private var sources: [DispatchSourceSignal] = []
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.stream = stream
        self.continuation = continuation
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler {
                continuation.yield(())
            }
            source.resume()
            sources.append(source)
        }
    }

    func wait() async {
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
    }
}
