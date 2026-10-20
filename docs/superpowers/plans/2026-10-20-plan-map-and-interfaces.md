# OpenSim Plan Map and Shared Interfaces

- Ngày: 2026-10-20
- Trạng thái: coordination contract cho các plan author
- Spec (nguồn sự thật): `docs/superpowers/specs/2026-10-19-open-simulator-design.md`
- Spike: `docs/superpowers/plans/2026-10-19-opensim-plan-0-private-api-spike.md`

Khi contract này mâu thuẫn với spec, spec thắng. Contract chỉ khóa tên module, type, protocol và ranh giới giữa các plan để tránh lệch.

## 1. Plan map

| Plan | File | Phạm vi | Phụ thuộc | Exit criteria |
|---|---|---|---|---|
| 0 | `2026-10-19-opensim-plan-0-private-api-spike.md` | Spike private API | Spec | Report render/input/a11y/watch/tv |
| 1 | `2026-10-20-opensim-plan-1-core-bridge-cli.md` | Core, Bridge lifecycle, CLI device/runtime/app/log | Plan 0 (chỉ cần cho quyết định bridge) | CLI lifecycle chạy trên simulator thật |
| 2 | `2026-10-20-opensim-plan-2-screen-input-a11y.md` | Screen, input, accessibility, CLI `ui`, `OpenSimBridgeUI` | Plan 1, Plan 0 report | Agent thao tác + đọc UI qua CLI |
| 3 | `2026-10-20-opensim-plan-3-daemon-session-mcp.md` | Daemon, session/lease, protocol, MCP stdio/HTTP | Plan 1, Plan 2 (service protocols) | MCP contract + đa session |
| 4 | `2026-10-20-opensim-plan-4-macos-app.md` | App macOS, device windows, full gesture, quick switch | Plan 2, Plan 3 | UI dùng dữ liệu thật từ daemon |
| 5 | `2026-10-20-opensim-plan-5-storage-performance.md` | Storage scan/clean, CPU/RAM metrics, CLI/MCP/UI | Plan 3, Plan 4 (tab shell) | Quản trị kho + runtime metrics |
| 6 | `2026-10-20-opensim-plan-6-watchos-tvos.md` | watchOS/tvOS runtime, adapter, fixture, parity | Plan 2 | Ma trận iOS/watch/tv |
| 7 | `2026-10-20-opensim-plan-7-release.md` | Hardening, CI, notarize, Homebrew, docs, release | Plan 1-6 | Bản open-source cài được |
| 8 | `2026-10-20-opensim-plan-8-visionos.md` | visionOS adapter, fixture, test | Plan 7 | visionOS verified |
| 9 | `2026-10-20-opensim-plan-9-physical-devices.md` | Thiết bị thật qua CoreDevice | Plan 3, Plan 7 | Physical device verified |
| 10 | `2026-10-20-opensim-plan-10-android-emulator.md` | Android Emulator: AVD, adb, gRPC, uiautomator, system image | Plan 2, Plan 3, Plan 4, Plan 5 | Android AVD lifecycle + screen/input/a11y |

## 2. Repo layout

```text
Package.swift
Sources/
  OpenSimCore/
    Domain/
    Protocol/
    Catalog/
    Errors/
  OpenSimBridge/
    Private/
    Services/
    Capabilities/
  OpenSimBridgeUI/
    SimulatorScreenView.swift
  OpenSimAndroid/
    Services/
    Generated/
  OpenSimProtocol/
    Envelope.swift
    Operations.swift
    Events.swift
  OpenSimDaemon/
    Server/
    Platform/
    Sessions/
    Storage/
    Metrics/
    LaunchAgent/
  OpenSimCLI/
    Commands/
    Output/
  OpenSimMCP/
    Stdio/
    HTTP/
    Tools/
App/
  project.yml
  Sources/OpenSimApp/
    App/
    Windows/
    Sidebar/
    Storage/
    Performance/
    Activity/
    Settings/
Fixtures/
  OpenSimFixture/
  OpenSimFixtureWatch/
  OpenSimFixtureTV/
Tests/
  OpenSimCoreTests/
  OpenSimBridgeTests/
  OpenSimProtocolTests/
  OpenSimDaemonTests/
  OpenSimCLITests/
  OpenSimMCPTests/
  OpenSimAppUITests/
  IntegrationTests/
docs/
  superpowers/
    specs/
    plans/
    spikes/
```

- Plan 1 tạo `Package.swift`, `OpenSimCore`, `OpenSimBridge`, `OpenSimCLI`, tests.
- Plan 2 thêm `OpenSimBridgeUI`, fixture iOS, `OpenSimBridgeTests` cho screen/input/a11y.
- Plan 3 thêm `OpenSimProtocol`, `OpenSimDaemon`, `OpenSimMCP`.
- Plan 4 thêm `App/`, XcodeGen, UI tests.
- Plan 5 thêm storage/metrics vào daemon, CLI, MCP, app tabs.
- Plan 6 thêm fixture watch/tv và platform adapters.
- Plan 7 thêm packaging scripts, CI, release docs.
- Plan 8/9 thêm module adapter riêng, không đổi tên type lõi.

## 3. Ranh giới module

| Module | Được làm | Không được làm |
|---|---|---|
| `OpenSimCore` | Domain, protocol, catalog, error, envelope | AppKit, private framework, process, network |
| `OpenSimBridge` | CoreSimulator/SimulatorKit, dynamic loading, capability, `simctl` fallback | SwiftUI, daemon, CLI parsing |
| `OpenSimBridgeUI` | NSView wrapper cho screen/gesture | Daemon, storage, metrics |
| `OpenSimProtocol` | Codable request/response/event dùng chung | Business logic |
| `OpenSimDaemon` | HTTP/SSE, session/lease, service composition, storage, metrics | SwiftUI, direct CLI parsing |
| `OpenSimCLI` | Parse args, gọi daemon hoặc direct bridge, render bảng/JSON | SwiftUI, private API trực tiếp |
| `OpenSimMCP` | JSON-RPC stdio/HTTP, tool adapter từ catalog | Business logic, private API |
| `OpenSimApp` | SwiftUI shell, AppKit screen view, window/lease UX | Logic lifecycle riêng ngoài daemon/bridge |

## 4. Shared domain types

Tên dưới đây là bắt buộc. Plan sau có thể thêm field có default hoặc type mới, nhưng không đổi tên/kiểu đã có.

```swift
public struct DeviceID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String)
}

public struct RuntimeID: Hashable, Codable, Sendable, RawRepresentable { public let rawValue: String }
public struct SessionID: Hashable, Codable, Sendable, RawRepresentable { public let rawValue: String }
public struct LeaseID: Hashable, Codable, Sendable, RawRepresentable { public let rawValue: String }
public struct RecordingID: Hashable, Codable, Sendable, RawRepresentable { public let rawValue: String }

public enum Platform: String, Codable, Sendable {
    case iOS, watchOS, tvOS, visionOS, android, unknown
}

public enum DeviceState: String, Codable, Sendable {
    case shutdown, booting, booted, shuttingDown, erasing, deleting, unknown
}

public struct Device: Codable, Sendable, Identifiable {
    public let id: DeviceID
    public var name: String
    public var platform: Platform
    public var deviceType: String
    public var runtime: RuntimeID
    public var state: DeviceState
    public var isAvailable: Bool
    public var dataPath: String?
    public var lastBootedAt: Date?
}

public enum RuntimeSource: String, Codable, Sendable {
    case system
    case xcodeCatalog = "xcode_catalog"
    case file
}

public struct Runtime: Codable, Sendable, Identifiable {
    public let id: RuntimeID
    public var name: String
    public var platform: Platform
    public var version: String
    public var build: String
    public var isAvailable: Bool
    public var path: String?
    public var sizeBytes: Int64? = nil
    public var source: RuntimeSource? = nil
    public var deviceCount: Int? = nil
}

public struct AppInfo: Codable, Sendable, Identifiable {
    public let id: String
    public var displayName: String?
    public var version: String?
    public var build: String?
    public var dataContainer: String?
    public var appContainer: String?
}

public struct Point: Codable, Sendable { public var x: Double; public var y: Double }
public struct Rect: Codable, Sendable { public var x: Double; public var y: Double; public var width: Double; public var height: Double }

public struct ScreenInfo: Codable, Sendable, Identifiable {
    public let id: UInt32
    public var width: Int
    public var height: Int
    public var scale: Double
    public var rotation: Double
    public var displayClass: Int
}

public enum ScreenshotFormat: String, Codable, Sendable { case png, jpeg }
public struct Screenshot: Codable, Sendable {
    public var path: String?
    public var data: Data?
    public var format: ScreenshotFormat
    public var width: Int
    public var height: Int
    public var scale: Double
    public var capturedAt: Date
}

public struct UIElement: Codable, Sendable, Identifiable {
    public let id: String
    public var role: String
    public var label: String?
    public var identifier: String?
    public var value: String?
    public var frame: Rect
    public var enabled: Bool
    public var selected: Bool
    public var children: [UIElement]
}

public struct UITree: Codable, Sendable {
    public var root: UIElement
    public var nodeCount: Int
    public var truncated: Bool
}

public struct ElementSelector: Codable, Sendable {
    public var role: String?
    public var label: String?
    public var identifier: String?
    public var text: String?
}

public enum StorageCategory: String, Codable, Sendable, CaseIterable {
    case simulatorDevice, simulatorCache, simulatorLog, runtime, derivedData, archive, appData
}

public struct StorageItem: Codable, Sendable, Identifiable {
    public let id: String
    public var category: StorageCategory
    public var path: String
    public var sizeBytes: Int64
    public var lastUsedAt: Date?
    public var safeToDelete: Bool
    public var reason: String?
    public var children: [StorageItem]
}

public struct StorageScan: Codable, Sendable {
    public var id: String
    public var createdAt: Date
    public var approximate: Bool
    public var items: [StorageItem]
    public var totalBytes: Int64
    public var reclaimableBytes: Int64
}

public struct CleanPlan: Codable, Sendable {
    public var token: String
    public var expiresAt: Date
    public var itemIDs: [String]
    public var reclaimableBytes: Int64
}

public struct CleanResultItem: Codable, Sendable {
    public var itemID: String
    public var success: Bool
    public var error: OpenSimError?
}

public struct MetricSample: Codable, Sendable {
    public var deviceID: DeviceID
    public var timestamp: Date
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var processCount: Int
    public var diskReadBytes: UInt64
    public var diskWriteBytes: UInt64
}

public struct ProcessSample: Codable, Sendable {
    public var pid: Int32
    public var parentPID: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64
}

public enum LeaseMode: String, Codable, Sendable { case control, observe }

public struct Session: Codable, Sendable, Identifiable {
    public let id: SessionID
    public var clientKind: String
    public var clientName: String
    public var createdAt: Date
    public var lastSeenAt: Date
}

public struct Lease: Codable, Sendable, Identifiable {
    public let id: LeaseID
    public var deviceID: DeviceID
    public var sessionID: SessionID
    public var mode: LeaseMode
    public var ownerName: String
    public var acquiredAt: Date
    public var expiresAt: Date
}

public struct AuditEvent: Codable, Sendable, Identifiable {
    public let id: String
    public var timestamp: Date
    public var actor: String
    public var sessionID: SessionID?
    public var leaseID: LeaseID?
    public var action: String
    public var target: String
    public var result: String
    public var durationMs: Int
}

public struct ResponseMeta: Codable, Sendable {
    public var requestId: String
    public var durationMs: Int
}

public struct Envelope<T: Codable & Sendable>: Codable, Sendable {
    public var schemaVersion: Int
    public var ok: Bool
    public var data: T?
    public var error: OpenSimError?
    public var meta: ResponseMeta
}

public struct OpenSimError: Error, Codable, Sendable {
    public var code: String
    public var message: String
    public var details: [String: String]
    public var recovery: String?
    public var retryable: Bool
}

public enum LogLevel: String, Codable, Sendable { case debug, info, notice, warning, error, fault }

public struct LogEntry: Codable, Sendable {
    public var timestamp: Date
    public var level: LogLevel
    public var subsystem: String?
    public var category: String?
    public var process: String?
    public var message: String
}

public struct LogPage: Codable, Sendable {
    public var entries: [LogEntry]
    public var nextCursor: String?
}

public struct Key: Codable, Sendable {
    public var name: String
    public var keyCode: UInt16?
}

public struct KeyModifiers: Codable, Sendable {
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool
}

public enum HardwareButton: String, Codable, Sendable {
    case home, lock, side, volumeUp, volumeDown, appleTVSelect, appleTVMenu, appleTVHome
}

public enum VideoCodec: String, Codable, Sendable { case h264, hevc }

public enum ContainerKind: String, Codable, Sendable { case app, data, group }
```

## 5. Service protocols

```swift
public protocol DeviceControlling: Sendable {
    func listDevices() async throws -> [Device]
    func device(_ id: DeviceID) async throws -> Device
    func createDevice(name: String, deviceType: String, runtime: RuntimeID?) async throws -> Device
    func cloneDevice(_ id: DeviceID, name: String) async throws -> Device
    func boot(_ id: DeviceID, wait: Bool) async throws -> Device
    func shutdown(_ id: DeviceID, wait: Bool) async throws -> Device
    func erase(_ id: DeviceID) async throws -> Device
    func delete(_ id: DeviceID) async throws
    func rename(_ id: DeviceID, to name: String) async throws -> Device
    func pair(watch: DeviceID, phone: DeviceID) async throws
}

public protocol RuntimeControlling: Sendable {
    func listRuntimes() async throws -> [Runtime]
    func downloadRuntime(platform: Platform, version: String) async throws -> Runtime
    func installRuntime(at path: String) async throws -> Runtime
    func deleteRuntime(_ id: RuntimeID) async throws
    func verifyRuntime(_ id: RuntimeID) async throws
}

public protocol AppControlling: Sendable {
    func listApps(on device: DeviceID, filter: String?) async throws -> [AppInfo]
    func installApp(on device: DeviceID, at path: String) async throws -> AppInfo
    func uninstallApp(on device: DeviceID, bundleID: String) async throws
    func launchApp(on device: DeviceID, bundleID: String, args: [String], environment: [String: String]) async throws -> Int32
    func terminateApp(on device: DeviceID, bundleID: String) async throws
    func appInfo(on device: DeviceID, bundleID: String) async throws -> AppInfo
    func containerPath(on device: DeviceID, bundleID: String, kind: ContainerKind) async throws -> String
}

public protocol LogControlling: Sendable {
    func tailLogs(on device: DeviceID, cursor: String?, limit: Int, filter: String?) async throws -> LogPage
}

public protocol ScreenControlling: Sendable {
    func screens(for device: DeviceID) async throws -> [ScreenInfo]
    func screenshot(on device: DeviceID, format: ScreenshotFormat, scale: Double, quality: Int?) async throws -> Screenshot
    func startRecording(on device: DeviceID, to path: String?, codec: VideoCodec) async throws -> RecordingID
    func stopRecording(_ id: RecordingID) async throws -> String
}

public protocol InputControlling: Sendable {
    func tap(on device: DeviceID, at point: Point, settle: Bool) async throws
    func swipe(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws
    func longPress(on device: DeviceID, at point: Point, durationMs: Int) async throws
    func drag(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws
    func pinch(on device: DeviceID, center: Point, scale: Double, durationMs: Int) async throws
    func rotate(on device: DeviceID, center: Point, angle: Double, durationMs: Int) async throws
    func scroll(on device: DeviceID, deltaX: Double, deltaY: Double, at point: Point?) async throws
    func typeText(on device: DeviceID, text: String) async throws
    func key(on device: DeviceID, key: Key, modifiers: KeyModifiers) async throws
    func button(on device: DeviceID, button: HardwareButton) async throws
}

public protocol AccessibilityReading: Sendable {
    func tree(on device: DeviceID, maxDepth: Int, maxNodes: Int) async throws -> UITree
    func find(on device: DeviceID, selector: ElementSelector) async throws -> [UIElement]
}

public protocol StorageManaging: Sendable {
    func scanStorage(refresh: Bool) async throws -> StorageScan
    func storageItems(scanID: String, parentID: String?) async throws -> [StorageItem]
    func planClean(scanID: String, itemIDs: [String]) async throws -> CleanPlan
    func applyClean(planToken: String, itemIDs: [String]) async throws -> [CleanResultItem]
}

public protocol MetricsReading: Sendable {
    func deviceMetrics(since: Date?) async throws -> [MetricSample]
    func processes(on device: DeviceID) async throws -> [ProcessSample]
}
```

`Key`, `KeyModifiers`, `HardwareButton`, `VideoCodec`, `ContainerKind`, `LogPage`, `LogEntry` do chưa có trong snippet trên; Plan 1 định nghĩa enum/struct tương ứng trong `OpenSimCore/Domain`, Plan 2/5 chỉ dùng, không đổi tên.

`OpenSimBridge` aggregate:

```swift
public struct BridgeCapabilities: Codable, Sendable {
    public var render: Capability
    public var hid: Capability
    public var accessibility: Capability
    public var screenshot: Capability
    public var video: Capability
    public var watch: Capability
    public var tv: Capability
}

public enum Capability: String, Codable, Sendable {
    case available, unavailable, unknown
}

public protocol SimulatorBridge: Sendable {
    var capabilities: BridgeCapabilities { get async }
    var devices: any DeviceControlling { get }
    var runtimes: any RuntimeControlling { get }
    var apps: any AppControlling { get }
    var logs: any LogControlling { get }
    var screen: (any ScreenControlling)? { get }
    var input: (any InputControlling)? { get }
    var accessibility: (any AccessibilityReading)? { get }
}
```

Plan 1 trả `screen/input/accessibility = nil`; Plan 2 điền. Client phải kiểm tra optional và trả `capability_unavailable`.

## 6. Daemon protocol

### State file

`~/Library/Application Support/OpenSim/daemon.json`, quyền `0600`:

```json
{
  "pid": 12345,
  "port": 54321,
  "token": "base64url-32-bytes",
  "version": "0.1.0",
  "xcodeVersion": "27.1",
  "startedAt": "2026-10-20T10:00:00Z"
}
```

### HTTP endpoints

| Method | Path | Ý nghĩa |
|---|---|---|
| GET | `/v1/health` | health + version + capabilities |
| GET | `/v1/devices` | danh sách device |
| GET | `/v1/devices/{udid}` | chi tiết device |
| POST | `/v1/devices/{udid}/actions` | lifecycle action |
| GET | `/v1/events` | SSE event stream |
| POST | `/v1/sessions` | tạo session |
| DELETE | `/v1/sessions/{id}` | đóng session |
| POST | `/v1/leases` | acquire lease |
| POST | `/v1/leases/{id}/heartbeat` | gia hạn |
| DELETE | `/v1/leases/{id}` | release |
| POST | `/v1/operations` | thực thi operation từ catalog |
| POST | `/v1/storage/scans` | bắt đầu scan |
| GET | `/v1/storage/scans/{id}` | kết quả scan |
| POST | `/v1/storage/clean-plans` | tạo plan |
| POST | `/v1/storage/clean-plans/{id}/apply` | apply plan |
| GET | `/v1/perf/devices` | metric samples |
| GET | `/v1/perf/devices/{udid}/processes` | process list |
| POST | `/mcp` | MCP JSON-RPC |
| GET | `/mcp` | MCP SSE stream |

### Auth và binding

- Bind `127.0.0.1`, port động.
- `Authorization: Bearer <token>` cho mọi endpoint trừ `/v1/health` (health vẫn kiểm tra Host).
- Kiểm tra `Host` thuộc `127.0.0.1` hoặc `localhost`; từ chối `Origin` khác.
- Không CORS.

### SSE events

`device.state.changed`, `session.created`, `session.closed`, `lease.changed`, `lease.revoked`, `storage.scan.progress`, `storage.scan.completed`, `metrics.sample`, `audit.appended`, `daemon.health`.

### Operation

```swift
public struct OperationRequest: Codable, Sendable {
    public var operation: String
    public var parameters: [String: String]
    public var sessionID: SessionID?
    public var leaseID: LeaseID?
    public var dryRun: Bool?
}

public struct OperationResult: Codable, Sendable {
    public var operation: String
    public var data: Data
    public var auditID: String?
}
```

`OperationRequest.parameters` dùng string map để JSON ổn định; type cụ thể được parse trong handler. Ảnh lớn không đi qua operation result; dùng `screen_screenshot` trả metadata + path, hoặc endpoint riêng cho MCP image content.

## 7. Command catalog

Plan 1 định nghĩa:

```swift
public struct Operation: Sendable {
    public var cliPath: [String]
    public var mcpName: String
    public var summary: String
    public var requiresControlLease: Bool
    public var destructive: Bool
    public var readOnly: Bool
    public var parameters: [OperationParameter]
}

public struct OperationParameter: Sendable {
    public var name: String
    public var type: String
    public var required: Bool
    public var defaultValue: String?
}

public struct OperationCatalog: Sendable {
    public private(set) var operations: [String: Operation]
    public mutating func register(_ operation: Operation)
    public func operation(forCLI path: [String]) -> Operation?
    public func operation(forMCP name: String) -> Operation?
}
```

- CLI và MCP adapter đều đọc catalog; không hardcode danh sách lệnh ở hai nơi.
- Plan 1 đăng ký device/runtime/app/log/doctor; Plan 2 đăng ký `ui`; Plan 3 đăng ký session/daemon/mcp; Plan 5 đăng ký `storage`/`perf`.
- MCP tool name lấy đúng bảng trong spec mục 8.2.
- Tool destructive phải có `destructive = true`; MCP adapter tự thêm yêu cầu `confirm`/`planToken`.

## 8. Naming and output rules

- CLI binary: `opensim`; app: `OpenSim.app`; bundle ID app `dev.opensim.app`; daemon `dev.opensim.daemon`.
- JSON envelope schema version `1`.
- Exit codes: `0`, `2`, `3`, `4`, `5`, `6`, `7`, `10`.
- Error codes dùng đúng danh sách spec 8.3.
- Screenshot CLI mặc định ghi file; MCP mặc định JPEG 80 scale 0.5.
- Không dùng shell string; mọi process chạy argument array.
- Path validation theo allowlist root trong spec.

## 9. Testing conventions

- Unit test bằng XCTest trong target tương ứng.
- Integration test chỉ chạy khi `OPENSIM_INTEGRATION=1`; dùng simulator thật, fixture app.
- `Fixtures/OpenSimFixture` do Plan 2 tạo; Plan 1 smoke test dùng app Settings (`com.apple.Preferences`) để tránh phụ thuộc fixture.
- UI test bằng XCUITest; không dùng Chrome.
- Mỗi task có check đỏ trước, implement, check xanh, commit.
- Không mock private API; protocol fake ở Core.

## 10. Plan authoring rules

- Mỗi plan bắt đầu bằng header bắt buộc của writing-plans: Goal, Architecture, Tech Stack, Spec, Global Constraints.
- Có bảng File Structure, Tasks với Files/Interfaces, steps có code thật, lệnh chạy, expected, commit.
- Không placeholder: không TBD/TODO/"implement later"/"similar to Task N"/dấu ba chấm.
- Có mục "Spec coverage" ánh xạ mục spec → task, và "Exit criteria".
- Được tham chiếu plan khác bằng path; không copy nội dung plan khác.
- Không sửa spec, contract, Plan 0 hoặc plan của agent khác.
- Không viết production code; chỉ plan + code snippet trong plan.
- Văn xuôi tiếng Việt, code/identifier tiếng Anh; không ký tự CJK.
- Nếu private API chưa được xác minh bởi Plan 0, dùng capability gate và fallback đã định trong spec; không bịa selector mới.
- Plan 8/9 là post-release; không được yêu cầu đổi type/protocol lõi ngoài việc thêm adapter.
- Plan 10 Android là platform thứ hai: adapter `OpenSimAndroid`, không đổi `OpenSimBridge`; dùng chung `Platform.android`, operation catalog, lease/audit và UI shell. Plan 10 có thể chạy song song Plan 6 hoặc sau Plan 7 tùy release scope; Plan 5 là dependency của Plan 10.

## 11. Quyền sở hữu file

| Agent | Plan sở hữu | Được sửa |
|---|---|---|
| Author A | 1, 3 | Hai file plan đó |
| Author B | 2, 4 | Hai file plan đó |
| Author C | 5, 6 | Hai file plan đó |
| Author D | 7, 8 | Hai file plan đó |
| Author E | 9 | File plan 9 |

Reviewer chỉ đọc và báo findings; không sửa file. Main agent tổng hợp và giao revision đúng owner.
