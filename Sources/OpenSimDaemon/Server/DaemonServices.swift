import Foundation
import OpenSimBridge
import OpenSimCore
import OpenSimProtocol

public struct DaemonServices: Sendable {
    public var bridge: any SimulatorBridge
    public var dispatcher: OperationDispatcher
    public var sessions: SessionManager
    public var leases: LeaseManager
    public var events: EventHub
    public var audit: AuditWriter
    public var state: DaemonState
    public var capabilities: BridgeCapabilities

    public init(
        bridge: any SimulatorBridge,
        dispatcher: OperationDispatcher,
        sessions: SessionManager,
        leases: LeaseManager,
        events: EventHub,
        audit: AuditWriter,
        state: DaemonState,
        capabilities: BridgeCapabilities
    ) {
        self.bridge = bridge
        self.dispatcher = dispatcher
        self.sessions = sessions
        self.leases = leases
        self.events = events
        self.audit = audit
        self.state = state
        self.capabilities = capabilities
    }

    public func healthResponse() -> HealthResponse {
        HealthResponse(
            status: "ok",
            version: state.version,
            protocolVersion: 1,
            pid: state.pid,
            port: state.port,
            startedAt: state.startedAt,
            capabilities: capabilities,
            xcodeVersion: state.xcodeVersion
        )
    }
}
