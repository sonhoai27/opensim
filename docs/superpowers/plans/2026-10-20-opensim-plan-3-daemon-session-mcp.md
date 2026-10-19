# OpenSim Plan 3 — Daemon, Session/Lease, MCP

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dựng control plane OpenSim: HTTP/SSE daemon trên loopback, session/lease, operation dispatch từ catalog của Plan 1, MCP JSON-RPC stdio và HTTP, LaunchAgent, auth/audit, và chuyển CLI sang daemon client nhưng vẫn giữ direct mode cho doctor và test.

**Architecture:** `OpenSimProtocol` chứa Codable request/response/event dùng chung. `OpenSimDaemon` chạy Hummingbird 2 trên `127.0.0.1`, đọc state file `0600`, quản lý session/lease bằng actor, và dispatch operation qua `BridgeOperationExecutor` của Plan 1. `OpenSimMCP` là adapter mỏng đọc `OperationCatalog` động và gọi daemon; không có danh sách tool thứ hai. CLI chọn `DaemonCommandBackend` mặc định, `--direct` dùng lại `BridgeOperationExecutor`.

**Tech Stack:** Swift 6 language mode, SwiftPM, Hummingbird 2.x, SwiftNIO `ByteBuffer`, `swift-log`, JSON-RPC 2.0 tự implement, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-19-open-simulator-design.md`

**Plan 1:** `docs/superpowers/plans/2026-10-20-opensim-plan-1-core-bridge-cli.md`

## Global Constraints

- Plan 3 phụ thuộc Plan 1. Không đổi tên type/protocol/file đã có trong Plan 1.
- HTTP chỉ bind `127.0.0.1`, port động; không Unix socket, không CORS.
- Bearer token 32 byte ngẫu nhiên mỗi lần daemon start; state file `0600`, thư mục `0700`.
- Kiểm tra `Host` và `Origin`; từ chối request không phải loopback.
- Lease TTL mặc định 300 giây; heartbeat 30 giây; takeover grace 3 giây; observe nhiều owner, control một owner.
- `device_create`, `device_clone`, `runtime_install`, `runtime_delete` là thao tác toàn cục không có device để giữ lease; chúng dùng `confirm` và audit, không yêu cầu control lease.
- Envelope schema version `1`; error code dùng spec 8.3 và `capability_unavailable`.
- MCP dùng JSON-RPC 2.0; không dùng MCP SDK; protocol version `2025-06-18`.
- MCP tool name lấy từ `OperationCatalog.mcpOperations()`; không hardcode danh sách thứ hai.
- Plan 2 services có thể `nil`; daemon vẫn start, operation cần service đó trả `capability_unavailable`.
- Không implement storage/performance; các endpoint đó thuộc Plan 5.
- Không implement app UI; không dùng Chrome/browser automation.
- Mọi process chạy bằng `Process` với argument array; không shell string.
- Mọi task có check đỏ, implement, check xanh, commit. Không chạy commit khi viết plan.
- Văn xuôi tiếng Việt; code, type, identifier, command tiếng Anh; không ký tự CJK.

---

## File Structure

| File | Trách nhiệm | Commit? |
|---|---|---|
| `Package.swift` | Thêm target `OpenSimProtocol`, `OpenSimDaemon`, `OpenSimMCP`, Hummingbird, swift-log, NIOCore | Có |
| `Sources/OpenSimProtocol/JSONValue.swift` | JSON value tự do cho MCP và event payload | Có |
| `Sources/OpenSimProtocol/DaemonState.swift` | State file `daemon.json`, token, port | Có |
| `Sources/OpenSimProtocol/Health.swift` | `HealthResponse` | Có |
| `Sources/OpenSimProtocol/Operations.swift` | `OperationRequest`, `OperationResult` | Có |
| `Sources/OpenSimProtocol/Sessions.swift` | Request/response cho session và lease | Có |
| `Sources/OpenSimProtocol/Events.swift` | `EventType`, `DaemonEvent`, payload structs | Có |
| `Sources/OpenSimProtocol/DeviceActions.swift` | Request/response cho `/v1/devices/{udid}/actions` | Có |
| `Sources/OpenSimCore/Catalog/Plan3Operations.swift` | Đăng ký `session_list`, `session_acquire`, `session_release` | Có |
| `Sources/OpenSimDaemon/Support/TokenGenerator.swift` | Token base64url 32 byte | Có |
| `Sources/OpenSimDaemon/Support/ProcessLock.swift` | `flock` chống hai daemon | Có |
| `Sources/OpenSimDaemon/Support/PortAllocator.swift` | Cấp port loopback động | Có |
| `Sources/OpenSimDaemon/Support/DaemonLogger.swift` | swift-log ra file, rotate 10 MB x 5 | Có |
| `Sources/OpenSimDaemon/State/DaemonStateStore.swift` | Ghi/đọc/xoá state file với quyền `0600` | Có |
| `Sources/OpenSimDaemon/Sessions/SessionManager.swift` | Tạo/list/close session | Có |
| `Sources/OpenSimDaemon/Sessions/LeaseManager.swift` | Acquire/heartbeat/release/validate/takeover/expiry | Có |
| `Sources/OpenSimDaemon/Audit/AuditWriter.swift` | JSONL audit, rotate 50 MB | Có |
| `Sources/OpenSimDaemon/Events/EventHub.swift` | Fan-out event, ring buffer 256, replay | Có |
| `Sources/OpenSimDaemon/Events/SSEFrame.swift` | Encode SSE frame | Có |
| `Sources/OpenSimDaemon/Operations/OperationDispatcher.swift` | Catalog dispatch, lease, confirm, optional service, audit | Có |
| `Sources/OpenSimDaemon/Server/DaemonServices.swift` | Dependency bundle cho server | Có |
| `Sources/OpenSimDaemon/Server/DaemonRouteProvider.swift` | Protocol cho MCP mount route | Có |
| `Sources/OpenSimDaemon/Server/DaemonServer.swift` | Hummingbird app, start/stop, route composition | Có |
| `Sources/OpenSimDaemon/Server/SecurityMiddleware.swift` | Host/Origin/token, `RequestSecurity` | Có |
| `Sources/OpenSimDaemon/Server/ErrorEnvelopeMiddleware.swift` | Map `OpenSimError` sang HTTP status và envelope | Có |
| `Sources/OpenSimDaemon/Server/DaemonHTTP.swift` | JSON response, envelope error, body decode | Có |
| `Sources/OpenSimDaemon/Server/Routes/HealthRoutes.swift` | `/v1/health` | Có |
| `Sources/OpenSimDaemon/Server/Routes/DeviceRoutes.swift` | `/v1/devices`, actions | Có |
| `Sources/OpenSimDaemon/Server/Routes/SessionRoutes.swift` | `/v1/sessions`, `/v1/leases` | Có |
| `Sources/OpenSimDaemon/Server/Routes/OperationRoutes.swift` | `/v1/operations` | Có |
| `Sources/OpenSimDaemon/Server/Routes/EventRoutes.swift` | `/v1/events` SSE | Có |
| `Sources/OpenSimDaemon/Runtime/DaemonRunner.swift` | Startup, lock, state, signal, shutdown | Có |
| `Sources/OpenSimDaemon/LaunchAgent/LaunchAgentManager.swift` | Plist, bootstrap, bootout, kickstart | Có |
| `Sources/OpenSimDaemon/Client/DaemonClient.swift` | HTTP client, envelope decode, SSE | Có |
| `Sources/OpenSimDaemon/Client/DaemonLauncher.swift` | Auto-start và chờ health tối đa 5 giây | Có |
| `Sources/OpenSimMCP/JSONRPC/JSONRPC.swift` | JSON-RPC 2.0 types, error codes | Có |
| `Sources/OpenSimMCP/Tools/MCPToolDefinition.swift` | Tool definition và input schema | Có |
| `Sources/OpenSimMCP/Tools/ToolCatalogAdapter.swift` | Catalog sang MCP tools, không hardcode | Có |
| `Sources/OpenSimMCP/Tools/MCPToolSession.swift` | Session, auto lease, heartbeat, gọi daemon | Có |
| `Sources/OpenSimMCP/Server/MCPHandler.swift` | initialize, tools/list, tools/call, ping | Có |
| `Sources/OpenSimMCP/Server/MCPHTTPSessionStore.swift` | Map `Mcp-Session-Id` sang handler/tool session | Có |
| `Sources/OpenSimMCP/HTTP/MCPRouteProvider.swift` | POST/GET/DELETE `/mcp`, SSE | Có |
| `Sources/OpenSimMCP/Stdio/StdioTransport.swift` | JSON-RPC line transport trên stdin/stdout | Có |
| `Sources/OpenSimCLI/Commands/DaemonCommand.swift` | `daemon start/stop/restart/status/logs/run` | Có |
| `Sources/OpenSimCLI/Commands/SessionCommand.swift` | `session list/acquire/release` | Có |
| `Sources/OpenSimCLI/Commands/MCPCommand.swift` | `mcp --stdio`, `mcp --http` | Có |
| `Sources/OpenSimCLI/Runtime/DaemonCommandBackend.swift` | `CommandBackend` qua daemon, auto session/lease | Có |
| `Sources/OpenSimCLI/Commands/GlobalOptions.swift` | Thêm `--direct`, `--session` | Có |
| `Sources/OpenSimCLI/Runtime/CLIRuntime.swift` | Chọn direct/daemon backend, async | Có |
| `Sources/OpenSimCLI/OpenSimCommand.swift` | Thêm nhóm daemon/session/mcp | Có |
| `Sources/OpenSimCLI/Commands/DoctorCommand.swift` | Doctor luôn direct | Có |
| `Sources/OpenSimCLI/Commands/LogCommand.swift` | Plan 3 đổi `makeBackend` sang async | Có |
| `Tests/OpenSimCLITests/CommandParsingTests.swift` | Plan 3 thêm test daemon/session/mcp | Có |
| `Tests/OpenSimProtocolTests/ProtocolCodingTests.swift` | Round-trip protocol | Có |
| `Tests/OpenSimDaemonTests/StateAndPortTests.swift` | State quyền, lock, token, port | Có |
| `Tests/OpenSimDaemonTests/LeaseManagerTests.swift` | Conflict/expiry/takeover/observe | Có |
| `Tests/OpenSimDaemonTests/AuditAndEventTests.swift` | Audit rotate, event replay | Có |
| `Tests/OpenSimDaemonTests/OperationDispatcherTests.swift` | Catalog, confirm, lease, optional service | Có |
| `Tests/OpenSimDaemonTests/SecurityTests.swift` | Host/Origin/token | Có |
| `Tests/OpenSimDaemonTests/HTTPRoutesTests.swift` | Health/devices/sessions/operations auth | Có |
| `Tests/OpenSimDaemonTests/SSETests.swift` | Frame, replay, reconnect | Có |
| `Tests/OpenSimDaemonTests/LaunchAgentTests.swift` | Plist content | Có |
| `Tests/OpenSimDaemonTests/DaemonClientTests.swift` | Client health/session/lease/devices | Có |
| `Tests/OpenSimDaemonTests/DaemonLoggerTests.swift` | File log và rotation | Có |
| `Tests/OpenSimDaemonTests/SessionAndOperationRoutesTests.swift` | Lease conflict/observe, operation routes | Có |
| `Tests/OpenSimDaemonTests/MCPHTTPTests.swift` | MCP HTTP session id và tools/list | Có |
| `Tests/OpenSimMCPTests/MCPHandlerTests.swift` | initialize/tools/list/tools/call errors | Có |
| `Tests/OpenSimMCPTests/ToolCatalogAdapterTests.swift` | Catalog parity | Có |
| `Tests/OpenSimMCPTests/StdioTransportTests.swift` | stdio parse và notification | Có |
| `Tests/OpenSimCLITests/CatalogCLIParityTests.swift` | Catalog có CLI command tương ứng | Có |
| `Tests/IntegrationTests/Plan3DaemonIntegrationTests.swift` | Daemon restart, CLI daemon switch, MCP end-to-end | Có |
| `Tests/IntegrationTests/README-Plan3.md` | Hướng dẫn chạy integration test Plan 3 | Có |

---

### Task 1: Package, JSONValue, daemon state và health

**Files:**
- Modify: `Package.swift`
- Create: `Sources/OpenSimProtocol/JSONValue.swift`
- Create: `Sources/OpenSimProtocol/DaemonState.swift`
- Create: `Sources/OpenSimProtocol/Health.swift`
- Test: `Tests/OpenSimProtocolTests/ProtocolCodingTests.swift`

**Interfaces:**
- Consumes: `OpenSimJSON`, `OpenSimDate`, `BridgeCapabilities`, `OpenSimVersion`.
- Produces: `JSONValue`; `DaemonState`; `HealthResponse`; target `OpenSimProtocol`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimProtocolTests/ProtocolCodingTests.swift`:

```swift
import XCTest
@testable import OpenSimProtocol
@testable import OpenSimCore

final class ProtocolCodingTests: XCTestCase {
    func testDaemonStateRoundTrip() throws {
        let state = DaemonState(
            pid: 12345,
            port: 54321,
            token: "token-value",
            version: "0.1.0",
            xcodeVersion: "27.1",
            startedAt: Date(timeIntervalSince1970: 1_797_000_000)
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(state)
        let decoded = try OpenSimJSON.decoder().decode(DaemonState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testHealthResponseDoesNotContainToken() throws {
        let health = HealthResponse(
            status: "ok",
            version: "0.1.0",
            protocolVersion: 1,
            pid: 10,
            port: 20,
            startedAt: Date(timeIntervalSince1970: 1_797_000_000),
            capabilities: BridgeCapabilities(
                render: .unavailable,
                hid: .unavailable,
                accessibility: .unavailable,
                screenshot: .available,
                video: .available,
                watch: .unavailable,
                tv: .unavailable
            ),
            xcodeVersion: "27.1"
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(health)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("token"))
        let decoded = try OpenSimJSON.decoder().decode(HealthResponse.self, from: data)
        XCTAssertEqual(decoded.capabilities.screenshot, .available)
    }

    func testJSONValueCoding() throws {
        let value = JSONValue.object([
            "name": .string("opensim"),
            "count": .number(3),
            "enabled": .bool(true),
            "items": .array([.string("a"), .null]),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.objectValue?["name"], .string("opensim"))
    }

    func testJSONValueFromEncodable() throws {
        let device = Device(
            id: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            name: "iPhone Air",
            platform: .iOS,
            deviceType: "iPhone-Air",
            runtime: RuntimeID("iOS-27-0"),
            state: .booted,
            isAvailable: true,
            dataPath: nil,
            lastBootedAt: nil
        )
        let value = try JSONValue.from(device)
        XCTAssertEqual(value.objectValue?["id"], .string("95B3747B-7065-447E-AB1E-53065142C3FC"))
        XCTAssertEqual(value.objectValue?["state"], .string("booted"))
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter ProtocolCodingTests
```

Expected: FAIL với `no such module 'OpenSimProtocol'`.

- [ ] **Step 3: Viết package và protocol foundation**

Modify `Package.swift` để thêm product/target protocol (chưa thêm daemon/MCP; các target đó được thêm khi task tạo source tương ứng):

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSim",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "OpenSimCore", targets: ["OpenSimCore"]),
        .library(name: "OpenSimBridge", targets: ["OpenSimBridge"]),
        .library(name: "OpenSimProtocol", targets: ["OpenSimProtocol"]),
        .executable(name: "opensim", targets: ["OpenSimCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(name: "OpenSimCore"),
        .target(name: "OpenSimBridge", dependencies: ["OpenSimCore"]),
        .target(name: "OpenSimProtocol", dependencies: ["OpenSimCore"]),
        .executableTarget(
            name: "OpenSimCLI",
            dependencies: [
                "OpenSimCore",
                "OpenSimBridge",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "OpenSimCoreTests", dependencies: ["OpenSimCore"]),
        .testTarget(name: "OpenSimBridgeTests", dependencies: ["OpenSimBridge", "OpenSimCore"]),
        .testTarget(name: "OpenSimProtocolTests", dependencies: ["OpenSimProtocol", "OpenSimCore"]),
        .testTarget(
            name: "OpenSimCLITests",
            dependencies: [
                "OpenSimCLI",
                "OpenSimCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "IntegrationTests", dependencies: ["OpenSimCore", "OpenSimBridge"]),
    ],
    swiftLanguageModes: [.v6]
)
```

Create `Sources/OpenSimProtocol/JSONValue.swift`:

```swift
import Foundation
import OpenSimCore

public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    public static func from<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try OpenSimJSON.encoder(pretty: false).encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try OpenSimJSON.decoder().decode(type, from: data)
    }
}
```

Create `Sources/OpenSimProtocol/DaemonState.swift`:

```swift
import Foundation

public struct DaemonState: Codable, Sendable, Equatable {
    public var pid: Int32
    public var port: Int
    public var token: String
    public var version: String
    public var xcodeVersion: String
    public var startedAt: Date

    public init(
        pid: Int32,
        port: Int,
        token: String,
        version: String,
        xcodeVersion: String,
        startedAt: Date
    ) {
        self.pid = pid
        self.port = port
        self.token = token
        self.version = version
        self.xcodeVersion = xcodeVersion
        self.startedAt = startedAt
    }
}
```

Create `Sources/OpenSimProtocol/Health.swift`:

```swift
import Foundation
import OpenSimCore

public struct HealthResponse: Codable, Sendable, Equatable {
    public var status: String
    public var version: String
    public var protocolVersion: Int
    public var pid: Int32
    public var port: Int
    public var startedAt: Date
    public var capabilities: BridgeCapabilities
    public var xcodeVersion: String

    public init(
        status: String,
        version: String,
        protocolVersion: Int,
        pid: Int32,
        port: Int,
        startedAt: Date,
        capabilities: BridgeCapabilities,
        xcodeVersion: String
    ) {
        self.status = status
        self.version = version
        self.protocolVersion = protocolVersion
        self.pid = pid
        self.port = port
        self.startedAt = startedAt
        self.capabilities = capabilities
        self.xcodeVersion = xcodeVersion
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter ProtocolCodingTests
```

Expected: PASS; `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/OpenSimProtocol Tests/OpenSimProtocolTests/ProtocolCodingTests.swift
git commit -m "feat(protocol): add daemon state health and json value"
```

---

### Task 2: Operation, session, lease và event protocol

**Files:**
- Create: `Sources/OpenSimProtocol/Operations.swift`
- Create: `Sources/OpenSimProtocol/Sessions.swift`
- Create: `Sources/OpenSimProtocol/Events.swift`
- Create: `Sources/OpenSimCore/Catalog/Plan3Operations.swift`
- Modify: `Tests/OpenSimProtocolTests/ProtocolCodingTests.swift`

**Interfaces:**
- Consumes: `SessionID`, `LeaseID`, `DeviceID`, `Lease`, `Session`, `LeaseMode`, `AuditEvent`, `OperationCatalog.plan1()`.
- Produces: `OperationRequest`, `OperationResult`; `CreateSessionRequest`, `AcquireLeaseRequest`, `HeartbeatRequest`, `LeaseReleaseResult`, `SessionListResult`; `EventType`, `DaemonEvent`, payload structs; `OperationCatalog.plan3()`.

- [ ] **Step 1: Viết test thất bại**

Append vào `Tests/OpenSimProtocolTests/ProtocolCodingTests.swift` trước dấu `}` cuối file:

```swift
    func testOperationRequestRoundTrip() throws {
        let request = OperationRequest(
            operation: "device_boot",
            parameters: ["device": "95B3747B-7065-447E-AB1E-53065142C3FC", "wait": "true"],
            sessionID: SessionID("session-1"),
            leaseID: LeaseID("lease-1"),
            dryRun: nil
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(request)
        let decoded = try OpenSimJSON.decoder().decode(OperationRequest.self, from: data)
        XCTAssertEqual(decoded, request)
    }

    func testOperationResultDataRoundTrip() throws {
        let payload = try OpenSimJSON.encoder(pretty: false).encode(["ok": true])
        let result = OperationResult(operation: "device_list", data: payload, auditID: "audit-1")
        let data = try OpenSimJSON.encoder(pretty: false).encode(result)
        let decoded = try OpenSimJSON.decoder().decode(OperationResult.self, from: data)
        XCTAssertEqual(decoded.data, payload)
        XCTAssertEqual(decoded.auditID, "audit-1")
    }

    func testDaemonEventRoundTrip() throws {
        let payload = DeviceStateChangedPayload(
            deviceID: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            state: .booted,
            previousState: .booting
        )
        let event = DaemonEvent(
            id: "7",
            type: .deviceStateChanged,
            timestamp: Date(timeIntervalSince1970: 1_797_000_000),
            data: try JSONValue.from(payload)
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(event)
        let decoded = try OpenSimJSON.decoder().decode(DaemonEvent.self, from: data)
        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.type.rawValue, "device.state.changed")
    }

    func testPlan3CatalogAddsSessionTools() {
        let catalog = OperationCatalog.plan3()
        XCTAssertEqual(catalog.mcpOperations().count, 25)
        XCTAssertNotNil(catalog.operation(forMCP: "session_acquire"))
        XCTAssertEqual(catalog.operation(forCLI: ["session", "release"])?.mcpName, "session_release")
    }
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter ProtocolCodingTests
```

Expected: FAIL với `cannot find type 'OperationRequest' in scope`.

- [ ] **Step 3: Viết protocol types và Plan 3 catalog**

Create `Sources/OpenSimProtocol/Operations.swift`:

```swift
import Foundation
import OpenSimCore

public struct OperationRequest: Codable, Sendable, Equatable {
    public var operation: String
    public var parameters: [String: String]
    public var sessionID: SessionID?
    public var leaseID: LeaseID?
    public var dryRun: Bool?

    public init(
        operation: String,
        parameters: [String: String] = [:],
        sessionID: SessionID? = nil,
        leaseID: LeaseID? = nil,
        dryRun: Bool? = nil
    ) {
        self.operation = operation
        self.parameters = parameters
        self.sessionID = sessionID
        self.leaseID = leaseID
        self.dryRun = dryRun
    }
}

public struct OperationResult: Codable, Sendable, Equatable {
    public var operation: String
    public var data: Data
    public var auditID: String?

    public init(operation: String, data: Data, auditID: String? = nil) {
        self.operation = operation
        self.data = data
        self.auditID = auditID
    }
}

public extension OperationResult {
    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try OpenSimJSON.decoder().decode(type, from: data)
    }
}
```

Create `Sources/OpenSimProtocol/Sessions.swift`:

```swift
import Foundation
import OpenSimCore

public struct CreateSessionRequest: Codable, Sendable, Equatable {
    public var clientKind: String
    public var clientName: String

    public init(clientKind: String, clientName: String) {
        self.clientKind = clientKind
        self.clientName = clientName
    }
}

public struct AcquireLeaseRequest: Codable, Sendable, Equatable {
    public var deviceID: DeviceID
    public var sessionID: SessionID
    public var mode: LeaseMode
    public var ttlSeconds: Int?
    public var takeover: Bool?
    public var ownerName: String?

    public init(
        deviceID: DeviceID,
        sessionID: SessionID,
        mode: LeaseMode,
        ttlSeconds: Int? = nil,
        takeover: Bool? = nil,
        ownerName: String? = nil
    ) {
        self.deviceID = deviceID
        self.sessionID = sessionID
        self.mode = mode
        self.ttlSeconds = ttlSeconds
        self.takeover = takeover
        self.ownerName = ownerName
    }
}

public struct HeartbeatRequest: Codable, Sendable, Equatable {
    public var sessionID: SessionID
    public var ttlSeconds: Int?

    public init(sessionID: SessionID, ttlSeconds: Int? = nil) {
        self.sessionID = sessionID
        self.ttlSeconds = ttlSeconds
    }
}

public struct LeaseReleaseResult: Codable, Sendable, Equatable {
    public var leaseID: LeaseID
    public var released: Bool

    public init(leaseID: LeaseID, released: Bool) {
        self.leaseID = leaseID
        self.released = released
    }
}

public struct SessionListResult: Codable, Sendable, Equatable {
    public var sessions: [Session]
    public var leases: [Lease]

    public init(sessions: [Session], leases: [Lease]) {
        self.sessions = sessions
        self.leases = leases
    }
}
```

Create `Sources/OpenSimProtocol/Events.swift`:

```swift
import Foundation
import OpenSimCore

public enum EventType: String, Codable, Sendable, CaseIterable {
    case deviceStateChanged = "device.state.changed"
    case sessionCreated = "session.created"
    case sessionClosed = "session.closed"
    case leaseChanged = "lease.changed"
    case leaseRevoked = "lease.revoked"
    case storageScanProgress = "storage.scan.progress"
    case storageScanCompleted = "storage.scan.completed"
    case metricsSample = "metrics.sample"
    case auditAppended = "audit.appended"
    case daemonHealth = "daemon.health"
}

public struct DaemonEvent: Codable, Sendable, Equatable {
    public var id: String
    public var type: EventType
    public var timestamp: Date
    public var data: JSONValue

    public init(id: String, type: EventType, timestamp: Date, data: JSONValue) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.data = data
    }
}

public struct DeviceStateChangedPayload: Codable, Sendable, Equatable {
    public var deviceID: DeviceID
    public var state: DeviceState
    public var previousState: DeviceState

    public init(deviceID: DeviceID, state: DeviceState, previousState: DeviceState) {
        self.deviceID = deviceID
        self.state = state
        self.previousState = previousState
    }
}

public struct SessionChangedPayload: Codable, Sendable, Equatable {
    public var session: Session

    public init(session: Session) {
        self.session = session
    }
}

public struct LeaseChangedPayload: Codable, Sendable, Equatable {
    public var lease: Lease
    public var reason: String

    public init(lease: Lease, reason: String) {
        self.lease = lease
        self.reason = reason
    }
}

public struct AuditAppendedPayload: Codable, Sendable, Equatable {
    public var event: AuditEvent

    public init(event: AuditEvent) {
        self.event = event
    }
}

public struct DaemonHealthPayload: Codable, Sendable, Equatable {
    public var status: String
    public var pid: Int32
    public var port: Int

    public init(status: String, pid: Int32, port: Int) {
        self.status = status
        self.pid = pid
        self.port = port
    }
}
```

Create `Sources/OpenSimCore/Catalog/Plan3Operations.swift`:

```swift
import Foundation

public extension OperationCatalog {
    static func plan3() -> OperationCatalog {
        var catalog = OperationCatalog.plan1()
        for operation in Plan3Operations.all {
            catalog.register(operation)
        }
        return catalog
    }
}

public enum Plan3Operations {
    public static let all: [Operation] = [
        Operation(
            cliPath: ["session", "list"],
            mcpName: "session_list",
            summary: "List sessions and active leases",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: []
        ),
        Operation(
            cliPath: ["session", "acquire"],
            mcpName: "session_acquire",
            summary: "Acquire a control or observe lease for a device",
            requiresControlLease: false,
            destructive: false,
            readOnly: false,
            parameters: [
                OperationParameter(name: "device", type: "string", required: true),
                OperationParameter(name: "mode", type: "string", required: false, defaultValue: "control"),
                OperationParameter(name: "ttlSeconds", type: "integer", required: false, defaultValue: "300"),
            ]
        ),
        Operation(
            cliPath: ["session", "release"],
            mcpName: "session_release",
            summary: "Release a lease owned by the current session",
            requiresControlLease: false,
            destructive: false,
            readOnly: false,
            parameters: [
                OperationParameter(name: "leaseID", type: "string", required: true),
            ]
        ),
    ]
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter ProtocolCodingTests
```

Expected: PASS; `Executed 8 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimProtocol/Operations.swift Sources/OpenSimProtocol/Sessions.swift Sources/OpenSimProtocol/Events.swift Sources/OpenSimCore/Catalog/Plan3Operations.swift Tests/OpenSimProtocolTests/ProtocolCodingTests.swift
git commit -m "feat(protocol): add operations sessions and events"
```

---

### Task 3: Token, state store, lock và port allocator

**Files:**
- Modify: `Package.swift` (thêm SwiftLog, Hummingbird, NIOCore, target `OpenSimDaemon`, `OpenSimDaemonTests`)
- Create: `Sources/OpenSimDaemon/Support/TokenGenerator.swift`
- Create: `Sources/OpenSimDaemon/Support/ProcessLock.swift`
- Create: `Sources/OpenSimDaemon/Support/PortAllocator.swift`
- Create: `Sources/OpenSimDaemon/State/DaemonStateStore.swift`
- Test: `Tests/OpenSimDaemonTests/StateAndPortTests.swift`

**Interfaces:**
- Consumes: `OpenSimPaths`, `DaemonState`, `OpenSimJSON`, `OpenSimError`.
- Produces: `TokenGenerator.make(byteCount:)`; `ProcessLock(path:)`, `.release()`; `PortAllocator.freePort()`; `DaemonStateStore(paths:).write(_:)`, `.read()`, `.remove()`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/StateAndPortTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimCore

final class StateAndPortTests: XCTestCase {
    func testTokenLengthAndAlphabet() throws {
        let token = try TokenGenerator.make()
        XCTAssertEqual(token.count, 43)
        XCTAssertFalse(token.contains("+"))
        XCTAssertFalse(token.contains("/"))
        XCTAssertFalse(token.contains("="))
    }

    func testStateStoreWritesSecureFileAndRoundTrips() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-state-\(UUID().uuidString)", isDirectory: true)
        let paths = OpenSimPaths(baseDirectory: root)
        let store = DaemonStateStore(paths: paths)
        let state = DaemonState(
            pid: 42,
            port: 1234,
            token: "token",
            version: "0.1.0",
            xcodeVersion: "27.1",
            startedAt: Date(timeIntervalSince1970: 1_797_000_000)
        )
        try store.write(state)
        XCTAssertEqual(try store.read(), state)
        let attributes = try FileManager.default.attributesOfItem(atPath: paths.daemonStateFile.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        store.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.daemonStateFile.path))
        try? FileManager.default.removeItem(at: root)
    }

    func testProcessLockRejectsSecondOwner() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-lock-\(UUID().uuidString)", isDirectory: true)
        let paths = OpenSimPaths(baseDirectory: root)
        try paths.ensureDirectories()
        let first = try ProcessLock(path: paths.lockFile)
        XCTAssertThrowsError(try ProcessLock(path: paths.lockFile))
        first.release()
        let second = try ProcessLock(path: paths.lockFile)
        second.release()
        try? FileManager.default.removeItem(at: root)
    }

    func testPortAllocatorReturnsLoopbackPort() throws {
        let port = try PortAllocator.freePort()
        XCTAssertGreaterThan(port, 1024)
        XCTAssertLessThan(port, 65_536)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter StateAndPortTests
```

Expected: FAIL với `cannot find 'TokenGenerator' in scope`.

- [ ] **Step 3: Viết support và state store**

Modify `Package.swift`: thêm ba dependency:

```swift
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.60.0"),
```

Thêm product:

```swift
        .library(name: "OpenSimDaemon", targets: ["OpenSimDaemon"]),
```

Thêm target và test target:

```swift
        .target(
            name: "OpenSimDaemon",
            dependencies: [
                "OpenSimCore",
                "OpenSimBridge",
                "OpenSimProtocol",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "OpenSimDaemonTests",
            dependencies: [
                "OpenSimDaemon",
                "OpenSimBridge",
                "OpenSimProtocol",
                "OpenSimCore",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
```

Create `Sources/OpenSimDaemon/Support/TokenGenerator.swift`:

```swift
import Foundation
import OpenSimCore
import Security

public enum TokenGenerator {
    public static func make(byteCount: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else {
                return errSecAllocate
            }
            return SecRandomCopyBytes(kSecRandomDefault, byteCount, base)
        }
        guard status == errSecSuccess else {
            throw OpenSimError(
                code: .internalError,
                message: "Cannot generate daemon token",
                details: ["status": "\(status)"]
            )
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

Create `Sources/OpenSimDaemon/Support/ProcessLock.swift`:

```swift
import Darwin
import Foundation
import OpenSimCore

public final class ProcessLock: @unchecked Sendable {
    private let fd: Int32
    private var released = false

    public init(path: URL) throws {
        let descriptor = open(path.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            throw OpenSimError(
                code: .permissionDenied,
                message: "Cannot open daemon lock file",
                details: ["path": path.path, "errno": "\(errno)"]
            )
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw OpenSimError.daemonUnavailable("Another OpenSim daemon is already running")
        }
        self.fd = descriptor
    }

    public func release() {
        guard !released else {
            return
        }
        released = true
        _ = flock(fd, LOCK_UN)
        _ = close(fd)
    }

    deinit {
        release()
    }
}
```

Create `Sources/OpenSimDaemon/Support/PortAllocator.swift`:

```swift
import Darwin
import Foundation
import OpenSimCore

public enum PortAllocator {
    public static func freePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw OpenSimError(
                code: .internalError,
                message: "Cannot create socket for port allocation",
                details: ["errno": "\(errno)"]
            )
        }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw OpenSimError(
                code: .internalError,
                message: "Cannot bind loopback socket",
                details: ["errno": "\(errno)"]
            )
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(descriptor, socketAddress, &length)
            }
        }
        guard nameResult == 0 else {
            throw OpenSimError(
                code: .internalError,
                message: "Cannot read allocated port",
                details: ["errno": "\(errno)"]
            )
        }
        return Int(UInt16(bigEndian: assigned.sin_port))
    }
}
```

Create `Sources/OpenSimDaemon/State/DaemonStateStore.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

public struct DaemonStateStore: Sendable {
    private let paths: OpenSimPaths
    private let fileManager: FileManager

    public init(paths: OpenSimPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func write(_ state: DaemonState) throws {
        try fileManager.createDirectory(
            at: paths.baseDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.baseDirectory.path)
        let data = try OpenSimJSON.encoder(pretty: true).encode(state)
        try data.write(to: paths.daemonStateFile, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.daemonStateFile.path)
    }

    public func read() throws -> DaemonState {
        let data = try Data(contentsOf: paths.daemonStateFile)
        return try OpenSimJSON.decoder().decode(DaemonState.self, from: data)
    }

    public func remove() {
        try? fileManager.removeItem(at: paths.daemonStateFile)
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter StateAndPortTests
```

Expected: PASS; `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimDaemon/Support Sources/OpenSimDaemon/State Tests/OpenSimDaemonTests/StateAndPortTests.swift
git commit -m "feat(daemon): add token state lock and port allocation"
```

### Task 4: SessionManager và LeaseManager

**Files:**
- Create: `Sources/OpenSimDaemon/Sessions/SessionManager.swift`
- Create: `Sources/OpenSimDaemon/Sessions/LeaseManager.swift`
- Test: `Tests/OpenSimDaemonTests/LeaseManagerTests.swift`

**Interfaces:**
- Consumes: `Session`, `Lease`, `LeaseMode`, `SessionID`, `LeaseID`, `DeviceID`, `OpenSimError`, `OpenSimDate`.
- Produces: `SessionManager(now:idGenerator:).create(clientKind:clientName:)`, `.close(_:)`, `.list()`, `.session(_:)`; `LeaseManager(defaultTTL:takeoverGrace:now:idGenerator:).acquire(device:session:mode:ttlSeconds:ownerName:takeover:)`, `.heartbeat(_:session:ttlSeconds:)`, `.release(_:session:)`, `.releaseAll(session:)`, `.validate(device:leaseID:session:)`, `.expireIfNeeded()`, `.activeLeases()`, `.leases(for:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/LeaseManagerTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimCore

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}

final class LeaseManagerTests: XCTestCase {
    private let device = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")
    private let sessionA = SessionID("session-a")
    private let sessionB = SessionID("session-b")

    func testControlConflictReportsOwnerAndExpiry() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = LeaseManager(defaultTTL: 300, takeoverGrace: 0, now: { clock.now() })
        _ = try await manager.acquire(
            device: device,
            session: sessionA,
            mode: .control,
            ttlSeconds: 300,
            ownerName: "agent-a",
            takeover: false
        )
        do {
            _ = try await manager.acquire(
                device: device,
                session: sessionB,
                mode: .control,
                ttlSeconds: 300,
                ownerName: "agent-b",
                takeover: false
            )
            XCTFail("expected lease_conflict")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "lease_conflict")
            XCTAssertEqual(error.details["owner"], "agent-a")
            XCTAssertEqual(error.retryable, true)
        }
    }

    func testObserveLeasesCoexist() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = LeaseManager(defaultTTL: 300, takeoverGrace: 0, now: { clock.now() })
        let first = try await manager.acquire(device: device, session: sessionA, mode: .observe, ttlSeconds: 300, ownerName: "a", takeover: false)
        let second = try await manager.acquire(device: device, session: sessionB, mode: .observe, ttlSeconds: 300, ownerName: "b", takeover: false)
        XCTAssertNotEqual(first.id, second.id)
        let active = await manager.activeLeases()
        XCTAssertEqual(active.count, 2)
    }

    func testExpiryReleasesLeaseAndValidateReturnsRevoked() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = LeaseManager(defaultTTL: 300, takeoverGrace: 0, now: { clock.now() })
        let lease = try await manager.acquire(device: device, session: sessionA, mode: .control, ttlSeconds: 1, ownerName: "a", takeover: false)
        clock.advance(2)
        let expired = await manager.expireIfNeeded()
        XCTAssertEqual(expired.map(\.id), [lease.id])
        do {
            try await manager.validate(device: device, leaseID: lease.id, session: sessionA)
            XCTFail("expected lease_revoked")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "lease_revoked")
        }
    }

    func testHeartbeatExtendsExpiry() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = LeaseManager(defaultTTL: 300, takeoverGrace: 0, now: { clock.now() })
        let lease = try await manager.acquire(device: device, session: sessionA, mode: .control, ttlSeconds: 10, ownerName: "a", takeover: false)
        clock.advance(5)
        let renewed = try await manager.heartbeat(lease.id, session: sessionA, ttlSeconds: 300)
        XCTAssertGreaterThan(renewed.expiresAt, lease.expiresAt)
        XCTAssertEqual(renewed.expiresAt.timeIntervalSince1970, clock.now().timeIntervalSince1970 + 300, accuracy: 0.001)
    }

    func testTakeoverReplacesControlLease() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = LeaseManager(defaultTTL: 300, takeoverGrace: 0, now: { clock.now() })
        let oldLease = try await manager.acquire(device: device, session: sessionA, mode: .control, ttlSeconds: 300, ownerName: "agent-a", takeover: false)
        let newLease = try await manager.acquire(device: device, session: sessionB, mode: .control, ttlSeconds: 300, ownerName: "app", takeover: true)
        XCTAssertNotEqual(oldLease.id, newLease.id)
        let active = await manager.activeLeases().filter { $0.mode == .control }
        XCTAssertEqual(active.map(\.id), [newLease.id])
    }

    func testReleaseRequiresOwnerSession() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = LeaseManager(defaultTTL: 300, takeoverGrace: 0, now: { clock.now() })
        let lease = try await manager.acquire(device: device, session: sessionA, mode: .control, ttlSeconds: 300, ownerName: "a", takeover: false)
        let wrong = await manager.release(lease.id, session: sessionB)
        XCTAssertFalse(wrong)
        let correct = await manager.release(lease.id, session: sessionA)
        XCTAssertTrue(correct)
    }

    func testSessionManagerCreateAndClose() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_797_000_000))
        let manager = SessionManager(now: { clock.now() }, idGenerator: { SessionID("session-fixed") })
        let session = await manager.create(clientKind: "cli", clientName: "device boot")
        XCTAssertEqual(session.id, SessionID("session-fixed"))
        XCTAssertEqual(session.createdAt, clock.now())
        let closed = await manager.close(session.id)
        XCTAssertTrue(closed)
        let all = await manager.list()
        XCTAssertTrue(all.isEmpty)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter LeaseManagerTests
```

Expected: FAIL với `cannot find 'LeaseManager' in scope`.

- [ ] **Step 3: Viết session và lease managers**

Create `Sources/OpenSimDaemon/Sessions/SessionManager.swift`:

```swift
import Foundation
import OpenSimCore

public actor SessionManager {
    private var sessions: [SessionID: Session] = [:]
    private let now: @Sendable () -> Date
    private let idGenerator: @Sendable () -> SessionID

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> SessionID = { SessionID(UUID().uuidString) }
    ) {
        self.now = now
        self.idGenerator = idGenerator
    }

    public func create(clientKind: String, clientName: String) -> Session {
        let timestamp = now()
        let session = Session(
            id: idGenerator(),
            clientKind: clientKind,
            clientName: clientName,
            createdAt: timestamp,
            lastSeenAt: timestamp
        )
        sessions[session.id] = session
        return session
    }

    public func close(_ id: SessionID) -> Bool {
        sessions.removeValue(forKey: id) != nil
    }

    public func list() -> [Session] {
        sessions.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func session(_ id: SessionID) -> Session? {
        sessions[id]
    }

    public func touch(_ id: SessionID) -> Session? {
        guard var session = sessions[id] else {
            return nil
        }
        session.lastSeenAt = now()
        sessions[id] = session
        return session
    }
}
```

Create `Sources/OpenSimDaemon/Sessions/LeaseManager.swift`:

```swift
import Foundation
import OpenSimCore

public actor LeaseManager {
    private var leases: [LeaseID: Lease] = [:]
    private let defaultTTL: TimeInterval
    private let takeoverGrace: TimeInterval
    private let now: @Sendable () -> Date
    private let idGenerator: @Sendable () -> LeaseID

    public init(
        defaultTTL: TimeInterval = 300,
        takeoverGrace: TimeInterval = 3,
        now: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> LeaseID = { LeaseID(UUID().uuidString) }
    ) {
        self.defaultTTL = defaultTTL
        self.takeoverGrace = takeoverGrace
        self.now = now
        self.idGenerator = idGenerator
    }

    public func acquire(
        device: DeviceID,
        session: SessionID,
        mode: LeaseMode,
        ttlSeconds: Int?,
        ownerName: String,
        takeover: Bool
    ) async throws -> Lease {
        _ = expireIfNeeded()
        let ttl = validatedTTL(ttlSeconds)

        if mode == .control {
            if let holder = controlLease(device: device) {
                if holder.sessionID == session {
                    return try renew(holder, ttl: ttl)
                }
                guard takeover else {
                    throw conflictError(holder)
                }
                if takeoverGrace > 0 {
                    try await Task.sleep(for: .milliseconds(Int64(takeoverGrace * 1_000)))
                }
                _ = expireIfNeeded()
                if let current = controlLease(device: device), current.sessionID != session {
                    leases.removeValue(forKey: current.id)
                }
            }
        }

        let timestamp = now()
        let lease = Lease(
            id: idGenerator(),
            deviceID: device,
            sessionID: session,
            mode: mode,
            ownerName: ownerName,
            acquiredAt: timestamp,
            expiresAt: timestamp.addingTimeInterval(ttl)
        )
        leases[lease.id] = lease
        return lease
    }

    public func heartbeat(_ id: LeaseID, session: SessionID, ttlSeconds: Int?) throws -> Lease {
        _ = expireIfNeeded()
        guard var lease = leases[id] else {
            throw OpenSimError(
                code: .leaseRevoked,
                message: "Lease no longer exists",
                details: ["leaseID": id.rawValue],
                recovery: "Acquire a new lease",
                retryable: true
            )
        }
        guard lease.sessionID == session else {
            throw conflictError(lease)
        }
        lease.expiresAt = now().addingTimeInterval(validatedTTL(ttlSeconds))
        leases[id] = lease
        return lease
    }

    public func release(_ id: LeaseID, session: SessionID) -> Bool {
        guard let lease = leases[id], lease.sessionID == session else {
            return false
        }
        leases.removeValue(forKey: id)
        return true
    }

    public func releaseAll(session: SessionID) -> [Lease] {
        let owned = leases.values.filter { $0.sessionID == session }
        for lease in owned {
            leases.removeValue(forKey: lease.id)
        }
        return owned
    }

    public func validate(device: DeviceID, leaseID: LeaseID?, session: SessionID) throws {
        _ = expireIfNeeded()
        guard let leaseID else {
            throw OpenSimError(
                code: .leaseRequired,
                message: "A control lease is required for this operation",
                details: ["device": device.rawValue],
                recovery: "Run `opensim session acquire --device <udid> --mode control`",
                retryable: false
            )
        }
        guard let lease = leases[leaseID] else {
            throw OpenSimError(
                code: .leaseRevoked,
                message: "Lease no longer exists",
                details: ["leaseID": leaseID.rawValue],
                recovery: "Acquire a new lease",
                retryable: true
            )
        }
        guard lease.sessionID == session else {
            throw conflictError(lease)
        }
        guard lease.deviceID == device else {
            throw OpenSimError(
                code: .leaseConflict,
                message: "Lease belongs to another device",
                details: ["leaseDevice": lease.deviceID.rawValue, "requestedDevice": device.rawValue],
                recovery: "Acquire a lease for the requested device",
                retryable: false
            )
        }
        guard lease.mode == .control else {
            throw OpenSimError(
                code: .leaseRequired,
                message: "Control mode is required for write operations",
                details: ["mode": lease.mode.rawValue],
                recovery: "Acquire a control lease",
                retryable: false
            )
        }
    }

    public func expireIfNeeded() -> [Lease] {
        let timestamp = now()
        let expired = leases.values.filter { $0.expiresAt <= timestamp }
        for lease in expired {
            leases.removeValue(forKey: lease.id)
        }
        return expired.sorted { $0.expiresAt < $1.expiresAt }
    }

    public func activeLeases() -> [Lease] {
        _ = expireIfNeeded()
        return leases.values.sorted { $0.acquiredAt < $1.acquiredAt }
    }

    public func leases(for session: SessionID) -> [Lease] {
        _ = expireIfNeeded()
        return leases.values.filter { $0.sessionID == session }
    }

    private func controlLease(device: DeviceID) -> Lease? {
        leases.values.first { $0.deviceID == device && $0.mode == .control }
    }

    private func renew(_ lease: Lease, ttl: TimeInterval) throws -> Lease {
        var updated = lease
        updated.expiresAt = now().addingTimeInterval(ttl)
        leases[lease.id] = updated
        return updated
    }

    private func validatedTTL(_ ttlSeconds: Int?) -> TimeInterval {
        let requested = TimeInterval(ttlSeconds ?? Int(defaultTTL))
        return min(max(requested, 1), 3_600)
    }

    private func conflictError(_ lease: Lease) -> OpenSimError {
        OpenSimError(
            code: .leaseConflict,
            message: "Device is controlled by another session",
            details: [
                "owner": lease.ownerName,
                "mode": lease.mode.rawValue,
                "expiresAt": OpenSimDate.string(from: lease.expiresAt),
                "leaseID": lease.id.rawValue,
            ],
            recovery: "Take control or wait for the lease to expire",
            retryable: true
        )
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter LeaseManagerTests
```

Expected: PASS; `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimDaemon/Sessions Tests/OpenSimDaemonTests/LeaseManagerTests.swift
git commit -m "feat(daemon): add session and lease managers"
```

### Task 5: AuditWriter và EventHub

**Files:**
- Create: `Sources/OpenSimDaemon/Audit/AuditWriter.swift`
- Create: `Sources/OpenSimDaemon/Events/EventHub.swift`
- Test: `Tests/OpenSimDaemonTests/AuditAndEventTests.swift`

**Interfaces:**
- Consumes: `AuditEvent`, `DaemonEvent`, `EventType`, `JSONValue`.
- Produces: `AuditWriter(fileURL:maxBytes:).append(_:)`; `EventHub.publish(type:payload:)`, `.subscribe(after:)`, `.replay(after:)`, `.eventCount()`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/AuditAndEventTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimCore

final class AuditAndEventTests: XCTestCase {
    func testAuditWriterRotatesAtMaxBytes() async throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("audit.jsonl")
        let writer = AuditWriter(fileURL: file, maxBytes: 350)
        for index in 0..<10 {
            let event = AuditEvent(
                id: "audit-\(index)",
                timestamp: Date(timeIntervalSince1970: Double(index)),
                actor: "agent",
                sessionID: SessionID("session-1"),
                leaseID: nil,
                action: "device_boot",
                target: "udid",
                result: "ok",
                durationMs: index
            )
            try await writer.append(event)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path + ".1"))
    }

    func testEventHubReplaysAfterID() async throws {
        let hub = EventHub()
        let payload = DeviceStateChangedPayload(
            deviceID: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            state: .booted,
            previousState: .booting
        )
        let first = try await hub.publish(type: .deviceStateChanged, payload: payload)
        let second = try await hub.publish(type: .deviceStateChanged, payload: payload)
        XCTAssertEqual(first.id, "1")
        XCTAssertEqual(second.id, "2")

        let (initial, _) = await hub.subscribe(after: "1")
        XCTAssertEqual(initial.map(\.id), ["2"])

        let (emptyInitial, stream) = await hub.subscribe(after: nil)
        XCTAssertTrue(emptyInitial.isEmpty)
        let third = try await hub.publish(type: .leaseChanged, payload: LeaseChangedPayload(
            lease: Lease(
                id: LeaseID("lease-1"),
                deviceID: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
                sessionID: SessionID("session-1"),
                mode: .control,
                ownerName: "agent",
                acquiredAt: Date(timeIntervalSince1970: 1),
                expiresAt: Date(timeIntervalSince1970: 2)
            ),
            reason: "acquired"
        ))
        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertEqual(received?.id, third.id)
        let count = await hub.eventCount()
        XCTAssertEqual(count, 3)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter AuditAndEventTests
```

Expected: FAIL với `cannot find 'AuditWriter' in scope`.

- [ ] **Step 3: Viết audit và event hub**

Create `Sources/OpenSimDaemon/Audit/AuditWriter.swift`:

```swift
import Foundation
import OpenSimCore

public actor AuditWriter {
    private let fileURL: URL
    private let maxBytes: Int
    private let fileManager: FileManager

    public init(fileURL: URL, maxBytes: Int = 50 * 1_024 * 1_024, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.fileManager = fileManager
    }

    public func append(_ event: AuditEvent) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var line = try OpenSimJSON.encoder(pretty: false).encode(event)
        line.append(0x0A)
        if currentSize() + line.count > maxBytes {
            try rotate()
        }
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    private func currentSize() -> Int {
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    private func rotate() throws {
        let base = fileURL.path
        for index in stride(from: 4, through: 1, by: -1) {
            let source = "\(base).\(index)"
            let destination = "\(base).\(index + 1)"
            guard fileManager.fileExists(atPath: source) else {
                continue
            }
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: destination)
            }
            try fileManager.moveItem(atPath: source, toPath: destination)
        }
        if fileManager.fileExists(atPath: base) {
            if fileManager.fileExists(atPath: "\(base).1") {
                try fileManager.removeItem(atPath: "\(base).1")
            }
            try fileManager.moveItem(atPath: base, toPath: "\(base).1")
        }
    }
}
```

Create `Sources/OpenSimDaemon/Events/EventHub.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

public actor EventHub {
    private var nextID = 1
    private var buffer: [DaemonEvent] = []
    private var subscribers: [UUID: AsyncStream<DaemonEvent>.Continuation] = [:]
    private let maxBuffer = 256
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func publish<T: Encodable & Sendable>(
        type: EventType,
        payload: T
    ) throws -> DaemonEvent {
        let event = DaemonEvent(
            id: "\(nextID)",
            type: type,
            timestamp: now(),
            data: try JSONValue.from(payload)
        )
        nextID += 1
        buffer.append(event)
        if buffer.count > maxBuffer {
            buffer.removeFirst(buffer.count - maxBuffer)
        }
        for continuation in subscribers.values {
            continuation.yield(event)
        }
        return event
    }

    public func subscribe(
        after lastEventID: String?
    ) -> (initial: [DaemonEvent], stream: AsyncStream<DaemonEvent>) {
        let initial = lastEventID == nil ? [] : replay(after: lastEventID)
        let (stream, continuation) = AsyncStream<DaemonEvent>.makeStream()
        let identifier = UUID()
        subscribers[identifier] = continuation
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeSubscriber(identifier)
            }
        }
        return (initial, stream)
    }

    public func replay(after lastEventID: String?) -> [DaemonEvent] {
        guard let lastEventID, let last = Int(lastEventID) else {
            return buffer
        }
        return buffer.filter { event in
            guard let identifier = Int(event.id) else {
                return false
            }
            return identifier > last
        }
    }

    public func eventCount() -> Int {
        buffer.count
    }

    private func removeSubscriber(_ identifier: UUID) {
        subscribers.removeValue(forKey: identifier)
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter AuditAndEventTests
```

Expected: PASS; `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimDaemon/Audit Sources/OpenSimDaemon/Events Tests/OpenSimDaemonTests/AuditAndEventTests.swift
git commit -m "feat(daemon): add audit writer and event hub"
```

### Task 6: OperationDispatcher

**Files:**
- Create: `Sources/OpenSimDaemon/Operations/OperationDispatcher.swift`
- Test: `Tests/OpenSimDaemonTests/OperationDispatcherTests.swift`

**Interfaces:**
- Consumes: `OperationCatalog.plan3()`, `BridgeOperationExecutor`, `SessionManager`, `LeaseManager`, `AuditWriter`, `EventHub`, `SimulatorBridge`, `OperationRequest`.
- Produces: `OperationDispatcher(catalog:executor:bridge:sessions:leases:audit:events:logger:).dispatch(_:) -> OperationResult`; xử lý `session_list`, `session_acquire`, `session_release`; guard `requiredService`, lease, confirm.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/OperationDispatcherTests.swift`:

```swift
import Logging
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimBridge
@testable import OpenSimCore

actor DaemonStubSimctlExecutor: SimctlExecuting {
    private var outputs: [SimctlOutput] = []

    func enqueue(_ output: SimctlOutput) {
        outputs.append(output)
    }

    func run(_ command: SimctlCommand, timeout: Duration) async throws -> SimctlOutput {
        guard !outputs.isEmpty else {
            throw OpenSimError(code: .internalError, message: "stub has no output")
        }
        return outputs.removeFirst()
    }
}

struct DispatcherTestDoctor: DoctorReporting {
    func doctorReport() async throws -> DoctorReport {
        throw OpenSimError(code: .internalError, message: "not used")
    }
}

final class OperationDispatcherTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    private func makeServices(catalog: OperationCatalog) -> (OperationDispatcher, SessionManager, LeaseManager, EventHub) {
        let executor = DaemonStubSimctlExecutor()
        let devices = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        let runtimes = SimctlRuntimeService(executor: executor, timeout: .seconds(5))
        let apps = SimctlAppService(executor: executor, timeout: .seconds(5))
        let logs = SimctlLogService(executor: executor, timeout: .seconds(5))
        let bridge = SimctlBridge(
            devices: devices,
            runtimes: runtimes,
            apps: apps,
            logs: logs,
            crashReports: CrashReportService(devices: devices),
            doctor: DispatcherTestDoctor(),
            capabilityProvider: {
                BridgeCapabilities(
                    render: .unavailable,
                    hid: .unavailable,
                    accessibility: .unavailable,
                    screenshot: .available,
                    video: .available,
                    watch: .unavailable,
                    tv: .unavailable
                )
            }
        )
        let sessions = SessionManager()
        let leases = LeaseManager(takeoverGrace: 0)
        let events = EventHub()
        let auditURL = URL(fileURLWithPath: "/tmp/opensim-dispatch-\(UUID().uuidString).jsonl")
        let dispatcher = OperationDispatcher(
            catalog: catalog,
            executor: BridgeOperationExecutor(bridge: bridge, crashReports: bridge, doctor: bridge, catalog: catalog),
            bridge: bridge,
            sessions: sessions,
            leases: leases,
            audit: AuditWriter(fileURL: auditURL),
            events: events,
            logger: Logger(label: "test")
        )
        return (dispatcher, sessions, leases, events)
    }

    func testWriteWithoutSessionReturnsLeaseRequired() async throws {
        let (dispatcher, _, _, _) = makeServices(catalog: OperationCatalog.plan3())
        do {
            _ = try await dispatcher.dispatch(OperationRequest(
                operation: "device_shutdown",
                parameters: ["device": udid.rawValue, "wait": "false"]
            ))
            XCTFail("expected lease_required")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "lease_required")
        }
    }

    func testDestructiveWithoutConfirmReturnsConfirmationRequired() async throws {
        let (dispatcher, sessions, _, _) = makeServices(catalog: OperationCatalog.plan3())
        let session = await sessions.create(clientKind: "test", clientName: "test")
        do {
            _ = try await dispatcher.dispatch(OperationRequest(
                operation: "device_erase",
                parameters: ["device": udid.rawValue, "confirm": "false"],
                sessionID: session.id
            ))
            XCTFail("expected confirmation_required")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "confirmation_required")
        }
    }

    func testOptionalServiceReturnsCapabilityUnavailable() async throws {
        let extra = Operation(
            cliPath: ["ui", "tap"],
            mcpName: "ui_tap",
            summary: "Tap",
            requiresControlLease: false,
            destructive: false,
            readOnly: false,
            parameters: [OperationParameter(name: "device", type: "string", required: true)],
            requiredService: .screen
        )
        var catalog = OperationCatalog.plan3()
        catalog.register(extra)
        let (dispatcher, _, _, _) = makeServices(catalog: catalog)
        do {
            _ = try await dispatcher.dispatch(OperationRequest(
                operation: "ui_tap",
                parameters: ["device": udid.rawValue]
            ))
            XCTFail("expected capability_unavailable")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "capability_unavailable")
            XCTAssertEqual(error.details["capability"], "screen")
        }
    }

    func testSessionListRequiresNoLease() async throws {
        let (dispatcher, sessions, _, _) = makeServices(catalog: OperationCatalog.plan3())
        _ = await sessions.create(clientKind: "cli", clientName: "test")
        let result = try await dispatcher.dispatch(OperationRequest(operation: "session_list"))
        let list = try result.decoded(SessionListResult.self)
        XCTAssertEqual(list.sessions.count, 1)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter OperationDispatcherTests
```

Expected: FAIL với `cannot find 'OperationDispatcher' in scope`.

- [ ] **Step 3: Viết dispatcher**

Create `Sources/OpenSimDaemon/Operations/OperationDispatcher.swift`:

```swift
import Foundation
import Logging
import OpenSimBridge
import OpenSimCore
import OpenSimProtocol

public struct OperationDispatcher: Sendable {
    public let catalog: OperationCatalog
    public let executor: BridgeOperationExecutor
    public let bridge: any SimulatorBridge
    public let sessions: SessionManager
    public let leases: LeaseManager
    public let audit: AuditWriter
    public let events: EventHub
    public let logger: Logger

    public init(
        catalog: OperationCatalog,
        executor: BridgeOperationExecutor,
        bridge: any SimulatorBridge,
        sessions: SessionManager,
        leases: LeaseManager,
        audit: AuditWriter,
        events: EventHub,
        logger: Logger
    ) {
        self.catalog = catalog
        self.executor = executor
        self.bridge = bridge
        self.sessions = sessions
        self.leases = leases
        self.audit = audit
        self.events = events
        self.logger = logger
    }

    public func dispatch(_ request: OperationRequest) async throws -> OperationResult {
        if request.dryRun == true {
            throw OpenSimError.invalidArgument("dryRun is not supported in Plan 3")
        }
        guard let operation = catalog.operation(forMCP: request.operation) else {
            throw OpenSimError.invalidArgument("Unknown operation: \(request.operation)")
        }
        let parameters = try OperationParameters(request.parameters).validated(against: operation)

        switch operation.mcpName {
        case "session_list":
            return try await handleSessionList(request: request, operation: operation)
        case "session_acquire":
            return try await handleSessionAcquire(request: request, operation: operation, parameters: parameters)
        case "session_release":
            return try await handleSessionRelease(request: request, operation: operation, parameters: parameters)
        default:
            break
        }

        if let service = operation.requiredService, !bridge.supports(service) {
            throw OpenSimError.capabilityUnavailable(service.rawValue)
        }
        if operation.destructive, try parameters.bool("confirm", default: false) == false {
            throw OpenSimError.confirmationRequired(action: operation.mcpName)
        }

        var deviceID: DeviceID?
        var lease: Lease?
        if operation.requiresControlLease {
            guard let sessionID = request.sessionID else {
                throw OpenSimError(
                    code: .leaseRequired,
                    message: "A session and control lease are required",
                    details: ["operation": operation.mcpName],
                    recovery: "Create a session and acquire a control lease",
                    retryable: false
                )
            }
            let resolved = try await resolveDevice(parameters)
            deviceID = resolved
            try await leases.validate(device: resolved, leaseID: request.leaseID, session: sessionID)
            if let leaseID = request.leaseID {
                lease = await leases.activeLeases().first { $0.id == leaseID }
            }
        }

        let started = Date()
        do {
            let data = try await executor.execute(operation: operation.mcpName, parameters: request.parameters)
            let auditEvent = await record(
                operation: operation,
                request: request,
                deviceID: deviceID,
                lease: lease,
                result: "ok",
                started: started
            )
            if let auditEvent {
                _ = try? await events.publish(type: .auditAppended, payload: AuditAppendedPayload(event: auditEvent))
            }
            return OperationResult(
                operation: operation.mcpName,
                data: data,
                auditID: auditEvent?.id
            )
        } catch let error as OpenSimError {
            _ = await record(
                operation: operation,
                request: request,
                deviceID: deviceID,
                lease: lease,
                result: "error:\(error.code)",
                started: started
            )
            throw error
        } catch {
            _ = await record(
                operation: operation,
                request: request,
                deviceID: deviceID,
                lease: lease,
                result: "error:internal",
                started: started
            )
            throw OpenSimError(code: .internalError, message: String(describing: error))
        }
    }

    private func handleSessionList(
        request: OperationRequest,
        operation: Operation
    ) async throws -> OperationResult {
        let sessions = await sessions.list()
        let leases = await leases.activeLeases()
        let result = SessionListResult(sessions: sessions, leases: leases)
        let data = try OpenSimJSON.encoder(pretty: false).encode(result)
        let auditEvent = await record(
            operation: operation,
            request: request,
            deviceID: nil,
            lease: nil,
            result: "ok",
            started: Date()
        )
        return OperationResult(operation: operation.mcpName, data: data, auditID: auditEvent?.id)
    }

    private func handleSessionAcquire(
        request: OperationRequest,
        operation: Operation,
        parameters: OperationParameters
    ) async throws -> OperationResult {
        guard let sessionID = request.sessionID else {
            throw OpenSimError.invalidArgument("session_acquire requires sessionID")
        }
        guard let session = await sessions.session(sessionID) else {
            throw OpenSimError.invalidArgument("Session does not exist: \(sessionID.rawValue)")
        }
        let device = try await resolveDevice(parameters)
        let modeRaw = parameters.optionalString("mode") ?? LeaseMode.control.rawValue
        guard let mode = LeaseMode(rawValue: modeRaw) else {
            throw OpenSimError.invalidArgument("mode must be control or observe")
        }
        let ttl = try parameters.int("ttlSeconds", default: 300)
        let lease = try await leases.acquire(
            device: device,
            session: sessionID,
            mode: mode,
            ttlSeconds: ttl,
            ownerName: session.clientName,
            takeover: false
        )
        _ = try? await events.publish(type: .leaseChanged, payload: LeaseChangedPayload(lease: lease, reason: "acquired"))
        let data = try OpenSimJSON.encoder(pretty: false).encode(lease)
        let auditEvent = await record(
            operation: operation,
            request: request,
            deviceID: device,
            lease: lease,
            result: "ok",
            started: Date()
        )
        return OperationResult(operation: operation.mcpName, data: data, auditID: auditEvent?.id)
    }

    private func handleSessionRelease(
        request: OperationRequest,
        operation: Operation,
        parameters: OperationParameters
    ) async throws -> OperationResult {
        guard let sessionID = request.sessionID else {
            throw OpenSimError.invalidArgument("session_release requires sessionID")
        }
        let leaseID = LeaseID(try parameters.string("leaseID"))
        let released = await leases.release(leaseID, session: sessionID)
        let ack = OperationAck(ok: released, message: released ? "Lease released" : "Lease not found or not owned by this session")
        let data = try OpenSimJSON.encoder(pretty: false).encode(ack)
        let auditEvent = await record(
            operation: operation,
            request: request,
            deviceID: nil,
            lease: nil,
            result: released ? "ok" : "error:lease_revoked",
            started: Date()
        )
        return OperationResult(operation: operation.mcpName, data: data, auditID: auditEvent?.id)
    }

    private func resolveDevice(_ parameters: OperationParameters) async throws -> DeviceID {
        let query = parameters.optionalString("device")
        let devices = try await bridge.devices.listDevices()
        return try DeviceResolver.resolve(query: query, in: devices).id
    }

    private func record(
        operation: Operation,
        request: OperationRequest,
        deviceID: DeviceID?,
        lease: Lease?,
        result: String,
        started: Date
    ) async -> AuditEvent? {
        let event = AuditEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            actor: request.sessionID?.rawValue ?? "cli",
            sessionID: request.sessionID,
            leaseID: lease?.id ?? request.leaseID,
            action: operation.mcpName,
            target: deviceID?.rawValue ?? request.parameters["device"] ?? operation.mcpName,
            result: result,
            durationMs: Int(Date().timeIntervalSince(started) * 1_000)
        )
        do {
            try await audit.append(event)
            return event
        } catch {
            logger.error("Audit append failed: \(String(describing: error))")
            return nil
        }
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter OperationDispatcherTests
```

Expected: PASS; `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimDaemon/Operations Tests/OpenSimDaemonTests/OperationDispatcherTests.swift
git commit -m "feat(daemon): add catalog operation dispatcher"
```

### Task 7: HTTP server, security middleware, health và devices

**Files:**
- Create: `Sources/OpenSimProtocol/DeviceActions.swift`
- Create: `Sources/OpenSimDaemon/Server/DaemonServices.swift`
- Create: `Sources/OpenSimDaemon/Server/DaemonRouteProvider.swift`
- Create: `Sources/OpenSimDaemon/Server/DaemonHTTP.swift`
- Create: `Sources/OpenSimDaemon/Server/SecurityMiddleware.swift`
- Create: `Sources/OpenSimDaemon/Server/DaemonServer.swift`
- Create: `Sources/OpenSimDaemon/Server/Routes/HealthRoutes.swift`
- Create: `Sources/OpenSimDaemon/Server/Routes/DeviceRoutes.swift`
- Test: `Tests/OpenSimDaemonTests/SecurityTests.swift`
- Test: `Tests/OpenSimDaemonTests/HTTPRoutesTests.swift`

**Interfaces:**
- Consumes: Hummingbird `Router`, `Request`, `Response`, `Application`, `BasicRequestContext`, `RouterMiddleware`; `DaemonServices`; `OperationDispatcher`.
- Produces: `DeviceActionRequest`, `DeviceActionResponse`; `DaemonServices`; `DaemonRouteProvider`, `DaemonRouteContext`; `DaemonHTTP.json`, `.envelopeError`, `.decode`; `SecurityMiddleware`, `RequestSecurity`; `DaemonServer.start(services:token:port:routeProviders:)`; `RunningDaemonServer.stop()`; health/device routes.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/SecurityTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon

final class SecurityTests: XCTestCase {
    func testHostPolicy() {
        XCTAssertTrue(RequestSecurity.isLoopbackHost("127.0.0.1:5555"))
        XCTAssertTrue(RequestSecurity.isLoopbackHost("localhost:1234"))
        XCTAssertTrue(RequestSecurity.isLoopbackHost("[::1]:1234"))
        XCTAssertTrue(RequestSecurity.isLoopbackHost("127.0.0.1"))
        XCTAssertFalse(RequestSecurity.isLoopbackHost("evil.example:1234"))
        XCTAssertFalse(RequestSecurity.isLoopbackHost(nil))
    }

    func testOriginPolicy() {
        XCTAssertTrue(RequestSecurity.isAllowedOrigin(nil))
        XCTAssertTrue(RequestSecurity.isAllowedOrigin("http://127.0.0.1:5555"))
        XCTAssertTrue(RequestSecurity.isAllowedOrigin("http://localhost:9090"))
        XCTAssertFalse(RequestSecurity.isAllowedOrigin("https://evil.example"))
        XCTAssertFalse(RequestSecurity.isAllowedOrigin("file:///tmp/page.html"))
    }

    func testTokenPolicy() {
        XCTAssertTrue(RequestSecurity.isAuthorized("Bearer secret", token: "secret"))
        XCTAssertFalse(RequestSecurity.isAuthorized("Bearer wrong", token: "secret"))
        XCTAssertFalse(RequestSecurity.isAuthorized(nil, token: "secret"))
        XCTAssertFalse(RequestSecurity.isAuthorized("secret", token: "secret"))
    }
}
```

Create `Tests/OpenSimDaemonTests/HTTPRoutesTests.swift`:

```swift
import Logging
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimBridge
@testable import OpenSimCore

final class HTTPRoutesTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    private func makeServer(executor: DaemonStubSimctlExecutor) async throws -> (RunningDaemonServer, String) {
        let devices = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        let runtimes = SimctlRuntimeService(executor: executor, timeout: .seconds(5))
        let apps = SimctlAppService(executor: executor, timeout: .seconds(5))
        let logs = SimctlLogService(executor: executor, timeout: .seconds(5))
        let bridge = SimctlBridge(
            devices: devices,
            runtimes: runtimes,
            apps: apps,
            logs: logs,
            crashReports: CrashReportService(devices: devices),
            doctor: DispatcherTestDoctor(),
            capabilityProvider: {
                BridgeCapabilities(
                    render: .unavailable,
                    hid: .unavailable,
                    accessibility: .unavailable,
                    screenshot: .available,
                    video: .available,
                    watch: .unavailable,
                    tv: .unavailable
                )
            }
        )
        let catalog = OperationCatalog.plan3()
        let sessions = SessionManager()
        let leases = LeaseManager(takeoverGrace: 0)
        let events = EventHub()
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-http-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audit = AuditWriter(fileURL: root.appendingPathComponent("audit.jsonl"))
        let dispatcher = OperationDispatcher(
            catalog: catalog,
            executor: BridgeOperationExecutor(bridge: bridge, crashReports: bridge, doctor: bridge, catalog: catalog),
            bridge: bridge,
            sessions: sessions,
            leases: leases,
            audit: audit,
            events: events,
            logger: Logger(label: "test")
        )
        let port = try PortAllocator.freePort()
        let state = DaemonState(
            pid: 1,
            port: port,
            token: "test-token",
            version: "0.1.0",
            xcodeVersion: "27.1",
            startedAt: Date(timeIntervalSince1970: 1_797_000_000)
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
            token: "test-token",
            port: port,
            routeProviders: []
        )
        return (server, "test-token")
    }

    func testHealthNeedsNoTokenAndDevicesNeedsToken() async throws {
        let executor = DaemonStubSimctlExecutor()
        let (server, token) = try await makeServer(executor: executor)
        defer { server.stop() }
        let base = URL(string: "http://127.0.0.1:\(server.port)")!

        let health = try await URLSession.shared.data(from: base.appendingPathComponent("v1/health"))
        XCTAssertEqual((health.1 as? HTTPURLResponse)?.statusCode, 200)
        let healthEnvelope = try OpenSimJSON.decoder().decode(Envelope<HealthResponse>.self, from: health.0)
        XCTAssertTrue(healthEnvelope.ok)
        XCTAssertEqual(healthEnvelope.data?.protocolVersion, 1)

        let unauthorized = try await URLSession.shared.data(from: base.appendingPathComponent("v1/devices"))
        XCTAssertEqual((unauthorized.1 as? HTTPURLResponse)?.statusCode, 401)

        await executor.enqueue(SimctlOutput(
            status: 0,
            stdout: Data("""
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"95B3747B-7065-447E-AB1E-53065142C3FC","name":"iPhone Air","state":"Booted","isAvailable":true}]}}
            """.utf8),
            stderr: Data()
        ))
        var request = URLRequest(url: base.appendingPathComponent("v1/devices"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let authorized = try await URLSession.shared.data(for: request)
        XCTAssertEqual((authorized.1 as? HTTPURLResponse)?.statusCode, 200)
        let devicesEnvelope = try OpenSimJSON.decoder().decode(Envelope<[Device]>.self, from: authorized.0)
        XCTAssertEqual(devicesEnvelope.data?.map(\.id), [udid])
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter SecurityTests
swift test --filter HTTPRoutesTests
```

Expected: FAIL với `cannot find 'RequestSecurity' in scope` và `cannot find 'DaemonServer' in scope`.

- [ ] **Step 3: Viết server foundation**

Create `Sources/OpenSimProtocol/DeviceActions.swift`:

```swift
import Foundation
import OpenSimCore

public struct DeviceActionRequest: Codable, Sendable, Equatable {
    public var action: String
    public var wait: Bool?
    public var name: String?
    public var confirm: Bool?
    public var sessionID: SessionID?
    public var leaseID: LeaseID?

    public init(
        action: String,
        wait: Bool? = nil,
        name: String? = nil,
        confirm: Bool? = nil,
        sessionID: SessionID? = nil,
        leaseID: LeaseID? = nil
    ) {
        self.action = action
        self.wait = wait
        self.name = name
        self.confirm = confirm
        self.sessionID = sessionID
        self.leaseID = leaseID
    }
}

public struct DeviceActionResponse: Codable, Sendable, Equatable {
    public var action: String
    public var device: Device?
    public var ack: OperationAck?

    public init(action: String, device: Device?, ack: OperationAck?) {
        self.action = action
        self.device = device
        self.ack = ack
    }
}
```

Create `Sources/OpenSimDaemon/Server/DaemonServices.swift`:

```swift
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
```

Create `Sources/OpenSimDaemon/Server/DaemonRouteProvider.swift`:

```swift
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
    func registerRoutes(
        on router: Router<BasicRequestContext>,
        context: DaemonRouteContext
    ) throws
}
```

Create `Sources/OpenSimDaemon/Server/DaemonHTTP.swift`:

```swift
import Foundation
import Hummingbird
import NIOCore
import OpenSimCore
import OpenSimProtocol

public enum DaemonHTTP {
    public static func json<T: Codable & Sendable>(
        _ value: T,
        status: HTTPResponseStatus = .ok
    ) throws -> Response {
        let envelope = Envelope<T>.success(value, requestId: RequestID.make(), durationMs: 0)
        let data = try OpenSimJSON.encoder(pretty: false).encode(envelope)
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: [UInt8](data)))
        )
    }

    public static func envelopeError(
        _ error: OpenSimError,
        status: HTTPResponseStatus
    ) -> Response {
        let envelope = Envelope<EmptyPayload>.failure(error, requestId: RequestID.make(), durationMs: 0)
        let data = (try? OpenSimJSON.encoder(pretty: false).encode(envelope)) ?? Data()
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: [UInt8](data)))
        )
    }

    public static func decode<T: Decodable>(
        _ request: Request,
        as type: T.Type
    ) async throws -> T {
        let buffer = try await request.body.collect(upTo: 8 * 1_024 * 1_024)
        let data = Data(buffer.readableBytesView)
        return try OpenSimJSON.decoder().decode(T.self, from: data)
    }
}
```

Create `Sources/OpenSimDaemon/Server/SecurityMiddleware.swift`:

```swift
import Foundation
import Hummingbird
import OpenSimCore

public enum RequestSecurity {
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
        return ["127.0.0.1", "localhost", "::1"].contains(host.lowercased())
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
        return ["127.0.0.1", "localhost", "::1"].contains(host.lowercased())
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
        guard RequestSecurity.isLoopbackHost(request.headers["host"]) else {
            return DaemonHTTP.envelopeError(
                OpenSimError(code: .permissionDenied, message: "Host is not loopback"),
                status: .forbidden
            )
        }
        guard RequestSecurity.isAllowedOrigin(request.headers["origin"]) else {
            return DaemonHTTP.envelopeError(
                OpenSimError(code: .permissionDenied, message: "Origin is not loopback"),
                status: .forbidden
            )
        }
        if request.uri.path == "/v1/health" {
            return try await next(request, context)
        }
        guard RequestSecurity.isAuthorized(request.headers["authorization"], token: token) else {
            return DaemonHTTP.envelopeError(
                OpenSimError(code: .permissionDenied, message: "Missing or invalid bearer token"),
                status: .unauthorized
            )
        }
        return try await next(request, context)
    }
}
```

Create `Sources/OpenSimDaemon/Server/Routes/HealthRoutes.swift`:

```swift
import Hummingbird

public enum HealthRoutes {
    public static func register(on router: Router<BasicRequestContext>, services: DaemonServices) {
        router.get("/v1/health") { _, _ in
            try DaemonHTTP.json(services.healthResponse())
        }
    }
}
```

Create `Sources/OpenSimDaemon/Server/Routes/DeviceRoutes.swift`:

```swift
import Foundation
import Hummingbird
import OpenSimCore
import OpenSimProtocol

public enum DeviceRoutes {
    public static func register(on router: Router<BasicRequestContext>, services: DaemonServices) {
        router.get("/v1/devices") { request, _ in
            var parameters: [String: String] = [:]
            let items = URLComponents(string: "?\(request.uri.query ?? "")")?.queryItems ?? []
            for item in items {
                parameters[item.name] = item.value
            }
            let result = try await services.dispatcher.dispatch(
                OperationRequest(operation: "device_list", parameters: parameters)
            )
            return try DaemonHTTP.json(try result.decoded([Device].self))
        }

        router.get("/v1/devices/:udid") { _, context in
            guard let udid = context.parameters.get("udid") else {
                throw OpenSimError.invalidArgument("Missing device UDID")
            }
            let result = try await services.dispatcher.dispatch(
                OperationRequest(operation: "device_get", parameters: ["device": udid])
            )
            return try DaemonHTTP.json(try result.decoded(Device.self))
        }

        router.post("/v1/devices/:udid/actions") { request, context in
            guard let udid = context.parameters.get("udid") else {
                throw OpenSimError.invalidArgument("Missing device UDID")
            }
            let body = try await DaemonHTTP.decode(request, as: DeviceActionRequest.self)
            return try await performAction(udid: udid, body: body, services: services)
        }
    }

    private static func performAction(
        udid: String,
        body: DeviceActionRequest,
        services: DaemonServices
    ) async throws -> Response {
        let operation: String
        var parameters: [String: String] = ["device": udid]
        switch body.action {
        case "boot":
            operation = "device_boot"
            parameters["wait"] = body.wait == true ? "true" : "false"
        case "shutdown":
            operation = "device_shutdown"
            parameters["wait"] = body.wait == true ? "true" : "false"
        case "erase":
            operation = "device_erase"
            parameters["confirm"] = body.confirm == true ? "true" : "false"
        case "delete":
            operation = "device_delete"
            parameters["confirm"] = body.confirm == true ? "true" : "false"
        case "rename":
            operation = "device_rename"
            guard let name = body.name else {
                throw OpenSimError.invalidArgument("rename requires name")
            }
            parameters["name"] = name
        default:
            throw OpenSimError.invalidArgument("Unknown device action: \(body.action)")
        }
        let result = try await services.dispatcher.dispatch(OperationRequest(
            operation: operation,
            parameters: parameters,
            sessionID: body.sessionID,
            leaseID: body.leaseID
        ))
        if operation == "device_delete" {
            let ack = try result.decoded(OperationAck.self)
            return try DaemonHTTP.json(DeviceActionResponse(action: body.action, device: nil, ack: ack))
        }
        let device = try result.decoded(Device.self)
        return try DaemonHTTP.json(DeviceActionResponse(action: body.action, device: device, ack: nil))
    }
}
```

Create `Sources/OpenSimDaemon/Server/DaemonServer.swift`:

```swift
import Foundation
import Hummingbird
import OpenSimCore
import OpenSimProtocol

public final class RunningDaemonServer: @unchecked Sendable {
    public let port: Int
    private let application: Application<Router<BasicRequestContext>>
    private let task: Task<Void, Error>

    init(
        port: Int,
        application: Application<Router<BasicRequestContext>>,
        task: Task<Void, Error>
    ) {
        self.port = port
        self.application = application
        self.task = task
    }

    public func stop() {
        application.server.shutdown()
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
        HealthRoutes.register(on: router, services: services)
        DeviceRoutes.register(on: router, services: services)

        let baseURL = try XCTUnwrapURL("http://127.0.0.1:\(port)")
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
        return RunningDaemonServer(port: port, application: application, task: task)
    }

    private static func waitUntilHealthy(port: Int) async throws {
        let url = try XCTUnwrapURL("http://127.0.0.1:\(port)/v1/health")
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
}

private func XCTUnwrapURL(_ value: String) throws -> URL {
    guard let url = URL(string: value) else {
        throw OpenSimError(code: .internalError, message: "Invalid URL: \(value)")
    }
    return url
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter SecurityTests
swift test --filter HTTPRoutesTests
```

Expected: PASS; `SecurityTests` có `Executed 3 tests, with 0 failures`; `HTTPRoutesTests` có `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimProtocol/DeviceActions.swift Sources/OpenSimDaemon/Server Tests/OpenSimDaemonTests/SecurityTests.swift Tests/OpenSimDaemonTests/HTTPRoutesTests.swift
git commit -m "feat(daemon): add http server security and device routes"
```

### Task 8: Session/lease/operation routes và error envelope

**Files:**
- Create: `Sources/OpenSimDaemon/Server/ErrorEnvelopeMiddleware.swift`
- Create: `Sources/OpenSimDaemon/Server/Routes/SessionRoutes.swift`
- Create: `Sources/OpenSimDaemon/Server/Routes/OperationRoutes.swift`
- Modify: `Sources/OpenSimDaemon/Server/DaemonServer.swift`
- Modify: `Sources/OpenSimDaemon/Server/DaemonHTTP.swift`
- Test: `Tests/OpenSimDaemonTests/SessionAndOperationRoutesTests.swift`

**Interfaces:**
- Consumes: `SessionManager`, `LeaseManager`, `OperationDispatcher`, `CreateSessionRequest`, `AcquireLeaseRequest`, `HeartbeatRequest`, `LeaseReleaseResult`.
- Produces: `ErrorEnvelopeMiddleware`; `DaemonHTTP.status(for:)`; routes `/v1/sessions`, `/v1/leases`, `/v1/operations`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/SessionAndOperationRoutesTests.swift`:

```swift
import Logging
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimBridge
@testable import OpenSimCore

struct RouteTestHarness {
    let server: RunningDaemonServer
    let token: String
    let services: DaemonServices
    let executor: DaemonStubSimctlExecutor

    static func start(
        executor: DaemonStubSimctlExecutor,
        routeProviders: [any DaemonRouteProvider] = []
    ) async throws -> RouteTestHarness {
        let devices = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        let runtimes = SimctlRuntimeService(executor: executor, timeout: .seconds(5))
        let apps = SimctlAppService(executor: executor, timeout: .seconds(5))
        let logs = SimctlLogService(executor: executor, timeout: .seconds(5))
        let bridge = SimctlBridge(
            devices: devices,
            runtimes: runtimes,
            apps: apps,
            logs: logs,
            crashReports: CrashReportService(devices: devices),
            doctor: DispatcherTestDoctor(),
            capabilityProvider: {
                BridgeCapabilities(
                    render: .unavailable,
                    hid: .unavailable,
                    accessibility: .unavailable,
                    screenshot: .available,
                    video: .available,
                    watch: .unavailable,
                    tv: .unavailable
                )
            }
        )
        let catalog = OperationCatalog.plan3()
        let sessions = SessionManager()
        let leases = LeaseManager(takeoverGrace: 0)
        let events = EventHub()
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-routes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audit = AuditWriter(fileURL: root.appendingPathComponent("audit.jsonl"))
        let dispatcher = OperationDispatcher(
            catalog: catalog,
            executor: BridgeOperationExecutor(bridge: bridge, crashReports: bridge, doctor: bridge, catalog: catalog),
            bridge: bridge,
            sessions: sessions,
            leases: leases,
            audit: audit,
            events: events,
            logger: Logger(label: "test")
        )
        let port = try PortAllocator.freePort()
        let state = DaemonState(
            pid: 1,
            port: port,
            token: "test-token",
            version: "0.1.0",
            xcodeVersion: "27.1",
            startedAt: Date(timeIntervalSince1970: 1_797_000_000)
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
            token: "test-token",
            port: port,
            routeProviders: routeProviders
        )
        return RouteTestHarness(server: server, token: "test-token", services: services, executor: executor)
    }

    func send<T: Decodable>(
        _ method: String,
        _ path: String,
        as type: T.Type
    ) async throws -> (Int, Envelope<T>) {
        try await send(method, path, body: Optional<EmptyBody>.none, as: type)
    }

    func send<Body: Encodable, T: Decodable>(
        _ method: String,
        _ path: String,
        body: Body?,
        as type: T.Type
    ) async throws -> (Int, Envelope<T>) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = try OpenSimJSON.decoder().decode(Envelope<T>.self, from: data)
        return (status, envelope)
    }
}

struct EmptyBody: Encodable {}

final class SessionAndOperationRoutesTests: XCTestCase {
    func testLeaseConflictAndObserveFlow() async throws {
        let executor = DaemonStubSimctlExecutor()
        let harness = try await RouteTestHarness.start(executor: executor)
        defer { harness.server.stop() }

        let (_, firstSession) = try await harness.send(
            "POST",
            "/v1/sessions",
            body: CreateSessionRequest(clientKind: "test", clientName: "first"),
            as: Session.self
        )
        let (_, secondSession) = try await harness.send(
            "POST",
            "/v1/sessions",
            body: CreateSessionRequest(clientKind: "test", clientName: "second"),
            as: Session.self
        )

        let (leaseStatus, firstLease) = try await harness.send(
            "POST",
            "/v1/leases",
            body: AcquireLeaseRequest(
                deviceID: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
                sessionID: try XCTUnwrap(firstSession.data?.id),
                mode: .control
            ),
            as: Lease.self
        )
        XCTAssertEqual(leaseStatus, 200)
        XCTAssertEqual(firstLease.data?.mode, .control)

        let (conflictStatus, conflict) = try await harness.send(
            "POST",
            "/v1/leases",
            body: AcquireLeaseRequest(
                deviceID: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
                sessionID: try XCTUnwrap(secondSession.data?.id),
                mode: .control
            ),
            as: Lease.self
        )
        XCTAssertEqual(conflictStatus, 409)
        XCTAssertEqual(conflict.error?.code, "lease_conflict")

        let (observeStatus, observe) = try await harness.send(
            "POST",
            "/v1/leases",
            body: AcquireLeaseRequest(
                deviceID: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
                sessionID: try XCTUnwrap(secondSession.data?.id),
                mode: .observe
            ),
            as: Lease.self
        )
        XCTAssertEqual(observeStatus, 200)
        XCTAssertEqual(observe.data?.mode, .observe)
    }

    func testOperationRoutesListSessions() async throws {
        let executor = DaemonStubSimctlExecutor()
        let harness = try await RouteTestHarness.start(executor: executor)
        defer { harness.server.stop() }
        _ = try await harness.send(
            "POST",
            "/v1/sessions",
            body: CreateSessionRequest(clientKind: "test", clientName: "one"),
            as: Session.self
        )

        let (status, envelope) = try await harness.send(
            "POST",
            "/v1/operations",
            body: OperationRequest(operation: "session_list"),
            as: OperationResult.self
        )
        XCTAssertEqual(status, 200)
        let result = try XCTUnwrap(envelope.data)
        let list = try result.decoded(SessionListResult.self)
        XCTAssertEqual(list.sessions.count, 1)
    }

    func testOperationWithoutLeaseReturnsConflict() async throws {
        let executor = DaemonStubSimctlExecutor()
        let harness = try await RouteTestHarness.start(executor: executor)
        defer { harness.server.stop() }
        let (status, envelope) = try await harness.send(
            "POST",
            "/v1/operations",
            body: OperationRequest(operation: "device_shutdown", parameters: ["device": "95B3747B-7065-447E-AB1E-53065142C3FC"]),
            as: OperationResult.self
        )
        XCTAssertEqual(status, 409)
        XCTAssertEqual(envelope.error?.code, "lease_required")
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter SessionAndOperationRoutesTests
```

Expected: FAIL với `cannot find type 'ErrorEnvelopeMiddleware' in scope` hoặc 404 route.

- [ ] **Step 3: Viết routes và error middleware**

Create `Sources/OpenSimDaemon/Server/ErrorEnvelopeMiddleware.swift`:

```swift
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
```

Modify `Sources/OpenSimDaemon/Server/DaemonHTTP.swift`: thêm trước dấu `}` cuối enum:

```swift
    public static func status(for error: OpenSimError) -> HTTPResponseStatus {
        switch error.code {
        case ErrorCode.invalidArgument.rawValue:
            return .badRequest
        case ErrorCode.deviceNotFound.rawValue:
            return .notFound
        case ErrorCode.deviceBusy.rawValue,
             ErrorCode.leaseRequired.rawValue,
             ErrorCode.leaseConflict.rawValue,
             ErrorCode.leaseRevoked.rawValue,
             ErrorCode.storageInUse.rawValue:
            return .conflict
        case ErrorCode.confirmationRequired.rawValue:
            return .badRequest
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
```

Create `Sources/OpenSimDaemon/Server/Routes/SessionRoutes.swift`:

```swift
import Foundation
import Hummingbird
import OpenSimCore
import OpenSimProtocol

public enum SessionRoutes {
    public static func register(on router: Router<BasicRequestContext>, services: DaemonServices) {
        router.post("/v1/sessions") { request, _ in
            let body = try await DaemonHTTP.decode(request, as: CreateSessionRequest.self)
            let session = await services.sessions.create(clientKind: body.clientKind, clientName: body.clientName)
            _ = try? await services.events.publish(type: .sessionCreated, payload: SessionChangedPayload(session: session))
            await audit(services: services, action: "session.create", target: session.id.rawValue, sessionID: session.id, leaseID: nil)
            return try DaemonHTTP.json(session)
        }

        router.delete("/v1/sessions/:id") { _, context in
            guard let raw = context.parameters.get("id") else {
                throw OpenSimError.invalidArgument("Missing session id")
            }
            let sessionID = SessionID(raw)
            let released = await services.leases.releaseAll(session: sessionID)
            let closed = await services.sessions.close(sessionID)
            if closed {
                _ = try? await services.events.publish(
                    type: .sessionClosed,
                    payload: ["sessionID": raw]
                )
            }
            await audit(services: services, action: "session.close", target: raw, sessionID: sessionID, leaseID: nil)
            return try DaemonHTTP.json(OperationAck(ok: closed, message: "Released \(released.count) leases"))
        }

        router.post("/v1/leases") { request, _ in
            let body = try await DaemonHTTP.decode(request, as: AcquireLeaseRequest.self)
            guard let session = await services.sessions.session(body.sessionID) else {
                throw OpenSimError.invalidArgument("Session does not exist")
            }
            let lease = try await services.leases.acquire(
                device: body.deviceID,
                session: body.sessionID,
                mode: body.mode,
                ttlSeconds: body.ttlSeconds,
                ownerName: body.ownerName ?? session.clientName,
                takeover: body.takeover ?? false
            )
            _ = try? await services.events.publish(type: .leaseChanged, payload: LeaseChangedPayload(lease: lease, reason: "acquired"))
            await audit(services: services, action: "lease.acquire", target: lease.deviceID.rawValue, sessionID: lease.sessionID, leaseID: lease.id)
            return try DaemonHTTP.json(lease)
        }

        router.post("/v1/leases/:id/heartbeat") { request, context in
            guard let raw = context.parameters.get("id") else {
                throw OpenSimError.invalidArgument("Missing lease id")
            }
            let body = try await DaemonHTTP.decode(request, as: HeartbeatRequest.self)
            let lease = try await services.leases.heartbeat(LeaseID(raw), session: body.sessionID, ttlSeconds: body.ttlSeconds)
            _ = try? await services.events.publish(type: .leaseChanged, payload: LeaseChangedPayload(lease: lease, reason: "heartbeat"))
            return try DaemonHTTP.json(lease)
        }

        router.delete("/v1/leases/:id") { request, context in
            guard let raw = context.parameters.get("id") else {
                throw OpenSimError.invalidArgument("Missing lease id")
            }
            let query = URLComponents(string: "?\(request.uri.query ?? "")")?.queryItems ?? []
            guard let sessionRaw = query.first(where: { $0.name == "sessionID" })?.value else {
                throw OpenSimError.invalidArgument("sessionID query parameter is required")
            }
            let leaseID = LeaseID(raw)
            let released = await services.leases.release(leaseID, session: SessionID(sessionRaw))
            if released {
                await audit(services: services, action: "lease.release", target: leaseID.rawValue, sessionID: SessionID(sessionRaw), leaseID: leaseID)
            }
            return try DaemonHTTP.json(LeaseReleaseResult(leaseID: leaseID, released: released))
        }
    }

    private static func audit(
        services: DaemonServices,
        action: String,
        target: String,
        sessionID: SessionID?,
        leaseID: LeaseID?
    ) async {
        let event = AuditEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            actor: sessionID?.rawValue ?? "http",
            sessionID: sessionID,
            leaseID: leaseID,
            action: action,
            target: target,
            result: "ok",
            durationMs: 0
        )
        try? await services.audit.append(event)
    }
}
```

`events.publish(type: .sessionClosed, payload: ["sessionID": raw])`: `[String:String]` Encodable Sendable, works. But payload type `[String:String]`; okay.
`request.uri.query` API risk. Use `request.uri.query` likely.

Create `Sources/OpenSimDaemon/Server/Routes/OperationRoutes.swift`:

```swift
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
```

Modify `DaemonServer.swift` middleware/registration:

```swift
        router.add(middleware: SecurityMiddleware(token: token))
        router.add(middleware: ErrorEnvelopeMiddleware())
        HealthRoutes.register(on: router, services: services)
        DeviceRoutes.register(on: router, services: services)
        SessionRoutes.register(on: router, services: services)
        OperationRoutes.register(on: router, services: services)
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter SessionAndOperationRoutesTests
```

Expected: PASS; `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimDaemon/Server Tests/OpenSimDaemonTests/SessionAndOperationRoutesTests.swift
git commit -m "feat(daemon): add session lease and operation routes"
```

### Task 9: SSE frame và `/v1/events`

**Files:**
- Create: `Sources/OpenSimDaemon/Events/SSEFrame.swift`
- Create: `Sources/OpenSimDaemon/Server/Routes/EventRoutes.swift`
- Modify: `Sources/OpenSimDaemon/Server/DaemonServer.swift`
- Test: `Tests/OpenSimDaemonTests/SSETests.swift`

**Interfaces:**
- Consumes: `DaemonEvent`, `EventHub`, Hummingbird `Response`, `AsyncThrowingStream`, `ByteBuffer`.
- Produces: `SSEFrame.encode(_:)`, `.comment(_:)`; `GET /v1/events` với `Last-Event-ID` replay.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/SSETests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimCore

final class SSETests: XCTestCase {
    func testFrameContainsIDEventAndData() throws {
        let event = DaemonEvent(
            id: "42",
            type: .deviceStateChanged,
            timestamp: Date(timeIntervalSince1970: 1_797_000_000),
            data: try JSONValue.from(DeviceStateChangedPayload(
                deviceID: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
                state: .booted,
                previousState: .booting
            ))
        )
        let frame = try SSEFrame.encode(event)
        XCTAssertTrue(frame.hasPrefix("id: 42\n"))
        XCTAssertTrue(frame.contains("event: device.state.changed\n"))
        XCTAssertTrue(frame.contains("data: {"))
        XCTAssertTrue(frame.hasSuffix("\n\n"))
    }

    func testEventHubReconnectReplay() async throws {
        let hub = EventHub()
        for index in 0..<3 {
            _ = try await hub.publish(
                type: .daemonHealth,
                payload: DaemonHealthPayload(status: "ok", pid: Int32(index), port: 5000 + index)
            )
        }
        let (initial, stream) = await hub.subscribe(after: "1")
        XCTAssertEqual(initial.map(\.id), ["2", "3"])
        let (empty, secondStream) = await hub.subscribe(after: nil)
        XCTAssertTrue(empty.isEmpty)
        var iterator = secondStream.makeAsyncIterator()
        let next = try await hub.publish(type: .daemonHealth, payload: DaemonHealthPayload(status: "ok", pid: 9, port: 6000))
        let received = await iterator.next()
        XCTAssertEqual(received?.id, next.id)
        _ = stream
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter SSETests
```

Expected: FAIL với `cannot find 'SSEFrame' in scope`.

- [ ] **Step 3: Viết SSE frame và route**

Create `Sources/OpenSimDaemon/Events/SSEFrame.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

public enum SSEFrame {
    public static func encode(_ event: DaemonEvent) throws -> String {
        let data = try OpenSimJSON.encoder(pretty: false).encode(event)
        let payload = String(decoding: data, as: UTF8.self)
        return "id: \(event.id)\nevent: \(event.type.rawValue)\ndata: \(payload)\n\n"
    }

    public static func comment(_ text: String) -> String {
        ": \(text)\n\n"
    }
}
```

Create `Sources/OpenSimDaemon/Server/Routes/EventRoutes.swift`:

```swift
import Hummingbird
import NIOCore
import OpenSimProtocol

public enum EventRoutes {
    public static func register(on router: Router<BasicRequestContext>, services: DaemonServices) {
        router.get("/v1/events") { request, _ -> Response in
            let lastEventID = request.headers["last-event-id"]
            let (initial, stream) = await services.events.subscribe(after: lastEventID)
            return makeResponse(initial: initial, stream: stream)
        }
    }

    private static func makeResponse(
        initial: [DaemonEvent],
        stream: AsyncStream<DaemonEvent>
    ) -> Response {
        let body = AsyncThrowingStream<ByteBuffer, Error> { continuation in
            let task = Task {
                do {
                    for event in initial {
                        continuation.yield(ByteBuffer(string: try SSEFrame.encode(event)))
                    }
                    for await event in stream {
                        continuation.yield(ByteBuffer(string: try SSEFrame.encode(event)))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        return Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache",
            ],
            body: .init(asyncSequence: body)
        )
    }
}
```

Modify `DaemonServer.swift` để đăng ký event route:

```swift
        SessionRoutes.register(on: router, services: services)
        OperationRoutes.register(on: router, services: services)
        EventRoutes.register(on: router, services: services)
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter SSETests
```

Expected: PASS; `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimDaemon/Events/SSEFrame.swift Sources/OpenSimDaemon/Server/Routes/EventRoutes.swift Sources/OpenSimDaemon/Server/DaemonServer.swift Tests/OpenSimDaemonTests/SSETests.swift
git commit -m "feat(daemon): add sse frames and event stream"
```

### Task 10: Daemon logger và DaemonRunner

**Files:**
- Create: `Sources/OpenSimDaemon/Support/DaemonLogger.swift`
- Create: `Sources/OpenSimDaemon/Runtime/DaemonRunner.swift`
- Test: `Tests/OpenSimDaemonTests/DaemonLoggerTests.swift`

**Interfaces:**
- Consumes: `OpenSimPaths`, `ProcessLock`, `SimctlBridge.live`, `OperationCatalog.plan3()`, `DaemonServices`, `DaemonServer`, `DaemonStateStore`, `TokenGenerator`, `PortAllocator`.
- Produces: `DaemonLogger.makeLogger(paths:maxBytes:)`; `DaemonRunConfiguration(paths:port:routeProviders:)`; `DaemonRunner.run(configuration:)` chạy đến SIGINT/SIGTERM, ghi/xoá state, giữ lock.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/DaemonLoggerTests.swift`:

```swift
import Logging
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimCore

final class DaemonLoggerTests: XCTestCase {
    func testFileLoggerWritesAndRotates() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-log-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = OpenSimPaths(baseDirectory: root)
        let logger = DaemonLogger.makeLogger(paths: paths, maxBytes: 120)
        for index in 0..<10 {
            logger.info("line \(index) with enough text to rotate the file")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.daemonLogFile.path))
        let files = try FileManager.default.contentsOfDirectory(atPath: paths.logDirectory.path)
        XCTAssertTrue(files.contains("daemon.log"))
        XCTAssertTrue(files.contains { $0.hasPrefix("daemon.log.") })
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter DaemonLoggerTests
```

Expected: FAIL với `cannot find 'DaemonLogger' in scope`.

- [ ] **Step 3: Viết logger và runner**

Create `Sources/OpenSimDaemon/Support/DaemonLogger.swift`:

```swift
import Foundation
import Logging
import OpenSimCore

private final class RotatingFileWriter: @unchecked Sendable {
    private let fileURL: URL
    private let maxBytes: Int
    private let maxFiles: Int
    private let lock = NSLock()

    init(fileURL: URL, maxBytes: Int, maxFiles: Int) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.maxFiles = maxFiles
    }

    func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = Data((line + "\n").utf8)
        let current = size()
        if current + data.count > maxBytes {
            rotate()
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(
                atPath: fileURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func size() -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    private func rotate() {
        let base = fileURL.path
        if maxFiles > 1 {
            for index in stride(from: maxFiles - 1, through: 1, by: -1) {
                let source = "\(base).\(index)"
                let destination = "\(base).\(index + 1)"
                guard FileManager.default.fileExists(atPath: source) else {
                    continue
                }
                try? FileManager.default.removeItem(atPath: destination)
                try? FileManager.default.moveItem(atPath: source, toPath: destination)
            }
        }
        if FileManager.default.fileExists(atPath: base) {
            try? FileManager.default.removeItem(atPath: "\(base).1")
            try? FileManager.default.moveItem(atPath: base, toPath: "\(base).1")
        }
    }
}

public struct RotatingFileLogHandler: LogHandler {
    public var metadata: Logger.Metadata = [:]
    public var logLevel: Logger.Level = .info
    private let label: String
    private let writer: RotatingFileWriter

    public init(label: String, fileURL: URL, maxBytes: Int, maxFiles: Int) {
        self.label = label
        self.writer = RotatingFileWriter(fileURL: fileURL, maxBytes: maxBytes, maxFiles: maxFiles)
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let timestamp = OpenSimDate.string(from: Date())
        writer.write("\(timestamp) \(level) [\(label)] \(message)")
    }
}

public enum DaemonLogger {
    public static func makeLogger(
        paths: OpenSimPaths,
        maxBytes: Int = 10 * 1_024 * 1_024,
        maxFiles: Int = 5
    ) -> Logger {
        let handler = RotatingFileLogHandler(
            label: "dev.opensim.daemon",
            fileURL: paths.daemonLogFile,
            maxBytes: maxBytes,
            maxFiles: maxFiles
        )
        var logger = Logger(label: "dev.opensim.daemon") { _ in handler }
        logger.logLevel = .info
        return logger
    }
}
```

Create `Sources/OpenSimDaemon/Runtime/DaemonRunner.swift`:

```swift
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
        let sessions = SessionManager()
        let leases = LeaseManager()
        let events = EventHub()
        let audit = AuditWriter(fileURL: paths.auditFile)
        let dispatcher = OperationDispatcher(
            catalog: catalog,
            executor: BridgeOperationExecutor(bridge: bridge, crashReports: bridge, doctor: bridge, catalog: catalog),
            bridge: bridge,
            sessions: sessions,
            leases: leases,
            audit: audit,
            events: events,
            logger: logger
        )
        let port = try configuration.port ?? PortAllocator.freePort()
        let token = try TokenGenerator.make()
        let startedAt = Date()
        let state = DaemonState(
            pid: getpid(),
            port: port,
            token: token,
            version: OpenSimVersion.version,
            xcodeVersion: xcode.version,
            startedAt: startedAt
        )
        let capabilities = await bridge.capabilities
        let services = DaemonServices(
            bridge: bridge,
            dispatcher: dispatcher,
            sessions: sessions,
            leases: leases,
            events: events,
            audit: audit,
            state: state,
            capabilities: capabilities
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
            source.setEventHandler { [continuation] in
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
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter DaemonLoggerTests
```

Expected: PASS; `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimDaemon/Support/DaemonLogger.swift Sources/OpenSimDaemon/Runtime Tests/OpenSimDaemonTests/DaemonLoggerTests.swift
git commit -m "feat(daemon): add file logger and daemon runner"
```

### Task 11: LaunchAgent, DaemonClient và DaemonLauncher

**Files:**
- Create: `Sources/OpenSimDaemon/LaunchAgent/LaunchAgentManager.swift`
- Create: `Sources/OpenSimDaemon/Client/DaemonClient.swift`
- Create: `Sources/OpenSimDaemon/Client/DaemonLauncher.swift`
- Test: `Tests/OpenSimDaemonTests/LaunchAgentTests.swift`
- Test: `Tests/OpenSimDaemonTests/DaemonClientTests.swift`

**Interfaces:**
- Consumes: `OpenSimPaths`, `OpenSimVersion`, `DaemonState`, `HealthResponse`, `OperationRequest`, `Session`, `Lease`.
- Produces: `LaunchAgentManager.install()`, `.bootstrap()`, `.bootout()`, `.kickstart()`, `.isLoaded()`, `.defaultPlistURL()`; `DaemonClient.health()`, `.devices()`, `.operation(_:)`, `.createSession(clientKind:clientName:)`, `.closeSession(_:)`, `.acquireLease(_:)`, `.heartbeatLease(_:sessionID:ttlSeconds:)`, `.releaseLease(_:sessionID:)`, `.events(lastEventID:)`; `DaemonLauncher.ensureRunning()`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/LaunchAgentTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimCore

final class LaunchAgentTests: XCTestCase {
    func testPlistContainsDaemonArgumentsAndEnvironment() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = OpenSimPaths(baseDirectory: root)
        let plistURL = root.appendingPathComponent("dev.opensim.daemon.plist")
        let manager = LaunchAgentManager(
            plistURL: plistURL,
            opensimPath: "/usr/local/bin/opensim",
            paths: paths
        )
        try manager.install()
        let data = try Data(contentsOf: plistURL)
        let object = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        XCTAssertEqual(object["Label"] as? String, "dev.opensim.daemon")
        XCTAssertEqual(object["ProgramArguments"] as? [String], ["/usr/local/bin/opensim", "daemon", "run", "--foreground"])
        XCTAssertEqual(object["RunAtLoad"] as? Bool, true)
        let environment = object["EnvironmentVariables"] as? [String: String]
        XCTAssertEqual(environment?["OPENSIM_HOME"], root.path)
    }
}
```

Create `Tests/OpenSimDaemonTests/DaemonClientTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimCore

final class DaemonClientTests: XCTestCase {
    func testClientHealthSessionLeaseAndDevices() async throws {
        let executor = DaemonStubSimctlExecutor()
        let harness = try await RouteTestHarness.start(executor: executor)
        defer { harness.server.stop() }
        let client = DaemonClient(
            baseURL: URL(string: "http://127.0.0.1:\(harness.server.port)")!,
            token: harness.token
        )
        let health = try await client.health()
        XCTAssertEqual(health.status, "ok")

        let session = try await client.createSession(clientKind: "cli", clientName: "test")
        let lease = try await client.acquireLease(AcquireLeaseRequest(
            deviceID: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            sessionID: session.id,
            mode: .control
        ))
        XCTAssertEqual(lease.mode, .control)
        let released = try await client.releaseLease(lease.id, sessionID: session.id)
        XCTAssertTrue(released.released)

        await executor.enqueue(SimctlOutput(
            status: 0,
            stdout: Data("""
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"95B3747B-7065-447E-AB1E-53065142C3FC","name":"iPhone Air","state":"Booted","isAvailable":true}]}}
            """.utf8),
            stderr: Data()
        ))
        let devices = try await client.devices()
        XCTAssertEqual(devices.map(\.name), ["iPhone Air"])
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter LaunchAgentTests
swift test --filter DaemonClientTests
```

Expected: FAIL với `cannot find 'LaunchAgentManager' in scope` và `cannot find 'DaemonClient' in scope`.

- [ ] **Step 3: Viết launch agent và client**

Create `Sources/OpenSimDaemon/LaunchAgent/LaunchAgentManager.swift`:

```swift
import Darwin
import Foundation
import OpenSimCore

public struct LaunchAgentManager: Sendable {
    public static let label = "dev.opensim.daemon"
    public let plistURL: URL
    public let opensimPath: String
    public let paths: OpenSimPaths

    public init(plistURL: URL = LaunchAgentManager.defaultPlistURL(), opensimPath: String, paths: OpenSimPaths) {
        self.plistURL = plistURL
        self.opensimPath = opensimPath
        self.paths = paths
    }

    public static func defaultPlistURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("dev.opensim.daemon.plist")
    }

    public func install() throws {
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let plist: [String: Any] = [
            "Label": LaunchAgentManager.label,
            "ProgramArguments": [opensimPath, "daemon", "run", "--foreground"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Background",
            "ThrottleInterval": 5,
            "StandardOutPath": paths.logDirectory.appendingPathComponent("daemon.out.log").path,
            "StandardErrorPath": paths.logDirectory.appendingPathComponent("daemon.err.log").path,
            "EnvironmentVariables": ["OPENSIM_HOME": paths.baseDirectory.path],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistURL.path)
    }

    public func bootstrap() throws {
        let status = try runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        guard status == 0 else {
            throw OpenSimError(
                code: .daemonUnavailable,
                message: "launchctl bootstrap failed",
                details: ["status": "\(status)"],
                recovery: "Run `launchctl print gui/\(getuid())/dev.opensim.daemon`"
            )
        }
    }

    public func bootout() throws {
        let status = try runLaunchctl(["bootout", "gui/\(getuid())/dev.opensim.daemon"])
        guard status == 0 else {
            throw OpenSimError(
                code: .daemonUnavailable,
                message: "launchctl bootout failed",
                details: ["status": "\(status)"]
            )
        }
    }

    public func kickstart() throws {
        let status = try runLaunchctl(["kickstart", "-k", "gui/\(getuid())/dev.opensim.daemon"])
        guard status == 0 else {
            throw OpenSimError(
                code: .daemonUnavailable,
                message: "launchctl kickstart failed",
                details: ["status": "\(status)"]
            )
        }
    }

    public func isLoaded() -> Bool {
        (try? runLaunchctl(["print", "gui/\(getuid())/dev.opensim.daemon"])) == 0
    }

    private func runLaunchctl(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        _ = out.fileHandleForReading.readDataToEndOfFile()
        _ = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
```

Create `Sources/OpenSimDaemon/Client/DaemonClient.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

public struct DaemonClient: Sendable {
    public let baseURL: URL
    public let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)
    }

    public init(state: DaemonState) {
        self.init(
            baseURL: URL(string: "http://127.0.0.1:\(state.port)")!,
            token: state.token
        )
    }

    public func health() async throws -> HealthResponse {
        try await request(method: "GET", path: "/v1/health", body: Optional<EmptyPayload>.none, as: HealthResponse.self)
    }

    public func devices() async throws -> [Device] {
        try await request(method: "GET", path: "/v1/devices", body: Optional<EmptyPayload>.none, as: [Device].self)
    }

    public func operation(_ request: OperationRequest) async throws -> OperationResult {
        try await self.request(method: "POST", path: "/v1/operations", body: request, as: OperationResult.self)
    }

    public func createSession(clientKind: String, clientName: String) async throws -> Session {
        try await request(
            method: "POST",
            path: "/v1/sessions",
            body: CreateSessionRequest(clientKind: clientKind, clientName: clientName),
            as: Session.self
        )
    }

    public func closeSession(_ id: SessionID) async throws {
        _ = try await rawRequest(method: "DELETE", path: "/v1/sessions/\(id.rawValue)", body: nil)
    }

    public func acquireLease(_ request: AcquireLeaseRequest) async throws -> Lease {
        try await self.request(method: "POST", path: "/v1/leases", body: request, as: Lease.self)
    }

    public func heartbeatLease(_ id: LeaseID, sessionID: SessionID, ttlSeconds: Int?) async throws -> Lease {
        try await request(
            method: "POST",
            path: "/v1/leases/\(id.rawValue)/heartbeat",
            body: HeartbeatRequest(sessionID: sessionID, ttlSeconds: ttlSeconds),
            as: Lease.self
        )
    }

    public func releaseLease(_ id: LeaseID, sessionID: SessionID) async throws -> LeaseReleaseResult {
        let path = "/v1/leases/\(id.rawValue)?sessionID=\(sessionID.rawValue)"
        return try await request(
            method: "DELETE",
            path: path,
            body: Optional<EmptyPayload>.none,
            as: LeaseReleaseResult.self
        )
    }

    public func events(lastEventID: String? = nil) -> AsyncThrowingStream<DaemonEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: try makeURL(path: "/v1/events"))
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    if let lastEventID {
                        urlRequest.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
                    }
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw OpenSimError.daemonUnavailable("SSE endpoint returned an error")
                    }
                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                let data = Data(dataLines.joined(separator: "\n").utf8)
                                dataLines.removeAll()
                                continuation.yield(try OpenSimJSON.decoder().decode(DaemonEvent.self, from: data))
                            }
                        } else if line.hasPrefix("data: ") {
                            dataLines.append(String(line.dropFirst(6)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func request<Body: Encodable, T: Decodable>(
        method: String,
        path: String,
        body: Body?,
        as type: T.Type
    ) async throws -> T {
        let data = try await rawRequest(
            method: method,
            path: path,
            body: body.map { try OpenSimJSON.encoder(pretty: false).encode($0) }
        )
        let envelope = try OpenSimJSON.decoder().decode(Envelope<T>.self, from: data)
        guard envelope.ok, let value = envelope.data else {
            throw envelope.error ?? OpenSimError.daemonUnavailable("Daemon returned an empty response")
        }
        return value
    }

    private func rawRequest(method: String, path: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenSimError.daemonUnavailable("Daemon returned a non-HTTP response")
            }
            if http.statusCode >= 400 {
                if let envelope = try? OpenSimJSON.decoder().decode(Envelope<EmptyPayload>.self, from: data),
                   let error = envelope.error {
                    throw error
                }
                throw OpenSimError.daemonUnavailable("Daemon returned HTTP \(http.statusCode)")
            }
            return data
        } catch let error as OpenSimError {
            throw error
        } catch {
            throw OpenSimError.daemonUnavailable(String(describing: error))
        }
    }

    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw OpenSimError.invalidArgument("Invalid daemon path: \(path)")
        }
        return url
    }
}
```

Create `Sources/OpenSimDaemon/Client/DaemonLauncher.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

public struct DaemonLauncher: Sendable {
    private let paths: OpenSimPaths
    private let stateStore: DaemonStateStore

    public init(paths: OpenSimPaths = OpenSimPaths()) {
        self.paths = paths
        self.stateStore = DaemonStateStore(paths: paths)
    }

    public func ensureRunning() async throws -> DaemonClient {
        try paths.ensureDirectories()
        if let state = try? stateStore.read(), let client = await healthyClient(state: state) {
            return client
        }
        if ProcessInfo.processInfo.environment["OPENSIM_DAEMON_AUTOSTART"] == "0" {
            throw OpenSimError.daemonUnavailable("Daemon is not running and autostart is disabled")
        }
        let manager = LaunchAgentManager(
            opensimPath: DaemonLauncher.executablePath(),
            paths: paths
        )
        try manager.install()
        try? manager.bootout()
        try manager.bootstrap()
        for _ in 0..<50 {
            if let state = try? stateStore.read(), let client = await healthyClient(state: state) {
                return client
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw OpenSimError.daemonUnavailable("Daemon did not become healthy within 5 seconds")
    }

    private func healthyClient(state: DaemonState) async -> DaemonClient? {
        let client = DaemonClient(state: state)
        guard (try? await client.health()) != nil else {
            return nil
        }
        return client
    }

    private static func executablePath() -> String {
        if let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path {
            return path
        }
        return CommandLine.arguments[0]
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter LaunchAgentTests
swift test --filter DaemonClientTests
```

Expected: PASS; `LaunchAgentTests` có `Executed 1 test, with 0 failures`; `DaemonClientTests` có `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimDaemon/LaunchAgent Sources/OpenSimDaemon/Client Tests/OpenSimDaemonTests/LaunchAgentTests.swift Tests/OpenSimDaemonTests/DaemonClientTests.swift
git commit -m "feat(daemon): add launch agent and http client"
```

### Task 12: CLI daemon backend, daemon commands, session commands

**Files:**
- Modify: `Package.swift` (thêm `OpenSimProtocol`, `OpenSimDaemon` vào dependency của `OpenSimCLI`)
- Modify: `Sources/OpenSimCLI/Commands/GlobalOptions.swift`
- Modify: `Sources/OpenSimCLI/Runtime/CLIRuntime.swift`
- Create: `Sources/OpenSimCLI/Runtime/DaemonCommandBackend.swift`
- Create: `Sources/OpenSimCLI/Commands/DaemonCommand.swift`
- Create: `Sources/OpenSimCLI/Commands/SessionCommand.swift`
- Modify: `Sources/OpenSimCLI/OpenSimCommand.swift`
- Modify: `Sources/OpenSimCLI/Commands/LogCommand.swift`
- Modify: `Sources/OpenSimCLI/Commands/DoctorCommand.swift`
- Modify: `Tests/OpenSimCLITests/CommandParsingTests.swift`

**Interfaces:**
- Consumes: `DaemonLauncher`, `DaemonClient`, `OperationCatalog.plan3()`, `AcquireLeaseRequest`, `SessionListResult`.
- Produces: `GlobalOptions.direct`, `.session`, `.directCopy()`; `DaemonCommandBackend`; `DaemonCommand`; `SessionCommand`; `CLIRuntime.makeBackend` async; root command có bảy nhóm.

- [ ] **Step 1: Viết test thất bại**

Modify `Tests/OpenSimCLITests/CommandParsingTests.swift`: thay test `testRootHasFiveGroups` bằng:

```swift
    func testRootHasSevenGroups() {
        let names = OpenSimCommand.configuration.subcommands.map { $0.configuration.commandName }
        XCTAssertEqual(
            Set(names),
            Set(["device", "runtime", "app", "log", "doctor", "daemon", "session"])
        )
    }

    func testParsesDirectAndSessionOptions() throws {
        let command = try OpenSimCommand.parseAsRoot([
            "device", "list", "--direct", "--session", "session-1",
        ])
        let list = try XCTUnwrap(command as? DeviceListCommand)
        XCTAssertTrue(list.globals.direct)
        XCTAssertEqual(list.globals.session, "session-1")
    }

    func testParsesDaemonStatus() throws {
        let command = try OpenSimCommand.parseAsRoot(["daemon", "status"])
        XCTAssertNotNil(command as? DaemonStatusCommand)
    }
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter CommandParsingTests
```

Expected: FAIL với `cannot find type 'DaemonStatusCommand' in scope` và root chỉ có năm nhóm.

- [ ] **Step 3: Viết CLI switch và commands**

Modify target `OpenSimCLI` trong `Package.swift` để thêm `OpenSimProtocol` và `OpenSimDaemon`:

```swift
        .executableTarget(
            name: "OpenSimCLI",
            dependencies: [
                "OpenSimCore",
                "OpenSimBridge",
                "OpenSimProtocol",
                "OpenSimDaemon",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
```

Modify `Sources/OpenSimCLI/Commands/GlobalOptions.swift`: thêm hai property và helper:

```swift
    @Flag(name: .customLong("direct"), help: "Bypass the daemon and use the bridge directly")
    public var direct: Bool = false

    @Option(name: .customLong("session"), help: "Reuse an existing session")
    public var session: String?

    public func directCopy() -> GlobalOptions {
        var copy = self
        copy.direct = true
        return copy
    }
```

Modify `Sources/OpenSimCLI/Runtime/CLIRuntime.swift`: thay `makeBackend` và dòng gọi trong `run`:

```swift
    public static func makeBackend(_ globals: GlobalOptions) async throws -> any CommandBackend {
        try globals.validate()
        if globals.direct {
            return try makeDirectBackend(globals)
        }
        let client = try await DaemonLauncher(paths: OpenSimPaths()).ensureRunning()
        return DaemonCommandBackend(
            client: client,
            catalog: OperationCatalog.plan3(),
            providedSession: globals.session.map(SessionID.init)
        )
    }

    public static func makeDirectBackend(_ globals: GlobalOptions) throws -> any CommandBackend {
        try globals.validate()
        let bridge = try SimctlBridge.live(timeout: .seconds(globals.timeout))
        let executor = BridgeOperationExecutor(
            bridge: bridge,
            crashReports: bridge,
            doctor: bridge
        )
        return DirectCommandBackend(executor: executor)
    }
```

Trong `CLIRuntime.run`, đổi:

```swift
            let backend = try makeBackend(globals)
```

thành:

```swift
            let backend = try await makeBackend(globals)
```

Create `Sources/OpenSimCLI/Runtime/DaemonCommandBackend.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimDaemon
import OpenSimProtocol

public struct DaemonCommandBackend: CommandBackend {
    private let client: DaemonClient
    private let catalog: OperationCatalog
    private let providedSession: SessionID?

    public init(client: DaemonClient, catalog: OperationCatalog, providedSession: SessionID?) {
        self.client = client
        self.catalog = catalog
        self.providedSession = providedSession
    }

    public func execute<T: Decodable & Sendable>(
        _ operation: String,
        parameters: [String: String],
        as type: T.Type
    ) async throws -> T {
        guard let metadata = catalog.operation(forMCP: operation) else {
            throw OpenSimError.invalidArgument("Unknown operation: \(operation)")
        }
        let needsSession = metadata.requiresControlLease || operation == "session_acquire" || operation == "session_release"
        let sessionID: SessionID?
        if needsSession {
            sessionID = try await sessionID()
        } else {
            sessionID = providedSession
        }
        var leaseID: LeaseID?
        if metadata.requiresControlLease {
            guard let sessionID else {
                throw OpenSimError.invalidArgument("A session is required for this operation")
            }
            let devices = try await client.devices()
            let device = try DeviceResolver.resolve(query: parameters["device"], in: devices)
            let lease = try await client.acquireLease(AcquireLeaseRequest(
                deviceID: device.id,
                sessionID: sessionID,
                mode: .control,
                ttlSeconds: 120
            ))
            leaseID = lease.id
        }
        do {
            let result = try await client.operation(OperationRequest(
                operation: operation,
                parameters: parameters,
                sessionID: sessionID,
                leaseID: leaseID
            ))
            if let leaseID {
                _ = try? await client.releaseLease(leaseID, sessionID: sessionID)
            }
            if providedSession == nil, let sessionID, operation != "session_acquire", operation != "session_release" {
                try? await client.closeSession(sessionID)
            }
            return try OpenSimJSON.decoder().decode(T.self, from: result.data)
        } catch {
            if let leaseID {
                _ = try? await client.releaseLease(leaseID, sessionID: sessionID)
            }
            if providedSession == nil, let sessionID, operation != "session_acquire", operation != "session_release" {
                try? await client.closeSession(sessionID)
            }
            throw error
        }
    }

    private func sessionID() async throws -> SessionID {
        if let providedSession {
            return providedSession
        }
        let session = try await client.createSession(clientKind: "cli", clientName: "opensim")
        return session.id
    }
}
```

Create `Sources/OpenSimCLI/Commands/DaemonCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimCore
import OpenSimDaemon
import OpenSimProtocol

public struct DaemonStatusInfo: Codable, Sendable {
    public var pid: Int32?
    public var port: Int?
    public var version: String?
    public var health: String
    public var capabilities: BridgeCapabilities?

    public init(pid: Int32?, port: Int?, version: String?, health: String, capabilities: BridgeCapabilities?) {
        self.pid = pid
        self.port = port
        self.version = version
        self.health = health
        self.capabilities = capabilities
    }
}

public struct DaemonCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Manage the OpenSim daemon",
        subcommands: [
            DaemonStartCommand.self,
            DaemonStopCommand.self,
            DaemonRestartCommand.self,
            DaemonStatusCommand.self,
            DaemonLogsCommand.self,
            DaemonRunCommand.self,
        ]
    )

    public init() {}
}

private func daemonAckTable(_ ack: OperationAck) -> Table {
    Table(headers: ["RESULT", "MESSAGE"], rows: [[ack.ok ? "ok" : "failed", ack.message ?? ""]])
}

private func daemonStatusTable(_ info: DaemonStatusInfo) -> Table {
    Table(
        headers: ["FIELD", "VALUE"],
        rows: [
            ["health", info.health],
            ["pid", info.pid.map(String.init) ?? ""],
            ["port", info.port.map(String.init) ?? ""],
            ["version", info.version ?? ""],
            ["render", info.capabilities?.render.rawValue ?? ""],
            ["screenshot", info.capabilities?.screenshot.rawValue ?? ""],
        ]
    )
}

private func runDaemonCommand<T: Codable & Sendable>(
    globals: GlobalOptions,
    table: @escaping @Sendable (T) -> Table,
    body: @Sendable () async throws -> T
) async throws {
    let renderer = OutputRenderer(json: globals.json)
    do {
        let value = try await body()
        try renderer.success(value, table: table(value), durationMs: 0)
    } catch let error as OpenSimError {
        renderer.failure(error, durationMs: 0)
        throw ExitCode(OpenSimExitCode.forError(error.code).rawValue)
    }
}

private func waitForDaemon(paths: OpenSimPaths, timeout: TimeInterval = 5) async throws -> DaemonState {
    let store = DaemonStateStore(paths: paths)
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let state = try? store.read(),
           (try? await DaemonClient(state: state).health()) != nil {
            return state
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    throw OpenSimError.daemonUnavailable("Daemon did not become healthy within 5 seconds")
}

public struct DaemonStartCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "start", abstract: "Start the daemon")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        try await runDaemonCommand(globals: globals, table: daemonAckTable) {
            let paths = OpenSimPaths()
            try paths.ensureDirectories()
            let store = DaemonStateStore(paths: paths)
            if let state = try? store.read(),
               (try? await DaemonClient(state: state).health()) != nil {
                return OperationAck(ok: true, message: "Daemon already running on port \(state.port)")
            }
            let manager = LaunchAgentManager(
                opensimPath: Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0],
                paths: paths
            )
            try manager.install()
            try? manager.bootout()
            try manager.bootstrap()
            let state = try await waitForDaemon(paths: paths)
            return OperationAck(ok: true, message: "Daemon started on port \(state.port)")
        }
    }
}

public struct DaemonStopCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "stop", abstract: "Stop the daemon")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        try await runDaemonCommand(globals: globals, table: daemonAckTable) {
            let paths = OpenSimPaths()
            try paths.ensureDirectories()
            let manager = LaunchAgentManager(
                opensimPath: Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0],
                paths: paths
            )
            try? manager.bootout()
            DaemonStateStore(paths: paths).remove()
            return OperationAck(ok: true, message: "Daemon stopped")
        }
    }
}

public struct DaemonRestartCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "restart", abstract: "Restart the daemon")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        try await runDaemonCommand(globals: globals, table: daemonAckTable) {
            let paths = OpenSimPaths()
            try paths.ensureDirectories()
            let manager = LaunchAgentManager(
                opensimPath: Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0],
                paths: paths
            )
            try manager.install()
            try manager.kickstart()
            _ = try await waitForDaemon(paths: paths)
            return OperationAck(ok: true, message: "Daemon restarted")
        }
    }
}

public struct DaemonStatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "status", abstract: "Show daemon status")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        try await runDaemonCommand(globals: globals, table: daemonStatusTable) {
            let paths = OpenSimPaths()
            let store = DaemonStateStore(paths: paths)
            guard let state = try? store.read() else {
                throw OpenSimError(
                    code: .daemonUnavailable,
                    message: "Daemon state file was not found",
                    recovery: "Run `opensim daemon start`"
                )
            }
            let health = try await DaemonClient(state: state).health()
            return DaemonStatusInfo(
                pid: state.pid,
                port: state.port,
                version: state.version,
                health: health.status,
                capabilities: health.capabilities
            )
        }
    }
}

public struct DaemonLogsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "logs", abstract: "Print daemon logs")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Number of lines")
    public var limit: Int = 200

    public init() {}

    public func run() async throws {
        let paths = OpenSimPaths()
        let lines = DaemonLogsCommand.tail(paths.daemonLogFile, limit: limit)
        if globals.json {
            let renderer = OutputRenderer(json: true)
            try renderer.success(lines, table: nil, durationMs: 0)
            return
        }
        for line in lines {
            print(line)
        }
    }

    private static func tail(_ url: URL, limit: Int) -> [String] {
        guard limit > 0, let data = try? Data(contentsOf: url) else {
            return []
        }
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(limit)
            .map(String.init)
    }
}

public struct DaemonRunCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the daemon in the foreground"
    )

    @Flag(name: .long, help: "Run in the foreground")
    public var foreground: Bool = false

    public init() {}

    public func run() async throws {
        try await DaemonRunner.run(configuration: DaemonRunConfiguration(paths: OpenSimPaths()))
    }
}
```

Create `Sources/OpenSimCLI/Commands/SessionCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimCore
import OpenSimProtocol

public struct SessionCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Manage daemon sessions and leases",
        subcommands: [
            SessionListCommand.self,
            SessionAcquireCommand.self,
            SessionReleaseCommand.self,
        ]
    )

    public init() {}
}

public struct SessionListCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "list", abstract: "List sessions and leases")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        _ = try await CLIRuntime.run(globals: globals, table: { result in
            let sessionRows = result.sessions.map {
                ["session", $0.id.rawValue, $0.clientKind, $0.clientName]
            }
            let leaseRows = result.leases.map {
                ["lease", $0.id.rawValue, $0.mode.rawValue, "\($0.deviceID.rawValue) \($0.ownerName)"]
            }
            return Table(headers: ["KIND", "ID", "TYPE", "DETAIL"], rows: sessionRows + leaseRows)
        }) { backend in
            try await backend.execute("session_list", parameters: [:], as: SessionListResult.self)
        }
    }
}

public struct SessionAcquireCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "acquire", abstract: "Acquire a lease")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Lease mode: control or observe")
    public var mode: String = "control"

    @Option(name: .long, help: "Lease TTL in seconds")
    public var ttl: Int = 300

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters([
            "mode": mode,
            "ttlSeconds": "\(ttl)",
        ])
        _ = try await CLIRuntime.run(globals: globals, table: { lease in
            Table(
                headers: ["LEASE_ID", "DEVICE", "MODE", "OWNER", "EXPIRES_AT"],
                rows: [[lease.id.rawValue, lease.deviceID.rawValue, lease.mode.rawValue, lease.ownerName, OpenSimDate.string(from: lease.expiresAt)]]
            )
        }) { backend in
            try await backend.execute("session_acquire", parameters: parameters, as: Lease.self)
        }
    }
}

public struct SessionReleaseCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "release", abstract: "Release a lease")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Lease identifier")
    public var leaseID: String

    public init() {}

    public func run() async throws {
        guard globals.session != nil else {
            throw OpenSimError.invalidArgument(
                "session release requires --session",
                recovery: "Pass the session that owns the lease"
            )
        }
        _ = try await CLIRuntime.run(globals: globals, table: { ack in
            Table(headers: ["RESULT", "MESSAGE"], rows: [[ack.ok ? "ok" : "failed", ack.message ?? ""]])
        }) { backend in
            try await backend.execute("session_release", parameters: ["leaseID": leaseID], as: OperationAck.self)
        }
    }
}
```

Modify `OpenSimCommand.swift` để thêm `DaemonCommand.self`, `SessionCommand.self` vào `subcommands`.

Modify `LogCommand.swift`: đổi

```swift
        let backend = try CLIRuntime.makeBackend(globals)
```

thành:

```swift
        let backend = try await CLIRuntime.makeBackend(globals)
```

Modify `DoctorCommand.swift`: đổi dòng gọi `CLIRuntime.run` thành dùng `globals.directCopy()`:

```swift
        _ = try await CLIRuntime.run(
            globals: globals.directCopy(),
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter CommandParsingTests
swift build
```

Expected: PASS; `Executed 10 tests, with 0 failures`; `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCLI Tests/OpenSimCLITests/CommandParsingTests.swift
git commit -m "feat(cli): switch to daemon backend and add daemon session commands"
```

### Task 13: MCP JSON-RPC, tool catalog adapter và handler

**Files:**
- Modify: `Package.swift` (thêm target `OpenSimMCP`, `OpenSimMCPTests`)
- Create: `Sources/OpenSimMCP/JSONRPC/JSONRPC.swift`
- Create: `Sources/OpenSimMCP/Tools/MCPToolDefinition.swift`
- Create: `Sources/OpenSimMCP/Tools/ToolCatalogAdapter.swift`
- Create: `Sources/OpenSimMCP/Tools/MCPToolSession.swift`
- Create: `Sources/OpenSimMCP/Server/MCPHandler.swift`
- Test: `Tests/OpenSimMCPTests/MCPHandlerTests.swift`
- Test: `Tests/OpenSimMCPTests/ToolCatalogAdapterTests.swift`

**Interfaces:**
- Consumes: `OperationCatalog.plan3()`, `Operation`, `DaemonClient`, `JSONValue`, `OpenSimError`.
- Produces: `JSONRPCID`, `JSONRPCRequest`, `JSONRPCResponse`, `JSONRPCError`, `JSONRPCErrorCode`; `MCPToolDefinition`; `ToolCatalogAdapter.tools(from:)`; `MCPToolCalling`; `MCPHandler.handle(_:)`; `MCPToolSession.call(tool:arguments:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimMCPTests/MCPHandlerTests.swift`:

```swift
import XCTest
@testable import OpenSimMCP
@testable import OpenSimProtocol
@testable import OpenSimCore

struct FakeToolCaller: MCPToolCalling {
    var result: JSONValue? = nil
    var error: OpenSimError? = nil

    func call(tool: Operation, arguments: JSONValue) async throws -> JSONValue {
        if let error {
            throw error
        }
        return result ?? .object([:])
    }
}

final class MCPHandlerTests: XCTestCase {
    private func handler(caller: FakeToolCaller) -> MCPHandler {
        MCPHandler(catalog: .plan3(), caller: caller, serverVersion: "0.1.0")
    }

    func testInitializeProtocolVersionAndCapabilities() async throws {
        let response = await handler(caller: FakeToolCaller()).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(1),
            method: "initialize",
            params: .object(["protocolVersion": .string("2025-06-18")])
        ))
        XCTAssertEqual(response?.id, .number(1))
        XCTAssertEqual(response?.result?["protocolVersion"], .string("2025-06-18"))
        XCTAssertEqual(response?.result?["capabilities"]?["tools"]?["listChanged"], .bool(false))
    }

    func testToolsListComesFromCatalog() async throws {
        let response = await handler(caller: FakeToolCaller()).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(2),
            method: "tools/list",
            params: nil
        ))
        let tools = try XCTUnwrap(response?.result?["tools"]?.arrayValue)
        XCTAssertEqual(tools.count, 25)
        let names = Set(tools.compactMap { $0["name"]?.stringValue })
        XCTAssertTrue(names.contains("device_boot"))
        XCTAssertTrue(names.contains("session_acquire"))
        XCTAssertFalse(names.contains("log_crash"))
    }

    func testUnknownToolReturnsInvalidParams() async throws {
        let response = await handler(caller: FakeToolCaller()).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(3),
            method: "tools/call",
            params: .object(["name": .string("missing_tool"), "arguments": .object([:])])
        ))
        XCTAssertEqual(response?.error?.code, -32602)
        XCTAssertNil(response?.result)
    }

    func testToolCallSuccessAndBusinessError() async throws {
        let success = await handler(caller: FakeToolCaller(result: .object(["ok": .bool(true)]))).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(4),
            method: "tools/call",
            params: .object(["name": .string("device_list"), "arguments": .object([:])])
        ))
        XCTAssertEqual(success?.result?["isError"], .bool(false))
        XCTAssertEqual(success?.result?["structuredContent"]?["ok"], .bool(true))

        let failure = await handler(caller: FakeToolCaller(error: .invalidArgument("bad"))).handle(JSONRPCRequest(
            jsonrpc: "2.0",
            id: .number(5),
            method: "tools/call",
            params: .object(["name": .string("device_list"), "arguments": .object([:])])
        ))
        XCTAssertEqual(failure?.result?["isError"], .bool(true))
        XCTAssertEqual(failure?.result?["structuredContent"]?["error"]?["code"], .string("invalid_argument"))
    }
}
```

Create `Tests/OpenSimMCPTests/ToolCatalogAdapterTests.swift`:

```swift
import XCTest
@testable import OpenSimMCP
@testable import OpenSimCore

final class ToolCatalogAdapterTests: XCTestCase {
    func testAdapterMatchesCatalogExactly() {
        let catalog = OperationCatalog.plan3()
        let tools = ToolCatalogAdapter.tools(from: catalog)
        XCTAssertEqual(Set(tools.map(\.name)), Set(catalog.mcpOperations().map(\.mcpName)))
    }

    func testDestructiveToolRequiresConfirm() throws {
        let tools = ToolCatalogAdapter.tools(from: .plan3())
        let erase = try XCTUnwrap(tools.first { $0.name == "device_erase" })
        let required = erase.inputSchema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        XCTAssertTrue(required.contains("confirm"))
        let confirm = try XCTUnwrap(erase.inputSchema["properties"]?["confirm"])
        XCTAssertEqual(confirm["type"]?.stringValue, "boolean")
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter MCPHandlerTests
swift test --filter ToolCatalogAdapterTests
```

Expected: FAIL với `cannot find type 'MCPHandler' in scope`.

- [ ] **Step 3: Viết MCP core**

Modify `Package.swift`: thêm product và target MCP:

```swift
        .library(name: "OpenSimMCP", targets: ["OpenSimMCP"]),
```

```swift
        .target(
            name: "OpenSimMCP",
            dependencies: [
                "OpenSimCore",
                "OpenSimProtocol",
                "OpenSimDaemon",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "OpenSimMCPTests",
            dependencies: ["OpenSimMCP", "OpenSimDaemon", "OpenSimProtocol", "OpenSimCore"]
        ),
```

Create `Sources/OpenSimMCP/JSONRPC/JSONRPC.swift`:

```swift
import Foundation
import OpenSimProtocol

public enum JSONRPCID: Codable, Sendable, Equatable {
    case number(Int)
    case string(String)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON-RPC id")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct JSONRPCRequest: Codable, Sendable, Equatable {
    public var jsonrpc: String
    public var id: JSONRPCID?
    public var method: String
    public var params: JSONValue?

    public init(jsonrpc: String = "2.0", id: JSONRPCID?, method: String, params: JSONValue?) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCError: Codable, Sendable, Equatable {
    public var code: Int
    public var message: String
    public var data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct JSONRPCResponse: Codable, Sendable, Equatable {
    public var jsonrpc: String
    public var id: JSONRPCID?
    public var result: JSONValue?
    public var error: JSONRPCError?

    public init(jsonrpc: String = "2.0", id: JSONRPCID?, result: JSONValue?, error: JSONRPCError?) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }
}

public enum JSONRPCErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}
```

Create `Sources/OpenSimMCP/Tools/MCPToolDefinition.swift`:

```swift
import Foundation
import OpenSimProtocol

public struct MCPToolDefinition: Codable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}
```

Create `Sources/OpenSimMCP/Tools/ToolCatalogAdapter.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

public enum ToolCatalogAdapter {
    public static func tools(from catalog: OperationCatalog) -> [MCPToolDefinition] {
        catalog.mcpOperations().map { operation in
            var properties: [String: JSONValue] = [:]
            var required: [JSONValue] = []
            for parameter in operation.parameters {
                var schema: [String: JSONValue] = ["type": .string(parameter.type)]
                if let defaultValue = parameter.defaultValue {
                    schema["default"] = typedDefault(defaultValue, type: parameter.type)
                }
                properties[parameter.name] = .object(schema)
                if parameter.required {
                    required.append(.string(parameter.name))
                }
            }
            let inputSchema = JSONValue.object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required),
                "additionalProperties": .bool(false),
            ])
            return MCPToolDefinition(
                name: operation.mcpName,
                description: operation.summary,
                inputSchema: inputSchema
            )
        }
    }

    private static func typedDefault(_ value: String, type: String) -> JSONValue {
        switch type {
        case "boolean":
            return .bool(value.lowercased() == "true")
        case "integer":
            return .number(Double(Int(value) ?? 0))
        case "number":
            return .number(Double(value) ?? 0)
        default:
            return .string(value)
        }
    }
}
```

Create `Sources/OpenSimMCP/Tools/MCPToolSession.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimDaemon
import OpenSimProtocol

public actor MCPToolSession: MCPToolCalling {
    private let client: DaemonClient
    private let catalog: OperationCatalog
    private let clientName: String
    private var sessionID: SessionID?
    private var leases: [DeviceID: Lease] = [:]
    private var heartbeatTask: Task<Void, Never>?

    public init(client: DaemonClient, catalog: OperationCatalog, clientName: String = "opensim-mcp") {
        self.client = client
        self.catalog = catalog
        self.clientName = clientName
    }

    public func call(tool: Operation, arguments: JSONValue) async throws -> JSONValue {
        let parameters = try Self.parameters(from: arguments)
        let session = try await ensureSession()
        var leaseID: LeaseID?
        if tool.requiresControlLease {
            let devices = try await client.devices()
            let device = try DeviceResolver.resolve(query: parameters["device"], in: devices)
            let lease = try await ensureLease(device: device.id, session: session)
            leaseID = lease.id
        }
        let result = try await client.operation(OperationRequest(
            operation: tool.mcpName,
            parameters: parameters,
            sessionID: session,
            leaseID: leaseID
        ))
        return try JSONDecoder().decode(JSONValue.self, from: result.data)
    }

    public func close() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        for lease in leases.values {
            _ = try? await client.releaseLease(lease.id, sessionID: lease.sessionID)
        }
        leases.removeAll()
        if let sessionID {
            try? await client.closeSession(sessionID)
        }
        sessionID = nil
    }

    private func ensureSession() async throws -> SessionID {
        if let sessionID {
            return sessionID
        }
        let session = try await client.createSession(clientKind: "mcp", clientName: clientName)
        sessionID = session.id
        return session.id
    }

    private func ensureLease(device: DeviceID, session: SessionID) async throws -> Lease {
        if let lease = leases[device], lease.expiresAt > Date().addingTimeInterval(60) {
            return lease
        }
        let lease = try await client.acquireLease(AcquireLeaseRequest(
            deviceID: device,
            sessionID: session,
            mode: .control,
            ttlSeconds: 300
        ))
        leases[device] = lease
        startHeartbeatIfNeeded()
        return lease
    }

    private func startHeartbeatIfNeeded() {
        guard heartbeatTask == nil else {
            return
        }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.heartbeatLeases()
            }
        }
    }

    private func heartbeatLeases() async {
        for (device, lease) in Array(leases) {
            do {
                let renewed = try await client.heartbeatLease(
                    lease.id,
                    sessionID: lease.sessionID,
                    ttlSeconds: 300
                )
                leases[device] = renewed
            } catch {
                leases.removeValue(forKey: device)
            }
        }
    }

    private static func parameters(from arguments: JSONValue) throws -> [String: String] {
        guard let object = arguments.objectValue else {
            throw OpenSimError.invalidArgument("Tool arguments must be a JSON object")
        }
        var result: [String: String] = [:]
        for (key, value) in object {
            switch value {
            case .null:
                continue
            case .string(let text):
                result[key] = text
            case .bool(let flag):
                result[key] = flag ? "true" : "false"
            case .number(let number):
                if number.rounded() == number {
                    result[key] = String(Int(number))
                } else {
                    result[key] = String(number)
                }
            case .array, .object:
                let data = try JSONEncoder().encode(value)
                result[key] = String(decoding: data, as: UTF8.self)
            }
        }
        return result
    }
}
```

Create `Sources/OpenSimMCP/Server/MCPHandler.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

public protocol MCPToolCalling: Sendable {
    func call(tool: Operation, arguments: JSONValue) async throws -> JSONValue
}

public struct MCPHandler: Sendable {
    public static let protocolVersion = "2025-06-18"
    private let catalog: OperationCatalog
    private let caller: any MCPToolCalling
    private let serverVersion: String

    public init(catalog: OperationCatalog, caller: any MCPToolCalling, serverVersion: String) {
        self.catalog = catalog
        self.caller = caller
        self.serverVersion = serverVersion
    }

    public func handle(_ request: JSONRPCRequest) async -> JSONRPCResponse? {
        let identifier = request.id
        guard request.jsonrpc == "2.0" else {
            return response(id: identifier, error: JSONRPCError(
                code: JSONRPCErrorCode.invalidRequest,
                message: "jsonrpc must be 2.0"
            ))
        }
        switch request.method {
        case "initialize":
            let result = JSONValue.object([
                "protocolVersion": .string(MCPHandler.protocolVersion),
                "capabilities": .object([
                    "tools": .object(["listChanged": .bool(false)]),
                ]),
                "serverInfo": .object([
                    "name": .string("opensim"),
                    "version": .string(serverVersion),
                ]),
            ])
            return response(id: identifier, result: result)

        case "notifications/initialized":
            return nil

        case "ping":
            return response(id: identifier, result: .object([:]))

        case "tools/list":
            let tools = ToolCatalogAdapter.tools(from: catalog)
            let encoded = tools.map { tool in
                JSONValue.object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "inputSchema": tool.inputSchema,
                ])
            }
            return response(id: identifier, result: .object(["tools": .array(encoded)]))

        case "tools/call":
            return await handleToolCall(request: request, identifier: identifier)

        default:
            return response(id: identifier, error: JSONRPCError(
                code: JSONRPCErrorCode.methodNotFound,
                message: "Method not found: \(request.method)"
            ))
        }
    }

    private func handleToolCall(request: JSONRPCRequest, identifier: JSONRPCID?) async -> JSONRPCResponse? {
        guard let params = request.params?.objectValue,
              let name = params["name"]?.stringValue else {
            return response(id: identifier, error: JSONRPCError(
                code: JSONRPCErrorCode.invalidParams,
                message: "tools/call requires name"
            ))
        }
        guard let tool = catalog.operation(forMCP: name), tool.mcpExposed else {
            return response(id: identifier, error: JSONRPCError(
                code: JSONRPCErrorCode.invalidParams,
                message: "Unknown tool: \(name)"
            ))
        }
        let arguments = params["arguments"] ?? .object([:])
        do {
            let value = try await caller.call(tool: tool, arguments: arguments)
            return response(id: identifier, result: toolResult(value: value, error: nil))
        } catch let error as OpenSimError {
            return response(id: identifier, result: toolResult(value: nil, error: error))
        } catch {
            let mapped = OpenSimError(code: .internalError, message: String(describing: error))
            return response(id: identifier, result: toolResult(value: nil, error: mapped))
        }
    }

    private func toolResult(value: JSONValue?, error: OpenSimError?) -> JSONValue {
        if let error {
            let structured = (try? JSONValue.from(error)) ?? .object([:])
            return .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("\(error.code): \(error.message)"),
                    ]),
                ]),
                "structuredContent": .object(["error": structured]),
                "isError": .bool(true),
            ])
        }
        let contentText = "ok"
        return .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(contentText),
                ]),
            ]),
            "structuredContent": value ?? .null,
            "isError": .bool(false),
        ])
    }

    private func response(id: JSONRPCID?, result: JSONValue) -> JSONRPCResponse? {
        guard id != nil else {
            return nil
        }
        return JSONRPCResponse(id: id, result: result, error: nil)
    }

    private func response(id: JSONRPCID?, error: JSONRPCError) -> JSONRPCResponse? {
        return JSONRPCResponse(id: id ?? .null, result: nil, error: error)
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter MCPHandlerTests
swift test --filter ToolCatalogAdapterTests
```

Expected: PASS; `MCPHandlerTests` có `Executed 4 tests, with 0 failures`; `ToolCatalogAdapterTests` có `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimMCP Tests/OpenSimMCPTests
git commit -m "feat(mcp): add jsonrpc handler and dynamic tool catalog"
```

### Task 14: MCP stdio transport và `opensim mcp`

**Files:**
- Modify: `Package.swift` (thêm `OpenSimMCP` vào dependency của `OpenSimCLI`)
- Create: `Sources/OpenSimMCP/Stdio/StdioTransport.swift`
- Create: `Sources/OpenSimCLI/Commands/MCPCommand.swift`
- Modify: `Sources/OpenSimCLI/OpenSimCommand.swift`
- Test: `Tests/OpenSimMCPTests/StdioTransportTests.swift`
- Modify: `Tests/OpenSimCLITests/CommandParsingTests.swift`

**Interfaces:**
- Consumes: `MCPHandler`, `MCPToolSession`, `DaemonLauncher`, `OpenSimPaths`.
- Produces: `StdioTransport(handler:).run()`, `.handleLine(_:)`; `MCPCommand --stdio/--http`; root command tám nhóm.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimMCPTests/StdioTransportTests.swift`:

```swift
import XCTest
@testable import OpenSimMCP
@testable import OpenSimProtocol
@testable import OpenSimCore

final class StdioTransportTests: XCTestCase {
    func testInitializeLineProducesResponse() async throws {
        let handler = MCPHandler(catalog: .plan3(), caller: FakeToolCaller(), serverVersion: "0.1.0")
        let transport = StdioTransport(handler: handler)
        let line = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#
        let lineOutput = await transport.handleLine(line)
        let output = try XCTUnwrap(lineOutput)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(output.utf8))
        XCTAssertEqual(response.id, .number(1))
        XCTAssertEqual(response.result?["protocolVersion"], .string("2025-06-18"))
    }

    func testMalformedLineProducesParseError() async throws {
        let handler = MCPHandler(catalog: .plan3(), caller: FakeToolCaller(), serverVersion: "0.1.0")
        let transport = StdioTransport(handler: handler)
        let lineOutput = await transport.handleLine("not json")
        let output = try XCTUnwrap(lineOutput)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(output.utf8))
        XCTAssertEqual(response.error?.code, -32700)
        XCTAssertEqual(response.id, .null)
    }

    func testNotificationProducesNoResponse() async {
        let handler = MCPHandler(catalog: .plan3(), caller: FakeToolCaller(), serverVersion: "0.1.0")
        let transport = StdioTransport(handler: handler)
        let line = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        let output = await transport.handleLine(line)
        XCTAssertNil(output)
    }
}
```

Trong `Tests/OpenSimCLITests/CommandParsingTests.swift`, thay test `testRootHasSevenGroups` bằng code dưới đây và thêm test `testParsesMCPStdio` trước dấu `}` cuối file:

```swift
    func testParsesMCPStdio() throws {
        let command = try OpenSimCommand.parseAsRoot(["mcp", "--stdio"])
        let mcp = try XCTUnwrap(command as? MCPCommand)
        XCTAssertTrue(mcp.stdio)
        XCTAssertFalse(mcp.http)
    }

    func testRootHasEightGroups() {
        let names = OpenSimCommand.configuration.subcommands.map { $0.configuration.commandName }
        XCTAssertEqual(
            Set(names),
            Set(["device", "runtime", "app", "log", "doctor", "daemon", "session", "mcp"])
        )
    }
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter StdioTransportTests
swift test --filter CommandParsingTests
```

Expected: FAIL với `cannot find type 'StdioTransport' in scope`.

- [ ] **Step 3: Viết stdio và CLI command**

Modify target `OpenSimCLI` trong `Package.swift` để thêm `OpenSimMCP`:

```swift
        .executableTarget(
            name: "OpenSimCLI",
            dependencies: [
                "OpenSimCore",
                "OpenSimBridge",
                "OpenSimProtocol",
                "OpenSimDaemon",
                "OpenSimMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
```

Create `Sources/OpenSimMCP/Stdio/StdioTransport.swift`:

```swift
import Foundation
import OpenSimProtocol

public struct StdioTransport: Sendable {
    private let handler: MCPHandler

    public init(handler: MCPHandler) {
        self.handler = handler
    }

    public func run() async {
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                if let output = await handleLine(line) {
                    FileHandle.standardOutput.write(Data((output + "\n").utf8))
                }
            }
        } catch {
            FileHandle.standardError.write(Data("stdio read failed: \(error)\n".utf8))
        }
    }

    public func handleLine(_ line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let data = trimmed.data(using: .utf8) else {
            return parseErrorResponse()
        }
        let request: JSONRPCRequest
        do {
            request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        } catch {
            return parseErrorResponse()
        }
        guard let response = await handler.handle(request) else {
            return nil
        }
        guard let encoded = try? OpenSimJSON.encoder(pretty: false).encode(response) else {
            return nil
        }
        return String(decoding: encoded, as: UTF8.self)
    }

    private func parseErrorResponse() -> String {
        let response = JSONRPCResponse(
            id: .null,
            result: nil,
            error: JSONRPCError(code: JSONRPCErrorCode.parseError, message: "Parse error")
        )
        let data = (try? OpenSimJSON.encoder(pretty: false).encode(response)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
```

Create `Sources/OpenSimCLI/Commands/MCPCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimCore
import OpenSimDaemon
import OpenSimMCP
import OpenSimProtocol

public struct MCPCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Run the MCP server"
    )

    @Flag(name: .long, help: "Serve JSON-RPC over stdin/stdout")
    public var stdio: Bool = false

    @Flag(name: .long, help: "Use the daemon HTTP MCP endpoint")
    public var http: Bool = false

    public init() {}

    public func run() async throws {
        guard stdio != http else {
            throw OpenSimError.invalidArgument("Choose exactly one of --stdio or --http")
        }
        let paths = OpenSimPaths()
        let client = try await DaemonLauncher(paths: paths).ensureRunning()
        let catalog = OperationCatalog.plan3()
        if stdio {
            let session = MCPToolSession(client: client, catalog: catalog)
            let handler = MCPHandler(
                catalog: catalog,
                caller: session,
                serverVersion: OpenSimVersion.version
            )
            await StdioTransport(handler: handler).run()
            await session.close()
            return
        }
        let state = try DaemonStateStore(paths: paths).read()
        FileHandle.standardError.write(
            Data("MCP HTTP endpoint: http://127.0.0.1:\(state.port)/mcp\n".utf8)
        )
        while !Task.isCancelled {
            try await Task.sleep(for: .seconds(60))
        }
    }
}
```

Modify `Sources/OpenSimCLI/OpenSimCommand.swift` để thêm `MCPCommand.self` vào `subcommands`.

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter StdioTransportTests
swift test --filter CommandParsingTests
swift build
```

Expected: PASS; `StdioTransportTests` có `Executed 3 tests, with 0 failures`; `CommandParsingTests` có `Executed 11 tests, with 0 failures`; `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimMCP/Stdio Sources/OpenSimCLI/Commands/MCPCommand.swift Sources/OpenSimCLI/OpenSimCommand.swift Tests/OpenSimMCPTests/StdioTransportTests.swift Tests/OpenSimCLITests/CommandParsingTests.swift
git commit -m "feat(mcp): add stdio transport and opensim mcp command"
```

### Task 15: MCP HTTP endpoint, session header và SSE

**Files:**
- Modify: `Package.swift` (thêm `OpenSimMCP` vào test target `OpenSimDaemonTests`)
- Modify: `Sources/OpenSimCLI/Commands/DaemonCommand.swift` (mount MCP route provider)
- Create: `Sources/OpenSimMCP/Server/MCPHTTPSessionStore.swift`
- Create: `Sources/OpenSimMCP/HTTP/MCPRouteProvider.swift`
- Test: `Tests/OpenSimDaemonTests/MCPHTTPTests.swift`

**Interfaces:**
- Consumes: `DaemonRouteProvider`, `DaemonRouteContext`, `DaemonClient`, `MCPHandler`, `MCPToolSession`, `EventHub`.
- Produces: `MCPHTTPSessionStore.create(clientName:)`, `.handler(for:)`, `.close(id:)`; `MCPRouteProvider(catalog:)` mount `POST/GET/DELETE /mcp`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/MCPHTTPTests.swift`:

```swift
import XCTest
@testable import OpenSimMCP
@testable import OpenSimDaemon
@testable import OpenSimProtocol
@testable import OpenSimCore
@testable import OpenSimBridge

final class MCPHTTPTests: XCTestCase {
    func testInitializeReturnsSessionIDAndToolsListUsesIt() async throws {
        let executor = DaemonStubSimctlExecutor()
        let harness = try await RouteTestHarness.start(
            executor: executor,
            routeProviders: [MCPRouteProvider(catalog: .plan3())]
        )
        defer { harness.server.stop() }
        let base = URL(string: "http://127.0.0.1:\(harness.server.port)/mcp")!

        var initialize = URLRequest(url: base)
        initialize.httpMethod = "POST"
        initialize.setValue("Bearer \(harness.token)", forHTTPHeaderField: "Authorization")
        initialize.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initialize.httpBody = try JSONEncoder().encode(JSONRPCRequest(
            id: .number(1),
            method: "initialize",
            params: .object(["protocolVersion": .string("2025-06-18")])
        ))
        let (initializeData, initializeResponse) = try await URLSession.shared.data(for: initialize)
        XCTAssertEqual((initializeResponse as? HTTPURLResponse)?.statusCode, 200)
        let sessionID = try XCTUnwrap((initializeResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Mcp-Session-Id"))
        let initialized = try JSONDecoder().decode(JSONRPCResponse.self, from: initializeData)
        XCTAssertEqual(initialized.result?["protocolVersion"], .string("2025-06-18"))

        var list = URLRequest(url: base)
        list.httpMethod = "POST"
        list.setValue("Bearer \(harness.token)", forHTTPHeaderField: "Authorization")
        list.setValue("application/json", forHTTPHeaderField: "Content-Type")
        list.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        list.httpBody = try JSONEncoder().encode(JSONRPCRequest(
            id: .number(2),
            method: "tools/list",
            params: nil
        ))
        let (listData, listResponse) = try await URLSession.shared.data(for: list)
        XCTAssertEqual((listResponse as? HTTPURLResponse)?.statusCode, 200)
        let listed = try JSONDecoder().decode(JSONRPCResponse.self, from: listData)
        XCTAssertEqual(listed.result?["tools"]?.arrayValue?.count, 25)
    }

    func testRequestWithoutSessionHeaderIsRejected() async throws {
        let executor = DaemonStubSimctlExecutor()
        let harness = try await RouteTestHarness.start(
            executor: executor,
            routeProviders: [MCPRouteProvider(catalog: .plan3())]
        )
        defer { harness.server.stop() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(harness.server.port)/mcp")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(harness.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSONRPCRequest(
            id: .number(3),
            method: "tools/list",
            params: nil
        ))
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 400)
        let error = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        XCTAssertEqual(error.error?.code, -32600)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter MCPHTTPTests
```

Expected: FAIL với `cannot find 'MCPRouteProvider' in scope`.

- [ ] **Step 3: Viết MCP HTTP**

Modify target `OpenSimDaemonTests` trong `Package.swift` để thêm `OpenSimMCP`:

```swift
        .testTarget(
            name: "OpenSimDaemonTests",
            dependencies: [
                "OpenSimDaemon",
                "OpenSimBridge",
                "OpenSimProtocol",
                "OpenSimCore",
                "OpenSimMCP",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
```

Thêm `import OpenSimMCP` vào đầu `Sources/OpenSimCLI/Commands/DaemonCommand.swift`, sau đó sửa `DaemonRunCommand.run()` để mount MCP HTTP:

```swift
    public func run() async throws {
        let catalog = OperationCatalog.plan3()
        try await DaemonRunner.run(configuration: DaemonRunConfiguration(
            paths: OpenSimPaths(),
            routeProviders: [MCPRouteProvider(catalog: catalog)]
        ))
    }
```

Create `Sources/OpenSimMCP/Server/MCPHTTPSessionStore.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimDaemon
import OpenSimProtocol

public actor MCPHTTPSessionStore {
    private struct StoredSession: Sendable {
        var handler: MCPHandler
        var tool: MCPToolSession
    }

    private let catalog: OperationCatalog
    private let baseURL: URL
    private let token: String
    private var sessions: [String: StoredSession] = [:]

    public init(catalog: OperationCatalog, baseURL: URL, token: String) {
        self.catalog = catalog
        self.baseURL = baseURL
        self.token = token
    }

    public func create(clientName: String) async throws -> (String, MCPHandler) {
        let client = DaemonClient(baseURL: baseURL, token: token)
        let tool = MCPToolSession(client: client, catalog: catalog, clientName: clientName)
        let handler = MCPHandler(
            catalog: catalog,
            caller: tool,
            serverVersion: OpenSimVersion.version
        )
        let id = UUID().uuidString
        sessions[id] = StoredSession(handler: handler, tool: tool)
        return (id, handler)
    }

    public func handler(for id: String) -> MCPHandler? {
        sessions[id]?.handler
    }

    public func close(id: String) async {
        guard let stored = sessions.removeValue(forKey: id) else {
            return
        }
        await stored.tool.close()
    }
}
```

Create `Sources/OpenSimMCP/HTTP/MCPRouteProvider.swift`:

```swift
import Foundation
import Hummingbird
import NIOCore
import OpenSimCore
import OpenSimDaemon
import OpenSimProtocol

public struct MCPRouteProvider: DaemonRouteProvider {
    private let catalog: OperationCatalog

    public init(catalog: OperationCatalog) {
        self.catalog = catalog
    }

    public func registerRoutes(
        on router: Router<BasicRequestContext>,
        context: DaemonRouteContext
    ) throws {
        let store = MCPHTTPSessionStore(
            catalog: catalog,
            baseURL: context.baseURL,
            token: context.token
        )

        router.post("/mcp") { request, _ in
            let rpc: JSONRPCRequest
            do {
                rpc = try await DaemonHTTP.decode(request, as: JSONRPCRequest.self)
            } catch {
                return mcpErrorResponse(
                    status: .badRequest,
                    code: JSONRPCErrorCode.parseError,
                    message: "Parse error"
                )
            }
            if rpc.method == "initialize" {
                let clientName = rpc.params?["clientInfo"]?["name"]?.stringValue ?? "mcp-client"
                let (sessionID, handler) = try await store.create(clientName: clientName)
                guard let response = await handler.handle(rpc) else {
                    return Response(status: .accepted)
                }
                return try mcpJSONResponse(response, sessionID: sessionID)
            }
            guard let sessionID = request.headers["mcp-session-id"],
                  let handler = await store.handler(for: sessionID) else {
                return mcpErrorResponse(
                    status: .badRequest,
                    code: JSONRPCErrorCode.invalidRequest,
                    message: "Mcp-Session-Id is required"
                )
            }
            guard let response = await handler.handle(rpc) else {
                return Response(status: .accepted)
            }
            return try mcpJSONResponse(response, sessionID: sessionID)
        }

        router.get("/mcp") { request, _ -> Response in
            guard let sessionID = request.headers["mcp-session-id"] else {
                return mcpErrorResponse(
                    status: .badRequest,
                    code: JSONRPCErrorCode.invalidRequest,
                    message: "Mcp-Session-Id is required"
                )
            }
            guard await store.handler(for: sessionID) != nil else {
                return mcpErrorResponse(
                    status: .badRequest,
                    code: JSONRPCErrorCode.invalidRequest,
                    message: "Unknown Mcp-Session-Id"
                )
            }
            let (initial, stream) = await context.services.events.subscribe(
                after: request.headers["last-event-id"]
            )
            return mcpSSEResponse(initial: initial, stream: stream)
        }

        router.delete("/mcp") { request, _ in
            guard let sessionID = request.headers["mcp-session-id"] else {
                return mcpErrorResponse(
                    status: .badRequest,
                    code: JSONRPCErrorCode.invalidRequest,
                    message: "Mcp-Session-Id is required"
                )
            }
            await store.close(id: sessionID)
            return Response(status: .ok)
        }
    }

    private func mcpJSONResponse(
        _ response: JSONRPCResponse,
        sessionID: String?
    ) throws -> Response {
        let data = try OpenSimJSON.encoder(pretty: false).encode(response)
        var httpResponse = Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: [UInt8](data)))
        )
        if let sessionID {
            httpResponse.headers["Mcp-Session-Id"] = sessionID
        }
        return httpResponse
    }

    private func mcpErrorResponse(
        status: HTTPResponseStatus,
        code: Int,
        message: String
    ) -> Response {
        let response = JSONRPCResponse(
            id: .null,
            result: nil,
            error: JSONRPCError(code: code, message: message)
        )
        let data = (try? OpenSimJSON.encoder(pretty: false).encode(response)) ?? Data()
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: [UInt8](data)))
        )
    }

    private func mcpSSEResponse(
        initial: [DaemonEvent],
        stream: AsyncStream<DaemonEvent>
    ) -> Response {
        let body = AsyncThrowingStream<ByteBuffer, Error> { continuation in
            let task = Task {
                do {
                    for event in initial {
                        continuation.yield(ByteBuffer(string: try notificationFrame(event)))
                    }
                    for await event in stream {
                        continuation.yield(ByteBuffer(string: try notificationFrame(event)))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        return Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache",
            ],
            body: .init(asyncSequence: body)
        )
    }

    private func notificationFrame(_ event: DaemonEvent) throws -> String {
        let payload = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "method": .string("notifications/message"),
            "params": .object([
                "level": .string("info"),
                "data": try JSONValue.from(event),
            ]),
        ])
        let data = try OpenSimJSON.encoder(pretty: false).encode(payload)
        return "id: \(event.id)\ndata: \(String(decoding: data, as: UTF8.self))\n\n"
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter MCPHTTPTests
```

Expected: PASS; `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimMCP/Server/MCPHTTPSessionStore.swift Sources/OpenSimMCP/HTTP/MCPRouteProvider.swift Tests/OpenSimMCPTests/MCPHTTPTests.swift
git commit -m "feat(mcp): add http endpoint with session and sse"
```

### Task 16: CLI/MCP parity, daemon restart và MCP end-to-end

**Files:**
- Modify: `Package.swift` (thêm `OpenSimProtocol`, `OpenSimDaemon` vào `IntegrationTests`)
- Create: `Tests/OpenSimCLITests/CatalogCLIParityTests.swift`
- Create: `Tests/IntegrationTests/Plan3DaemonIntegrationTests.swift`
- Create: `Tests/IntegrationTests/README-Plan3.md`

**Interfaces:**
- Consumes: `OpenSimCommand` tree, `OperationCatalog.plan3()`, `.build/debug/opensim`, `DaemonStateStore`, `DaemonClient`.
- Produces: parity test CLI/catalog; integration test daemon restart, CLI daemon switch, MCP stdio initialize/tools/list.

- [ ] **Step 1: Viết test thất bại**

Modify `Package.swift` để thêm protocol/daemon vào integration tests:

```swift
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["OpenSimCore", "OpenSimBridge", "OpenSimProtocol", "OpenSimDaemon"]
        ),
```

Create `Tests/OpenSimCLITests/CatalogCLIParityTests.swift`:

```swift
import ArgumentParser
import XCTest
@testable import OpenSimCLI
@testable import OpenSimCore

final class CatalogCLIParityTests: XCTestCase {
    func testEveryCatalogOperationHasCLICommand() {
        let paths = collect(OpenSimCommand.self, prefix: [])
        for operation in OperationCatalog.plan3().mcpOperations() {
            XCTAssertTrue(
                paths.contains(operation.cliPath.joined(separator: "/")),
                "Missing CLI command for \(operation.mcpName): \(operation.cliPath)"
            )
        }
    }

    func testEveryCLIGroupHasCatalogOperations() {
        let paths = collect(OpenSimCommand.self, prefix: [])
        let catalogPaths = Set(OperationCatalog.plan3().operations.values.map { $0.cliPath.joined(separator: "/") })
        for path in paths where !catalogPaths.contains(path) {
            XCTAssertTrue(
                path.hasPrefix("daemon/") || path.hasPrefix("mcp/") || path == "mcp" || path == "log/stream",
                "CLI command without catalog entry: \(path)"
            )
        }
    }

    private func collect(_ command: any ParsableCommand.Type, prefix: [String]) -> Set<String> {
        let configuration = command.configuration
        let path = prefix + [configuration.commandName]
        if configuration.subcommands.isEmpty {
            return [path.joined(separator: "/")]
        }
        return configuration.subcommands.reduce(into: Set<String>()) { result, subcommand in
            result.formUnion(collect(subcommand, prefix: path))
        }
    }
}
```

Create `Tests/IntegrationTests/Plan3DaemonIntegrationTests.swift`:

```swift
import XCTest
@testable import OpenSimCore
@testable import OpenSimDaemon
@testable import OpenSimProtocol

final class Plan3DaemonIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] == "1",
            "Set OPENSIM_INTEGRATION=1 to run daemon integration tests"
        )
    }

    private var binaryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/opensim")
    }

    private func makeHome() throws -> URL {
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-daemon-it-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func startDaemon(home: URL) throws -> Process {
        XCTAssertTrue(FileManager.default.fileExists(atPath: binaryURL.path))
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["daemon", "run", "--foreground"]
        var environment = ProcessInfo.processInfo.environment
        environment["OPENSIM_HOME"] = home.path
        environment["OPENSIM_DAEMON_AUTOSTART"] = "0"
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        return process
    }

    private func waitForState(home: URL, timeout: TimeInterval = 15) throws -> DaemonState {
        let store = DaemonStateStore(paths: OpenSimPaths(baseDirectory: home))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let state = try? store.read() {
                return state
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw XCTSkip("Daemon did not write a state file")
    }

    func testDaemonRestartChangesToken() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let first = try startDaemon(home: home)
        let firstState = try waitForState(home: home)
        first.terminate()
        first.waitUntilExit()
        let second = try startDaemon(home: home)
        let secondState = try waitForState(home: home)
        XCTAssertNotEqual(firstState.token, secondState.token)
        XCTAssertNotEqual(firstState.pid, secondState.pid)
        second.terminate()
        second.waitUntilExit()
    }

    func testCLIUsesDaemonThenDirectMode() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let daemon = try startDaemon(home: home)
        _ = try waitForState(home: home)
        defer {
            daemon.terminate()
            daemon.waitUntilExit()
        }
        let daemonJSON = try runCLI(home: home, arguments: ["device", "list", "--json"])
        XCTAssertTrue(daemonJSON.contains("\"schemaVersion\""))
        let directJSON = try runCLI(home: home, arguments: ["device", "list", "--json", "--direct"])
        XCTAssertTrue(directJSON.contains("\"schemaVersion\""))
    }

    func testMCPStdioInitializeAndToolsList() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let daemon = try startDaemon(home: home)
        _ = try waitForState(home: home)
        defer {
            daemon.terminate()
            daemon.waitUntilExit()
        }
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["mcp", "--stdio"]
        var environment = ProcessInfo.processInfo.environment
        environment["OPENSIM_HOME"] = home.path
        environment["OPENSIM_DAEMON_AUTOSTART"] = "0"
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }

        try writeLine(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#, to: input)
        let initialize = try XCTUnwrap(readLine(output.fileHandleForReading))
        XCTAssertTrue(initialize.contains("2025-06-18"))

        try writeLine(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":null}"#, to: input)
        let tools = try XCTUnwrap(readLine(output.fileHandleForReading))
        XCTAssertTrue(tools.contains("device_boot"))
        XCTAssertTrue(tools.contains("session_acquire"))
    }

    private func runCLI(home: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["OPENSIM_HOME"] = home.path
        environment["OPENSIM_DAEMON_AUTOSTART"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private func writeLine(_ line: String, to pipe: Pipe) throws {
        pipe.fileHandleForWriting.write(Data((line + "\n").utf8))
    }

    private func readLine(_ handle: FileHandle) -> String? {
        var data = Data()
        while true {
            guard let chunk = try? handle.read(upToCount: 1), let byte = chunk.first else {
                return nil
            }
            if byte == 0x0A {
                break
            }
            data.append(byte)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
```

Create `Tests/IntegrationTests/README-Plan3.md`:

```markdown
# Plan 3 integration tests

Run only with a built binary and a full Xcode installation:

```bash
swift build
OPENSIM_INTEGRATION=1 swift test --filter Plan3DaemonIntegrationTests
```

The tests use `OPENSIM_HOME` pointing at a temporary directory, spawn `opensim daemon run --foreground`, wait for `daemon.json`, and terminate the process. They do not install a LaunchAgent and do not modify the user's OpenSim state.

Expected final line:

```text
Executed 3 tests, with 0 failures
```
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter CatalogCLIParityTests
swift test --filter Plan3DaemonIntegrationTests
```

Expected: parity test FAIL nếu có catalog path thiếu CLI command; integration test skip-without-env với `Executed 3 tests, with 3 tests skipped`.

- [ ] **Step 3: Sửa parity và chạy integration**

Nếu parity fail, thêm command còn thiếu vào nhóm tương ứng hoặc sửa `cliPath` cho khớp; không thêm danh sách tool thứ hai. Sau đó chạy:

```bash
swift build
swift test --filter CatalogCLIParityTests
OPENSIM_INTEGRATION=1 swift test --filter Plan3DaemonIntegrationTests
```

Expected: `CatalogCLIParityTests` pass; integration `Executed 3 tests, with 0 failures`.

- [ ] **Step 4: Chạy MCP contract thủ công**

Run:

```bash
swift build
OPENSIM_HOME=/tmp/opensim-mcp-check .build/debug/opensim daemon run --foreground &
DAEMON_PID=$!
sleep 1
OPENSIM_HOME=/tmp/opensim-mcp-check .build/debug/opensim mcp --stdio <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":null}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"missing_tool","arguments":{}}}
EOF
kill "$DAEMON_PID"
```

Expected: ba dòng JSON-RPC; dòng 1 có `"protocolVersion":"2025-06-18"`; dòng 2 có 25 tool; dòng 3 có `"code":-32602`. Không có token trong output.

- [ ] **Step 5: Commit**

```bash
git add Tests/OpenSimCLITests/CatalogCLIParityTests.swift Tests/IntegrationTests/Plan3DaemonIntegrationTests.swift Tests/IntegrationTests/README-Plan3.md
git commit -m "test(daemon): add cli mcp parity and daemon restart integration"
```

---

## Spec coverage

| Mục spec | Nội dung | Task |
|---|---|---|
| 5.2 | Daemon trong user session, state file, auto-start 5 giây, đóng app không chết daemon | 3, 10, 11, 12 |
| 5.3 | Session, control/observe, lease TTL 300, heartbeat 30, takeover grace 3, lỗi lease | 4, 6, 8, 13 |
| 5.5 | Boot qua `/v1/devices/{udid}/actions`, event `device.state.changed`, lease flow | 7, 8, 9 |
| 7.1 | CLI `--json`, `--device`, `--timeout`, `--yes`, `--session`, `--direct`, exit code | 12, 16 |
| 7.2 | CLI `daemon`, `session`, `mcp`; giữ các nhóm Plan 1 | 12, 14 |
| 8.1 | MCP stdio JSON-RPC, HTTP Streamable, Bearer token, Host/Origin, protocol 2025-06-18 | 7, 13, 14, 15 |
| 8.2 | Tool catalog động từ `OperationCatalog`, destructive confirm, session tools | 2, 13 |
| 8.3 | JSON-RPC error code chuẩn, business error trong `structuredContent.error` | 13 |
| 12 | Loopback, token 32 byte, file `0600`, không shell string, audit | 3, 7, 10, 11 |
| 13 | Audit JSONL, daemon log rotate, health/version | 5, 10 |
| 14.2 | Test daemon start/stop/restart, token sai, Host sai, SSE reconnect | 7, 8, 9, 16 |
| 14.2 | Test MCP tools/list, tools/call, errors; session/lease conflict/expiry/takeover | 4, 13, 15 |
| 15 | Hummingbird 2, swift-log, không MCP SDK, không database | 1 |
| 16 Plan 3 | Daemon + session/lease + MCP stdio/HTTP; daemon không fail khi Plan 2 service nil | 6, 7, 10, 15 |

Ngoài phạm vi Plan 3: `screen_*`, `ui_*` (Plan 2: `docs/superpowers/plans/2026-10-20-opensim-plan-2-screen-input-a11y.md`), storage/perf endpoints (Plan 5: `docs/superpowers/plans/2026-10-20-opensim-plan-5-storage-performance.md`), app macOS (Plan 4: `docs/superpowers/plans/2026-10-20-opensim-plan-4-macos-app.md`), watch/tv (Plan 6: `docs/superpowers/plans/2026-10-20-opensim-plan-6-watchos-tvos.md`). Khi các service đó chưa có, dispatcher trả `capability_unavailable` và daemon vẫn start.

## Exit criteria

- `swift build` thành công với Hummingbird 2, swift-log, NIOCore; không có dependency MCP SDK.
- Unit test `OpenSimProtocolTests`, `OpenSimDaemonTests`, `OpenSimMCPTests`, `OpenSimCLITests` pass.
- `OPENSIM_INTEGRATION=1 swift test --filter Plan3DaemonIntegrationTests` pass với binary `.build/debug/opensim` và full Xcode.
- Daemon restart tạo token mới, ghi state `0600`, xoá state khi dừng; lock chặn instance thứ hai.
- Lease conflict trả `lease_conflict` kèm owner/expiresAt; lease hết hạn trả `lease_revoked`; takeover thay lease control; observe nhiều owner.
- Request sai token trả 401; Host/Origin ngoài loopback trả 403; `/v1/health` không cần token nhưng vẫn kiểm tra Host.
- `/v1/events` và `/mcp` GET dùng SSE, replay theo `Last-Event-ID`; MCP POST yêu cầu `Mcp-Session-Id` sau initialize.
- `tools/list` lấy đúng 25 tool từ catalog Plan 3; tool Plan 2/5 sẽ xuất hiện tự động khi catalog được mở rộng.
- MCP `initialize`, `tools/list`, `tools/call` success và error contract pass; business error nằm trong `structuredContent.error`, protocol error dùng JSON-RPC code.
- CLI mặc định dùng daemon; `--direct` vẫn chạy cho doctor/test; `opensim daemon start/stop/restart/status/logs` hoạt động.
- Không có storage/perf implementation, không có app UI, không có browser automation.

