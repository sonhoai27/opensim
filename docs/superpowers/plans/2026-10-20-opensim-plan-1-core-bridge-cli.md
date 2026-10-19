# OpenSim Plan 1 — Core, Bridge Lifecycle, CLI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dựng nền móng OpenSim: SwiftPM package, domain/envelope/error/catalog trong `OpenSimCore`, lifecycle device/runtime/app/log bằng `simctl` trong `OpenSimBridge`, và CLI `opensim` direct mode với `doctor` capability report.

**Architecture:** `OpenSimCore` chỉ chứa domain, protocol, catalog, error và validation, không biết private framework. `OpenSimBridge` bọc `xcrun simctl` bằng argument array, dịch output thành domain type, và trả `screen/input/accessibility = nil` để Plan 2 điền sau. `OpenSimCLI` dịch cờ CLI thành operation trong catalog, gọi `BridgeOperationExecutor`, rồi render envelope JSON hoặc bảng người đọc.

**Tech Stack:** Swift 6 language mode, SwiftPM, macOS 27.0+, `swift-argument-parser`, `xcrun simctl`, Foundation, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-19-open-simulator-design.md`

## Global Constraints

- macOS 27.0+; arm64; Xcode 27.1 là bản chính, Xcode 27.0 best-effort; yêu cầu full Xcode.
- Swift 6 language mode; SwiftPM; package name `OpenSim`; CLI binary `opensim`; version `0.1.0`.
- Dependency Plan 1 chỉ gồm `swift-argument-parser`; không dùng MCP SDK, không database, không web view.
- `simctl` là đường chính cho device/runtime/app/log. Không gọi selector private để thực hiện lifecycle.
- Plan 0 chưa chạy. Chỉ được kiểm tra class đã nêu trong spec/Plan 0; không gọi selector private, không bịa selector.
- `SimulatorBridge.screen`, `.input`, `.accessibility` trả `nil`; Plan 1 phải build và test khi không có Plan 2.
- Không có daemon, MCP, storage, performance, app UI, `ui` command trong Plan 1.
- JSON envelope schema version `1`; exit code `0`, `2`, `3`, `4`, `5`, `6`, `7`, `10`.
- Error code dùng danh sách spec 8.3, bổ sung `capability_unavailable` cho client kiểm tra optional service.
- Không dựng shell string; mọi process chạy bằng `Process` với argument array.
- Validate UDID theo UUID, bundle ID theo regex, path theo allowlist root trước khi chạm filesystem hoặc `simctl`.
- Mọi task có check đỏ trước, implement, check xanh, commit. Không chạy commit trong lúc viết plan.
- Văn xuôi tiếng Việt; code, type, identifier, command tiếng Anh; không ký tự CJK.

---

## File Structure

| File | Trách nhiệm | Commit? |
|---|---|---|
| `Package.swift` | Khai báo target/product/test của Plan 1 | Có |
| `Sources/OpenSimCore/Domain/Identifiers.swift` | `DeviceID`, `RuntimeID`, `SessionID`, `LeaseID`, `RecordingID` encode dạng string | Có |
| `Sources/OpenSimCore/Domain/Device.swift` | `Platform`, `DeviceState`, `Device`, parse state | Có |
| `Sources/OpenSimCore/Domain/Runtime.swift` | `Runtime` | Có |
| `Sources/OpenSimCore/Domain/AppInfo.swift` | `AppInfo`, `ContainerKind` | Có |
| `Sources/OpenSimCore/Domain/Input.swift` | `Point`, `Rect`, `Key`, `KeyModifiers`, `HardwareButton`, `VideoCodec` | Có |
| `Sources/OpenSimCore/Domain/Log.swift` | `LogLevel`, `LogEntry`, `LogPage` | Có |
| `Sources/OpenSimCore/Domain/Screen.swift` | `ScreenInfo`, `ScreenshotFormat`, `Screenshot` | Có |
| `Sources/OpenSimCore/Domain/UI.swift` | `UIElement`, `UITree`, `ElementSelector` | Có |
| `Sources/OpenSimCore/Domain/Storage.swift` | Storage domain types theo contract | Có |
| `Sources/OpenSimCore/Domain/Metrics.swift` | `MetricSample`, `ProcessSample` | Có |
| `Sources/OpenSimCore/Domain/Session.swift` | `LeaseMode`, `Session`, `Lease` | Có |
| `Sources/OpenSimCore/Domain/Audit.swift` | `AuditEvent` | Có |
| `Sources/OpenSimCore/Domain/CrashReport.swift` | `CrashReport` cho `log crash` | Có |
| `Sources/OpenSimCore/Domain/CleanResultItem.swift` | `CleanResultItem` (định nghĩa sau `OpenSimError`) | Có |
| `Sources/OpenSimCore/Domain/OperationResults.swift` | `OperationAck`, `AppLaunchResult`, `ContainerPathResult` | Có |
| `Sources/OpenSimCore/Domain/Doctor.swift` | `Capability`, `BridgeCapabilities`, `DaemonStatus`, `DaemonHealth`, `XcodeInfo`, `FrameworkStatus`, `PrivateAPIStatus`, `DoctorReport` | Có |
| `Sources/OpenSimCore/Support/OpenSimPaths.swift` | Đường dẫn Application Support/Logs, override `OPENSIM_HOME` | Có |
| `Sources/OpenSimCore/Support/OpenSimVersion.swift` | Version string dùng chung | Có |
| `Sources/OpenSimCore/Protocol/ServiceProtocols.swift` | Các protocol service theo contract, thêm `DoctorReporting`, `CrashReportReading` | Có |
| `Sources/OpenSimCore/Protocol/SimulatorBridge.swift` | `BridgeService`, `SimulatorBridge` | Có |
| `Sources/OpenSimCore/Protocol/Envelope.swift` | `ResponseMeta`, `Envelope`, `EmptyPayload` | Có |
| `Sources/OpenSimCore/Protocol/JSONCoding.swift` | Encoder/decoder ổn định cho JSON và date | Có |
| `Sources/OpenSimCore/Protocol/OperationParameters.swift` | Parse và validate parameter string map | Có |
| `Sources/OpenSimCore/Errors/OpenSimError.swift` | Error struct và factory | Có |
| `Sources/OpenSimCore/Errors/ErrorCode.swift` | Tên error code ổn định | Có |
| `Sources/OpenSimCore/Errors/ExitCode.swift` | Map error code sang exit code | Có |
| `Sources/OpenSimCore/Catalog/Operation.swift` | `Operation`, `OperationParameter`, `BridgeService` | Có |
| `Sources/OpenSimCore/Catalog/OperationCatalog.swift` | Đăng ký, tra cứu CLI/MCP, validate | Có |
| `Sources/OpenSimCore/Catalog/Plan1Operations.swift` | Catalog operations của Plan 1 | Có |
| `Sources/OpenSimCore/Validation/IdentifierValidation.swift` | UDID, bundle ID, name, runtime identifier | Có |
| `Sources/OpenSimCore/Validation/PathPolicy.swift` | Allowlist root, symlink resolution, app/runtime path | Có |
| `Sources/OpenSimCore/Validation/DeviceResolver.swift` | Resolve UDID/name/default booted | Có |
| `Sources/OpenSimBridge/Simctl/SimctlCommand.swift` | Argument builder cho mọi lệnh simctl Plan 1 | Có |
| `Sources/OpenSimBridge/Simctl/SimctlExecutor.swift` | `SimctlExecuting`, process executor, timeout | Có |
| `Sources/OpenSimBridge/Simctl/SimctlErrorMapper.swift` | stderr sang `OpenSimError` | Có |
| `Sources/OpenSimBridge/Simctl/SimctlPayloads.swift` | Decodable shape của `simctl list devices -j` | Có |
| `Sources/OpenSimBridge/Services/SimctlDeviceService.swift` | `DeviceControlling` | Có |
| `Sources/OpenSimBridge/Services/SimctlRuntimeService.swift` | `RuntimeControlling` | Có |
| `Sources/OpenSimBridge/Services/SimctlAppService.swift` | `AppControlling` | Có |
| `Sources/OpenSimBridge/Services/SimctlPlistParser.swift` | Parse OpenStep plist của `listapps`/`appinfo` | Có |
| `Sources/OpenSimBridge/Services/SimctlLogService.swift` | `LogControlling`, cursor, NDJSON | Có |
| `Sources/OpenSimBridge/Services/CrashReportService.swift` | `CrashReportReading` | Có |
| `Sources/OpenSimBridge/Environment/XcodeLocator.swift` | `xcode-select`, `xcodebuild -version` | Có |
| `Sources/OpenSimBridge/Environment/FrameworkLocator.swift` | Đường dẫn CoreSimulator/SimulatorKit | Có |
| `Sources/OpenSimBridge/Environment/PrivateFrameworkProbe.swift` | `dlopen` + class check, không gọi selector | Có |
| `Sources/OpenSimBridge/Environment/DaemonStateProbe.swift` | Đọc state file cho doctor | Có |
| `Sources/OpenSimBridge/Environment/CapabilityEvaluator.swift` | Capability matrix từ runtime/framework | Có |
| `Sources/OpenSimBridge/Environment/DoctorService.swift` | `DoctorReporting` | Có |
| `Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift` | Operation name sang bridge call, confirm, parameter validation | Có |
| `Sources/OpenSimBridge/SimctlBridge.swift` | Aggregate `SimulatorBridge`, nil optional services | Có |
| `Sources/OpenSimCLI/OpenSimCommand.swift` | Root command, subcommand groups | Có |
| `Sources/OpenSimCLI/Commands/GlobalOptions.swift` | `--device`, `--json`, `--timeout`, `--yes` | Có |
| `Sources/OpenSimCLI/Commands/DeviceCommand.swift` | Nhóm device | Có |
| `Sources/OpenSimCLI/Commands/RuntimeCommand.swift` | Nhóm runtime | Có |
| `Sources/OpenSimCLI/Commands/AppCommand.swift` | Nhóm app | Có |
| `Sources/OpenSimCLI/Commands/LogCommand.swift` | tail, stream, crash | Có |
| `Sources/OpenSimCLI/Commands/DoctorCommand.swift` | Doctor report và capability matrix | Có |
| `Sources/OpenSimCLI/Runtime/CLIRuntime.swift` | Tạo `SimctlBridge`, backend, chạy command | Có |
| `Sources/OpenSimCLI/Runtime/CommandBackend.swift` | Protocol backend + direct backend | Có |
| `Sources/OpenSimCLI/Output/OutputRenderer.swift` | Envelope JSON, human table, stderr | Có |
| `Sources/OpenSimCLI/Output/Table.swift` | Bảng ASCII căn cột | Có |
| `Tests/OpenSimCoreTests/IdentifierAndDeviceTests.swift` | ID encode, state parse, platform parse | Có |
| `Tests/OpenSimCoreTests/DomainCodingTests.swift` | Codable domain types | Có |
| `Tests/OpenSimCoreTests/EnvelopeTests.swift` | Envelope success/failure | Có |
| `Tests/OpenSimCoreTests/ErrorTests.swift` | Error encode, exit code map | Có |
| `Tests/OpenSimCoreTests/CatalogTests.swift` | Catalog lookup/validate, Plan 1 set | Có |
| `Tests/OpenSimCoreTests/ValidationTests.swift` | UDID, bundle ID, path policy, device resolver | Có |
| `Tests/OpenSimBridgeTests/SimctlCommandTests.swift` | Argument array chính xác | Có |
| `Tests/OpenSimBridgeTests/SimctlDeviceServiceTests.swift` | List/get/boot/erase với stub | Có |
| `Tests/OpenSimBridgeTests/SimctlRuntimeServiceTests.swift` | Runtime list/install/delete | Có |
| `Tests/OpenSimBridgeTests/SimctlAppServiceTests.swift` | listapps/appinfo/launch/container | Có |
| `Tests/OpenSimBridgeTests/SimctlLogServiceTests.swift` | NDJSON, cursor, paging | Có |
| `Tests/OpenSimBridgeTests/CapabilityEvaluatorTests.swift` | Capability matrix | Có |
| `Tests/OpenSimCLITests/OutputRendererTests.swift` | Envelope JSON, table, lỗi | Có |
| `Tests/OpenSimCLITests/ExitCodeTests.swift` | Exit code mapping | Có |
| `Tests/OpenSimCLITests/CommandParsingTests.swift` | Parse cờ và nhóm lệnh | Có |
| `Tests/OpenSimCoreTests/BridgeProtocolTests.swift` | Capability và bridge service enum | Có |
| `Tests/OpenSimBridgeTests/BridgeOperationExecutorTests.swift` | Catalog dispatch, confirm, parameter validation | Có |
| `Tests/IntegrationTests/Plan1SettingsIntegrationTests.swift` | Settings app trên simulator booted, lifecycle device tạo mới | Có |
| `Tests/IntegrationTests/README.md` | Hướng dẫn chạy integration test | Có |

---

### Task 1: SwiftPM package, identifier và device domain

**Files:**
- Create: `Package.swift`
- Create: `Sources/OpenSimCore/Domain/Identifiers.swift`
- Create: `Sources/OpenSimCore/Domain/Device.swift`
- Test: `Tests/OpenSimCoreTests/IdentifierAndDeviceTests.swift`

**Interfaces:**
- Consumes: không có.
- Produces: `DeviceID`, `RuntimeID`, `SessionID`, `LeaseID`, `RecordingID` (RawRepresentable, encode dạng JSON string); `Platform`; `DeviceState`; `Device`; `Device.parseState(_:)`; `Device.platform(forRuntimeIdentifier:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimCoreTests/IdentifierAndDeviceTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class IdentifierAndDeviceTests: XCTestCase {
    func testDeviceIDEncodesAsSingleString() throws {
        let device = Device(
            id: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
            name: "iPhone Air",
            platform: .iOS,
            deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-Air",
            runtime: RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"),
            state: .booted,
            isAvailable: true,
            dataPath: "/tmp/device-data",
            lastBootedAt: nil
        )
        let data = try JSONEncoder().encode(device)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["id"] as? String, "95B3747B-7065-447E-AB1E-53065142C3FC")
        XCTAssertEqual(object["runtime"] as? String, "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
        XCTAssertEqual(object["state"] as? String, "booted")
    }

    func testDeviceStateParsing() {
        XCTAssertEqual(Device.parseState("Shutdown"), .shutdown)
        XCTAssertEqual(Device.parseState("Booted"), .booted)
        XCTAssertEqual(Device.parseState("Booting"), .booting)
        XCTAssertEqual(Device.parseState("Shutting Down"), .shuttingDown)
        XCTAssertEqual(Device.parseState("Erasing"), .erasing)
        XCTAssertEqual(Device.parseState("Deleting"), .deleting)
        XCTAssertEqual(Device.parseState("Unavailable"), .unknown)
    }

    func testPlatformFromRuntimeIdentifier() {
        XCTAssertEqual(Device.platform(forRuntimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0"), .iOS)
        XCTAssertEqual(Device.platform(forRuntimeIdentifier: "com.apple.CoreSimulator.SimRuntime.watchOS-27-0"), .watchOS)
        XCTAssertEqual(Device.platform(forRuntimeIdentifier: "com.apple.CoreSimulator.SimRuntime.tvOS-27-0"), .tvOS)
        XCTAssertEqual(Device.platform(forRuntimeIdentifier: "com.apple.CoreSimulator.SimRuntime.xrOS-27-0"), .visionOS)
        XCTAssertEqual(Device.platform(forRuntimeIdentifier: "custom"), .unknown)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter IdentifierAndDeviceTests
```

Expected: FAIL với `error: Source files for target OpenSimCore should be located under Sources/OpenSimCore` hoặc `cannot find type 'DeviceID' in scope`.

- [ ] **Step 3: Viết package và domain**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSim",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "OpenSimCore", targets: ["OpenSimCore"]),
    ],
    targets: [
        .target(name: "OpenSimCore"),
        .testTarget(name: "OpenSimCoreTests", dependencies: ["OpenSimCore"]),
    ],
    swiftLanguageModes: [.v6]
)
```

Create `Sources/OpenSimCore/Domain/Identifiers.swift`:

```swift
import Foundation

public struct DeviceID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RuntimeID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SessionID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct LeaseID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RecordingID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
```

Create `Sources/OpenSimCore/Domain/Device.swift`:

```swift
import Foundation

public enum Platform: String, Codable, Sendable, CaseIterable {
    case iOS
    case watchOS
    case tvOS
    case visionOS
    case unknown
}

public enum DeviceState: String, Codable, Sendable, CaseIterable {
    case shutdown
    case booting
    case booted
    case shuttingDown
    case erasing
    case deleting
    case unknown
}

public struct Device: Codable, Sendable, Identifiable, Equatable {
    public let id: DeviceID
    public var name: String
    public var platform: Platform
    public var deviceType: String
    public var runtime: RuntimeID
    public var state: DeviceState
    public var isAvailable: Bool
    public var dataPath: String?
    public var lastBootedAt: Date?

    public init(
        id: DeviceID,
        name: String,
        platform: Platform,
        deviceType: String,
        runtime: RuntimeID,
        state: DeviceState,
        isAvailable: Bool,
        dataPath: String?,
        lastBootedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.deviceType = deviceType
        self.runtime = runtime
        self.state = state
        self.isAvailable = isAvailable
        self.dataPath = dataPath
        self.lastBootedAt = lastBootedAt
    }

    public static func parseState(_ raw: String) -> DeviceState {
        let normalized = raw
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
        switch normalized {
        case "shutdown":
            return .shutdown
        case "booting":
            return .booting
        case "booted":
            return .booted
        case "shuttingdown":
            return .shuttingDown
        case "erasing":
            return .erasing
        case "deleting":
            return .deleting
        default:
            return .unknown
        }
    }

    public static func platform(forRuntimeIdentifier identifier: String) -> Platform {
        if identifier.contains(".iOS-") || identifier.hasSuffix(".iOS") {
            return .iOS
        }
        if identifier.contains(".watchOS-") || identifier.hasSuffix(".watchOS") {
            return .watchOS
        }
        if identifier.contains(".tvOS-") || identifier.hasSuffix(".tvOS") {
            return .tvOS
        }
        if identifier.contains(".visionOS-") || identifier.contains(".xrOS-") {
            return .visionOS
        }
        return .unknown
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter IdentifierAndDeviceTests
```

Expected: PASS; output có `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/OpenSimCore/Domain/Identifiers.swift Sources/OpenSimCore/Domain/Device.swift Tests/OpenSimCoreTests/IdentifierAndDeviceTests.swift
git commit -m "feat(core): add package scaffold and device domain"
```

---

### Task 2: Đầy đủ domain types còn thiếu của contract

**Files:**
- Create: `Sources/OpenSimCore/Domain/Runtime.swift`
- Create: `Sources/OpenSimCore/Domain/AppInfo.swift`
- Create: `Sources/OpenSimCore/Domain/Input.swift`
- Create: `Sources/OpenSimCore/Domain/Log.swift`
- Create: `Sources/OpenSimCore/Domain/Screen.swift`
- Create: `Sources/OpenSimCore/Domain/UI.swift`
- Create: `Sources/OpenSimCore/Domain/Storage.swift`
- Create: `Sources/OpenSimCore/Domain/Metrics.swift`
- Create: `Sources/OpenSimCore/Domain/Session.swift`
- Create: `Sources/OpenSimCore/Domain/Audit.swift`
- Create: `Sources/OpenSimCore/Domain/CrashReport.swift`
- Create: `Sources/OpenSimCore/Domain/OperationResults.swift`
- Create: `Sources/OpenSimCore/Domain/Doctor.swift`
- Create: `Sources/OpenSimCore/Support/OpenSimPaths.swift`
- Create: `Sources/OpenSimCore/Support/OpenSimVersion.swift`
- Test: `Tests/OpenSimCoreTests/DomainCodingTests.swift`

**Interfaces:**
- Consumes: `DeviceID`, `RuntimeID`, `SessionID`, `LeaseID`, `RecordingID`, `Platform`, `Device`.
- Produces: `BridgeCapabilities`, `Runtime`, `AppInfo`, `ContainerKind`, `Point`, `Rect`, `Key`, `KeyModifiers`, `HardwareButton`, `VideoCodec`, `LogLevel`, `LogEntry`, `LogPage`, `ScreenInfo`, `ScreenshotFormat`, `Screenshot`, `UIElement`, `UITree`, `ElementSelector`, `StorageCategory`, `StorageItem`, `StorageScan`, `CleanPlan`, `MetricSample`, `ProcessSample`, `LeaseMode`, `Session`, `Lease`, `AuditEvent`, `CrashReport`, `OperationAck`, `AppLaunchResult`, `ContainerPathResult`, `DaemonStatus`, `DaemonHealth`, `XcodeInfo`, `FrameworkStatus`, `PrivateAPIStatus`, `DoctorReport`, `OpenSimPaths`, `OpenSimVersion`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimCoreTests/DomainCodingTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class DomainCodingTests: XCTestCase {
    func testLogPageRoundTrip() throws {
        let entry = LogEntry(
            timestamp: Date(timeIntervalSince1970: 1_797_000_000.123456),
            level: .error,
            subsystem: "com.apple.UIKit",
            category: "Application",
            process: "Preferences",
            message: "launch failed"
        )
        let page = LogPage(entries: [entry], nextCursor: "cursor-1")
        let data = try JSONEncoder().encode(page)
        let decoded = try JSONDecoder().decode(LogPage.self, from: data)
        XCTAssertEqual(decoded.entries.first?.message, "launch failed")
        XCTAssertEqual(decoded.entries.first?.level, .error)
        XCTAssertEqual(decoded.nextCursor, "cursor-1")
    }

    func testContainerAndVideoEnumsUseStableRawValues() throws {
        XCTAssertEqual(ContainerKind.app.rawValue, "app")
        XCTAssertEqual(ContainerKind.data.rawValue, "data")
        XCTAssertEqual(ContainerKind.group.rawValue, "group")
        XCTAssertEqual(VideoCodec.h264.rawValue, "h264")
        XCTAssertEqual(VideoCodec.hevc.rawValue, "hevc")
        XCTAssertEqual(HardwareButton.volumeUp.rawValue, "volumeUp")
        XCTAssertEqual(LogLevel.fault.rawValue, "fault")
    }

    func testKeyModifiersDefaults() throws {
        let modifiers = KeyModifiers()
        XCTAssertFalse(modifiers.command)
        XCTAssertFalse(modifiers.shift)
        XCTAssertFalse(modifiers.option)
        XCTAssertFalse(modifiers.control)
        let data = try JSONEncoder().encode(modifiers)
        let decoded = try JSONDecoder().decode(KeyModifiers.self, from: data)
        XCTAssertEqual(decoded, modifiers)
    }

    func testDoctorReportRoundTrip() throws {
        let report = DoctorReport(
            generatedAt: Date(timeIntervalSince1970: 1_797_000_000),
            macOSVersion: "27.0.1",
            architecture: "arm64",
            xcode: XcodeInfo(path: "/Applications/Xcode.app/Contents/Developer", version: "27.1", build: "27A9275", isFullXcode: true),
            frameworks: FrameworkStatus(
                coreSimulatorPath: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework",
                simulatorKitPath: "/Applications/Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework",
                coreSimulatorPresent: true,
                simulatorKitPresent: true
            ),
            privateAPI: PrivateAPIStatus(
                coreSimulatorLoadable: true,
                simulatorKitLoadable: true,
                simDisplayViewClassFound: true,
                simDeviceLegacyHIDClientClassFound: true,
                simAccessibilityManagerClassFound: false,
                notes: ["probe": "class check only"]
            ),
            capabilities: BridgeCapabilities(
                render: .unavailable,
                hid: .unavailable,
                accessibility: .unavailable,
                screenshot: .available,
                video: .available,
                watch: .unavailable,
                tv: .unavailable
            ),
            runtime: .available,
            daemon: DaemonHealth(status: .notInstalled, pid: nil, port: nil, version: nil, tokenPermissionsOK: nil),
            diskFreeBytes: 70_000_000_000,
            deviceCount: 6,
            runtimeCount: 1,
            notes: ["bridge": "simctl"]
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(DoctorReport.self, from: data)
        XCTAssertEqual(decoded.xcode?.version, "27.1")
        XCTAssertEqual(decoded.capabilities.screenshot, .available)
        XCTAssertEqual(decoded.daemon.status, .notInstalled)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter DomainCodingTests
```

Expected: FAIL với `cannot find 'LogEntry' in scope`, `cannot find type 'CrashReport' in scope`.

- [ ] **Step 3: Viết domain types**

Create `Sources/OpenSimCore/Domain/Runtime.swift`:

```swift
import Foundation

public struct Runtime: Codable, Sendable, Identifiable, Equatable {
    public let id: RuntimeID
    public var name: String
    public var platform: Platform
    public var version: String
    public var build: String
    public var isAvailable: Bool
    public var path: String?

    public init(
        id: RuntimeID,
        name: String,
        platform: Platform,
        version: String,
        build: String,
        isAvailable: Bool,
        path: String?
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.version = version
        self.build = build
        self.isAvailable = isAvailable
        self.path = path
    }
}
```

Create `Sources/OpenSimCore/Domain/AppInfo.swift`:

```swift
import Foundation

public enum ContainerKind: String, Codable, Sendable, CaseIterable {
    case app
    case data
    case group
}

public struct AppInfo: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var displayName: String?
    public var version: String?
    public var build: String?
    public var dataContainer: String?
    public var appContainer: String?

    public init(
        id: String,
        displayName: String?,
        version: String?,
        build: String?,
        dataContainer: String?,
        appContainer: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.build = build
        self.dataContainer = dataContainer
        self.appContainer = appContainer
    }
}
```

Create `Sources/OpenSimCore/Domain/Input.swift`:

```swift
import Foundation

public struct Point: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Rect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct Key: Codable, Sendable, Equatable {
    public var name: String
    public var keyCode: UInt16?

    public init(name: String, keyCode: UInt16? = nil) {
        self.name = name
        self.keyCode = keyCode
    }
}

public struct KeyModifiers: Codable, Sendable, Equatable {
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }
}

public enum HardwareButton: String, Codable, Sendable, CaseIterable {
    case home
    case lock
    case side
    case volumeUp
    case volumeDown
    case appleTVSelect
    case appleTVMenu
    case appleTVHome
}

public enum VideoCodec: String, Codable, Sendable, CaseIterable {
    case h264
    case hevc
}
```

Create `Sources/OpenSimCore/Domain/Log.swift`:

```swift
import Foundation

public enum LogLevel: String, Codable, Sendable, CaseIterable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault
}

public struct LogEntry: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var level: LogLevel
    public var subsystem: String?
    public var category: String?
    public var process: String?
    public var message: String

    public init(
        timestamp: Date,
        level: LogLevel,
        subsystem: String?,
        category: String?,
        process: String?,
        message: String
    ) {
        self.timestamp = timestamp
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.process = process
        self.message = message
    }
}

public struct LogPage: Codable, Sendable, Equatable {
    public var entries: [LogEntry]
    public var nextCursor: String?

    public init(entries: [LogEntry], nextCursor: String?) {
        self.entries = entries
        self.nextCursor = nextCursor
    }
}
```

Create `Sources/OpenSimCore/Domain/Screen.swift`:

```swift
import Foundation

public struct ScreenInfo: Codable, Sendable, Identifiable, Equatable {
    public let id: UInt32
    public var width: Int
    public var height: Int
    public var scale: Double
    public var rotation: Double
    public var displayClass: Int

    public init(id: UInt32, width: Int, height: Int, scale: Double, rotation: Double, displayClass: Int) {
        self.id = id
        self.width = width
        self.height = height
        self.scale = scale
        self.rotation = rotation
        self.displayClass = displayClass
    }
}

public enum ScreenshotFormat: String, Codable, Sendable, CaseIterable {
    case png
    case jpeg
}

public struct Screenshot: Codable, Sendable, Equatable {
    public var path: String?
    public var data: Data?
    public var format: ScreenshotFormat
    public var width: Int
    public var height: Int
    public var scale: Double
    public var capturedAt: Date

    public init(
        path: String?,
        data: Data?,
        format: ScreenshotFormat,
        width: Int,
        height: Int,
        scale: Double,
        capturedAt: Date
    ) {
        self.path = path
        self.data = data
        self.format = format
        self.width = width
        self.height = height
        self.scale = scale
        self.capturedAt = capturedAt
    }
}
```

Create `Sources/OpenSimCore/Domain/UI.swift`:

```swift
import Foundation

public struct UIElement: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var role: String
    public var label: String?
    public var identifier: String?
    public var value: String?
    public var frame: Rect
    public var enabled: Bool
    public var selected: Bool
    public var children: [UIElement]

    public init(
        id: String,
        role: String,
        label: String?,
        identifier: String?,
        value: String?,
        frame: Rect,
        enabled: Bool,
        selected: Bool,
        children: [UIElement]
    ) {
        self.id = id
        self.role = role
        self.label = label
        self.identifier = identifier
        self.value = value
        self.frame = frame
        self.enabled = enabled
        self.selected = selected
        self.children = children
    }
}

public struct UITree: Codable, Sendable, Equatable {
    public var root: UIElement
    public var nodeCount: Int
    public var truncated: Bool

    public init(root: UIElement, nodeCount: Int, truncated: Bool) {
        self.root = root
        self.nodeCount = nodeCount
        self.truncated = truncated
    }
}

public struct ElementSelector: Codable, Sendable, Equatable {
    public var role: String?
    public var label: String?
    public var identifier: String?
    public var text: String?

    public init(role: String? = nil, label: String? = nil, identifier: String? = nil, text: String? = nil) {
        self.role = role
        self.label = label
        self.identifier = identifier
        self.text = text
    }
}
```

Create `Sources/OpenSimCore/Domain/Storage.swift`:

```swift
import Foundation

public enum StorageCategory: String, Codable, Sendable, CaseIterable {
    case simulatorDevice
    case simulatorCache
    case simulatorLog
    case runtime
    case derivedData
    case archive
    case appData
}

public struct StorageItem: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var category: StorageCategory
    public var path: String
    public var sizeBytes: Int64
    public var lastUsedAt: Date?
    public var safeToDelete: Bool
    public var reason: String?
    public var children: [StorageItem]

    public init(
        id: String,
        category: StorageCategory,
        path: String,
        sizeBytes: Int64,
        lastUsedAt: Date?,
        safeToDelete: Bool,
        reason: String?,
        children: [StorageItem]
    ) {
        self.id = id
        self.category = category
        self.path = path
        self.sizeBytes = sizeBytes
        self.lastUsedAt = lastUsedAt
        self.safeToDelete = safeToDelete
        self.reason = reason
        self.children = children
    }
}

public struct StorageScan: Codable, Sendable, Equatable {
    public var id: String
    public var createdAt: Date
    public var approximate: Bool
    public var items: [StorageItem]
    public var totalBytes: Int64
    public var reclaimableBytes: Int64

    public init(
        id: String,
        createdAt: Date,
        approximate: Bool,
        items: [StorageItem],
        totalBytes: Int64,
        reclaimableBytes: Int64
    ) {
        self.id = id
        self.createdAt = createdAt
        self.approximate = approximate
        self.items = items
        self.totalBytes = totalBytes
        self.reclaimableBytes = reclaimableBytes
    }
}

public struct CleanPlan: Codable, Sendable, Equatable {
    public var token: String
    public var expiresAt: Date
    public var itemIDs: [String]
    public var reclaimableBytes: Int64

    public init(token: String, expiresAt: Date, itemIDs: [String], reclaimableBytes: Int64) {
        self.token = token
        self.expiresAt = expiresAt
        self.itemIDs = itemIDs
        self.reclaimableBytes = reclaimableBytes
    }
}

```

Create `Sources/OpenSimCore/Domain/Metrics.swift`:

```swift
import Foundation

public struct MetricSample: Codable, Sendable, Equatable {
    public var deviceID: DeviceID
    public var timestamp: Date
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var processCount: Int
    public var diskReadBytes: UInt64
    public var diskWriteBytes: UInt64

    public init(
        deviceID: DeviceID,
        timestamp: Date,
        cpuPercent: Double,
        memoryBytes: UInt64,
        processCount: Int,
        diskReadBytes: UInt64,
        diskWriteBytes: UInt64
    ) {
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.processCount = processCount
        self.diskReadBytes = diskReadBytes
        self.diskWriteBytes = diskWriteBytes
    }
}

public struct ProcessSample: Codable, Sendable, Equatable {
    public var pid: Int32
    public var parentPID: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64

    public init(pid: Int32, parentPID: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}
```

Create `Sources/OpenSimCore/Domain/Session.swift`:

```swift
import Foundation

public enum LeaseMode: String, Codable, Sendable, CaseIterable {
    case control
    case observe
}

public struct Session: Codable, Sendable, Identifiable, Equatable {
    public let id: SessionID
    public var clientKind: String
    public var clientName: String
    public var createdAt: Date
    public var lastSeenAt: Date

    public init(id: SessionID, clientKind: String, clientName: String, createdAt: Date, lastSeenAt: Date) {
        self.id = id
        self.clientKind = clientKind
        self.clientName = clientName
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}

public struct Lease: Codable, Sendable, Identifiable, Equatable {
    public let id: LeaseID
    public var deviceID: DeviceID
    public var sessionID: SessionID
    public var mode: LeaseMode
    public var ownerName: String
    public var acquiredAt: Date
    public var expiresAt: Date

    public init(
        id: LeaseID,
        deviceID: DeviceID,
        sessionID: SessionID,
        mode: LeaseMode,
        ownerName: String,
        acquiredAt: Date,
        expiresAt: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.sessionID = sessionID
        self.mode = mode
        self.ownerName = ownerName
        self.acquiredAt = acquiredAt
        self.expiresAt = expiresAt
    }
}
```

Create `Sources/OpenSimCore/Domain/Audit.swift`:

```swift
import Foundation

public struct AuditEvent: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var timestamp: Date
    public var actor: String
    public var sessionID: SessionID?
    public var leaseID: LeaseID?
    public var action: String
    public var target: String
    public var result: String
    public var durationMs: Int

    public init(
        id: String,
        timestamp: Date,
        actor: String,
        sessionID: SessionID?,
        leaseID: LeaseID?,
        action: String,
        target: String,
        result: String,
        durationMs: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actor = actor
        self.sessionID = sessionID
        self.leaseID = leaseID
        self.action = action
        self.target = target
        self.result = result
        self.durationMs = durationMs
    }
}
```

Create `Sources/OpenSimCore/Domain/CrashReport.swift`:

```swift
import Foundation

public struct CrashReport: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var processName: String
    public var path: String
    public var modifiedAt: Date
    public var sizeBytes: Int64

    public init(id: String, processName: String, path: String, modifiedAt: Date, sizeBytes: Int64) {
        self.id = id
        self.processName = processName
        self.path = path
        self.modifiedAt = modifiedAt
        self.sizeBytes = sizeBytes
    }
}
```

Create `Sources/OpenSimCore/Domain/OperationResults.swift`:

```swift
import Foundation

public struct OperationAck: Codable, Sendable, Equatable {
    public var ok: Bool
    public var message: String?

    public init(ok: Bool, message: String? = nil) {
        self.ok = ok
        self.message = message
    }
}

public struct AppLaunchResult: Codable, Sendable, Equatable {
    public var bundleID: String
    public var pid: Int32

    public init(bundleID: String, pid: Int32) {
        self.bundleID = bundleID
        self.pid = pid
    }
}

public struct ContainerPathResult: Codable, Sendable, Equatable {
    public var bundleID: String
    public var kind: ContainerKind
    public var path: String

    public init(bundleID: String, kind: ContainerKind, path: String) {
        self.bundleID = bundleID
        self.kind = kind
        self.path = path
    }
}
```

Create `Sources/OpenSimCore/Domain/Doctor.swift`:

```swift
import Foundation

public enum Capability: String, Codable, Sendable, CaseIterable {
    case available
    case unavailable
    case unknown
}

public struct BridgeCapabilities: Codable, Sendable, Equatable {
    public var render: Capability
    public var hid: Capability
    public var accessibility: Capability
    public var screenshot: Capability
    public var video: Capability
    public var watch: Capability
    public var tv: Capability

    public init(
        render: Capability,
        hid: Capability,
        accessibility: Capability,
        screenshot: Capability,
        video: Capability,
        watch: Capability,
        tv: Capability
    ) {
        self.render = render
        self.hid = hid
        self.accessibility = accessibility
        self.screenshot = screenshot
        self.video = video
        self.watch = watch
        self.tv = tv
    }
}

public enum DaemonStatus: String, Codable, Sendable, CaseIterable {
    case notInstalled
    case notRunning
    case unhealthy
    case running
}

public struct DaemonHealth: Codable, Sendable, Equatable {
    public var status: DaemonStatus
    public var pid: Int32?
    public var port: Int?
    public var version: String?
    public var tokenPermissionsOK: Bool?

    public init(
        status: DaemonStatus,
        pid: Int32?,
        port: Int?,
        version: String?,
        tokenPermissionsOK: Bool?
    ) {
        self.status = status
        self.pid = pid
        self.port = port
        self.version = version
        self.tokenPermissionsOK = tokenPermissionsOK
    }
}

public struct XcodeInfo: Codable, Sendable, Equatable {
    public var path: String
    public var version: String
    public var build: String
    public var isFullXcode: Bool

    public init(path: String, version: String, build: String, isFullXcode: Bool) {
        self.path = path
        self.version = version
        self.build = build
        self.isFullXcode = isFullXcode
    }
}

public struct FrameworkStatus: Codable, Sendable, Equatable {
    public var coreSimulatorPath: String?
    public var simulatorKitPath: String?
    public var coreSimulatorPresent: Bool
    public var simulatorKitPresent: Bool

    public init(
        coreSimulatorPath: String?,
        simulatorKitPath: String?,
        coreSimulatorPresent: Bool,
        simulatorKitPresent: Bool
    ) {
        self.coreSimulatorPath = coreSimulatorPath
        self.simulatorKitPath = simulatorKitPath
        self.coreSimulatorPresent = coreSimulatorPresent
        self.simulatorKitPresent = simulatorKitPresent
    }
}

public struct PrivateAPIStatus: Codable, Sendable, Equatable {
    public var coreSimulatorLoadable: Bool
    public var simulatorKitLoadable: Bool
    public var simDisplayViewClassFound: Bool
    public var simDeviceLegacyHIDClientClassFound: Bool
    public var simAccessibilityManagerClassFound: Bool
    public var notes: [String: String]

    public init(
        coreSimulatorLoadable: Bool,
        simulatorKitLoadable: Bool,
        simDisplayViewClassFound: Bool,
        simDeviceLegacyHIDClientClassFound: Bool,
        simAccessibilityManagerClassFound: Bool,
        notes: [String: String]
    ) {
        self.coreSimulatorLoadable = coreSimulatorLoadable
        self.simulatorKitLoadable = simulatorKitLoadable
        self.simDisplayViewClassFound = simDisplayViewClassFound
        self.simDeviceLegacyHIDClientClassFound = simDeviceLegacyHIDClientClassFound
        self.simAccessibilityManagerClassFound = simAccessibilityManagerClassFound
        self.notes = notes
    }
}

public struct DoctorReport: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var macOSVersion: String
    public var architecture: String
    public var xcode: XcodeInfo?
    public var frameworks: FrameworkStatus
    public var privateAPI: PrivateAPIStatus
    public var capabilities: BridgeCapabilities
    public var runtime: Capability
    public var daemon: DaemonHealth
    public var diskFreeBytes: Int64
    public var deviceCount: Int
    public var runtimeCount: Int
    public var notes: [String: String]

    public init(
        generatedAt: Date,
        macOSVersion: String,
        architecture: String,
        xcode: XcodeInfo?,
        frameworks: FrameworkStatus,
        privateAPI: PrivateAPIStatus,
        capabilities: BridgeCapabilities,
        runtime: Capability,
        daemon: DaemonHealth,
        diskFreeBytes: Int64,
        deviceCount: Int,
        runtimeCount: Int,
        notes: [String: String]
    ) {
        self.generatedAt = generatedAt
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.xcode = xcode
        self.frameworks = frameworks
        self.privateAPI = privateAPI
        self.capabilities = capabilities
        self.runtime = runtime
        self.daemon = daemon
        self.diskFreeBytes = diskFreeBytes
        self.deviceCount = deviceCount
        self.runtimeCount = runtimeCount
        self.notes = notes
    }
}
```

Create `Sources/OpenSimCore/Support/OpenSimPaths.swift`:

```swift
import Foundation

public struct OpenSimPaths: Sendable {
    public let baseDirectory: URL

    public init(baseDirectory: URL = OpenSimPaths.defaultBaseDirectory) {
        self.baseDirectory = baseDirectory
    }

    public static var defaultBaseDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["OPENSIM_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("OpenSim", isDirectory: true)
    }

    public var daemonStateFile: URL {
        baseDirectory.appendingPathComponent("daemon.json")
    }

    public var lockFile: URL {
        baseDirectory.appendingPathComponent("daemon.lock")
    }

    public var auditFile: URL {
        baseDirectory.appendingPathComponent("audit.jsonl")
    }

    public var logDirectory: URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("OpenSim", isDirectory: true)
        return logs
    }

    public var daemonLogFile: URL {
        logDirectory.appendingPathComponent("daemon.log")
    }

    public func ensureDirectories() throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
```

Create `Sources/OpenSimCore/Support/OpenSimVersion.swift`:

```swift
public enum OpenSimVersion {
    public static let version = "0.1.0"
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter DomainCodingTests
```

Expected: PASS; output có `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCore/Domain Sources/OpenSimCore/Support Tests/OpenSimCoreTests/DomainCodingTests.swift
git commit -m "feat(core): add shared domain types and paths"
```

### Task 3: Error contract, exit code, envelope và JSON coding

**Files:**
- Create: `Sources/OpenSimCore/Domain/CleanResultItem.swift`
- Create: `Sources/OpenSimCore/Errors/ErrorCode.swift`
- Create: `Sources/OpenSimCore/Errors/OpenSimError.swift`
- Create: `Sources/OpenSimCore/Errors/ExitCode.swift`
- Create: `Sources/OpenSimCore/Protocol/Envelope.swift`
- Create: `Sources/OpenSimCore/Protocol/JSONCoding.swift`
- Test: `Tests/OpenSimCoreTests/ErrorTests.swift`
- Test: `Tests/OpenSimCoreTests/EnvelopeTests.swift`

**Interfaces:**
- Consumes: `OpenSimVersion`.
- Produces: `CleanResultItem`; `ErrorCode` (raw string), `OpenSimError`, factory `OpenSimError.invalidArgument`, `.deviceNotFound`, `.confirmationRequired`, `.capabilityUnavailable`, `.simctlFailed`, `.daemonUnavailable`; `OpenSimExitCode.forError(_:)`; `ResponseMeta`; `Envelope<T>`; `EmptyPayload`; `RequestID.make()`; `OpenSimJSON.encoder(pretty:)`, `.decoder()`; `OpenSimDate.string(from:)`, `.date(from:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimCoreTests/ErrorTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class ErrorTests: XCTestCase {
    func testErrorJSONShape() throws {
        let error = OpenSimError(
            code: .leaseConflict,
            message: "Device is controlled by another session",
            details: ["owner": "agent-42"],
            recovery: "Take control or wait for the lease to expire",
            retryable: true
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(error)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["code"] as? String, "lease_conflict")
        XCTAssertEqual(object["retryable"] as? Bool, true)
        XCTAssertEqual((object["details"] as? [String: String])?["owner"], "agent-42")
    }

    func testExitCodeMapping() {
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.invalidArgument.rawValue), .usage)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.deviceNotFound.rawValue), .notFound)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.leaseConflict.rawValue), .conflict)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.leaseRequired.rawValue), .conflict)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.deviceNotBooted.rawValue), .conflict)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.unsupportedXcode.rawValue), .unsupported)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.privateApiUnavailable.rawValue), .unsupported)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.capabilityUnavailable.rawValue), .unsupported)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.permissionDenied.rawValue), .permission)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.xcodeNotFound.rawValue), .permission)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.confirmationRequired.rawValue), .confirmationRequired)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.simctlFailed.rawValue), .internalError)
        XCTAssertEqual(OpenSimExitCode.forError(ErrorCode.internalError.rawValue), .internalError)
    }

    func testCapabilityUnavailableIsStable() {
        let error = OpenSimError.capabilityUnavailable("screen")
        XCTAssertEqual(error.code, "capability_unavailable")
        XCTAssertEqual(error.retryable, false)
        XCTAssertEqual(error.details["capability"], "screen")
    }
}
```

Create `Tests/OpenSimCoreTests/EnvelopeTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class EnvelopeTests: XCTestCase {
    func testSuccessEnvelope() throws {
        let envelope = Envelope<[Device]>.success(
            [],
            requestId: "REQ-1",
            durationMs: 12
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(envelope)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertEqual((object["meta"] as? [String: Any])?["requestId"] as? String, "REQ-1")
        XCTAssertTrue(object["error"] is NSNull)
    }

    func testFailureEnvelopeDecodesError() throws {
        let error = OpenSimError.invalidArgument("bad value")
        let envelope = Envelope<EmptyPayload>.failure(error, requestId: "REQ-2", durationMs: 4)
        let data = try OpenSimJSON.encoder(pretty: false).encode(envelope)
        let decoded = try OpenSimJSON.decoder().decode(Envelope<EmptyPayload>.self, from: data)
        XCTAssertFalse(decoded.ok)
        XCTAssertNil(decoded.data)
        XCTAssertEqual(decoded.error?.code, "invalid_argument")
        XCTAssertEqual(decoded.meta.requestId, "REQ-2")
    }

    func testDateUsesISO8601WithFractionalSeconds() throws {
        let date = Date(timeIntervalSince1970: 1_797_000_000.25)
        let text = OpenSimDate.string(from: date)
        XCTAssertTrue(text.contains("."))
        let parsed = try XCTUnwrap(OpenSimDate.date(from: text))
        XCTAssertEqual(parsed.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter ErrorTests
swift test --filter EnvelopeTests
```

Expected: FAIL với `cannot find type 'OpenSimError' in scope`, `cannot find 'OpenSimJSON' in scope`.

- [ ] **Step 3: Viết error, envelope và JSON coding**

Create `Sources/OpenSimCore/Errors/ErrorCode.swift`:

```swift
public enum ErrorCode: String, Codable, Sendable, CaseIterable {
    case xcodeNotFound = "xcode_not_found"
    case unsupportedXcode = "unsupported_xcode"
    case privateApiUnavailable = "private_api_unavailable"
    case a11yUnavailable = "a11y_unavailable"
    case capabilityUnavailable = "capability_unavailable"
    case deviceNotFound = "device_not_found"
    case deviceNotBooted = "device_not_booted"
    case deviceBusy = "device_busy"
    case leaseRequired = "lease_required"
    case leaseConflict = "lease_conflict"
    case leaseRevoked = "lease_revoked"
    case simctlFailed = "simctl_failed"
    case inputFailed = "input_failed"
    case storageScanFailed = "storage_scan_failed"
    case storageInUse = "storage_in_use"
    case confirmationRequired = "confirmation_required"
    case invalidArgument = "invalid_argument"
    case permissionDenied = "permission_denied"
    case daemonUnavailable = "daemon_unavailable"
    case internalError = "internal"
}
```

Create `Sources/OpenSimCore/Domain/CleanResultItem.swift`:

```swift
import Foundation

public struct CleanResultItem: Codable, Sendable, Equatable {
    public var itemID: String
    public var success: Bool
    public var error: OpenSimError?

    public init(itemID: String, success: Bool, error: OpenSimError?) {
        self.itemID = itemID
        self.success = success
        self.error = error
    }
}
```

Create `Sources/OpenSimCore/Errors/OpenSimError.swift`:

```swift
import Foundation

public struct OpenSimError: Error, Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    public var details: [String: String]
    public var recovery: String?
    public var retryable: Bool

    public init(
        code: String,
        message: String,
        details: [String: String] = [:],
        recovery: String? = nil,
        retryable: Bool = false
    ) {
        self.code = code
        self.message = message
        self.details = details
        self.recovery = recovery
        self.retryable = retryable
    }

    public init(
        code: ErrorCode,
        message: String,
        details: [String: String] = [:],
        recovery: String? = nil,
        retryable: Bool = false
    ) {
        self.init(
            code: code.rawValue,
            message: message,
            details: details,
            recovery: recovery,
            retryable: retryable
        )
    }

    public static func invalidArgument(_ message: String, recovery: String? = nil) -> OpenSimError {
        OpenSimError(
            code: .invalidArgument,
            message: message,
            recovery: recovery,
            retryable: false
        )
    }

    public static func deviceNotFound(_ id: DeviceID) -> OpenSimError {
        OpenSimError(
            code: .deviceNotFound,
            message: "Device \(id.rawValue) was not found",
            details: ["udid": id.rawValue],
            recovery: "Run `opensim device list` to see available devices",
            retryable: false
        )
    }

    public static func confirmationRequired(action: String) -> OpenSimError {
        OpenSimError(
            code: .confirmationRequired,
            message: "Operation \(action) requires confirmation",
            details: ["action": action],
            recovery: "Re-run the command with --yes",
            retryable: false
        )
    }

    public static func capabilityUnavailable(_ capability: String) -> OpenSimError {
        OpenSimError(
            code: .capabilityUnavailable,
            message: "Capability \(capability) is not available in this build",
            details: ["capability": capability],
            recovery: "Run `opensim doctor` and install the plan that provides this service",
            retryable: false
        )
    }

    public static func simctlFailed(_ output: SimctlFailureParts) -> OpenSimError {
        OpenSimError(
            code: .simctlFailed,
            message: output.message,
            details: output.details,
            recovery: "Run `xcrun simctl help` and check the device state",
            retryable: false
        )
    }

    public static func daemonUnavailable(_ message: String) -> OpenSimError {
        OpenSimError(
            code: .daemonUnavailable,
            message: message,
            recovery: "Run `opensim daemon start` and check `opensim daemon status`",
            retryable: true
        )
    }
}

public struct SimctlFailureParts: Sendable, Equatable {
    public var message: String
    public var details: [String: String]

    public init(message: String, details: [String: String]) {
        self.message = message
        self.details = details
    }
}
```

Create `Sources/OpenSimCore/Errors/ExitCode.swift`:

```swift
public enum OpenSimExitCode: Int32, Sendable, CaseIterable {
    case success = 0
    case usage = 2
    case notFound = 3
    case conflict = 4
    case unsupported = 5
    case permission = 6
    case confirmationRequired = 7
    case internalError = 10

    public static func forError(_ code: String) -> OpenSimExitCode {
        switch code {
        case ErrorCode.invalidArgument.rawValue:
            return .usage
        case ErrorCode.deviceNotFound.rawValue:
            return .notFound
        case ErrorCode.deviceNotBooted.rawValue,
             ErrorCode.deviceBusy.rawValue,
             ErrorCode.leaseRequired.rawValue,
             ErrorCode.leaseConflict.rawValue,
             ErrorCode.leaseRevoked.rawValue,
             ErrorCode.storageInUse.rawValue:
            return .conflict
        case ErrorCode.unsupportedXcode.rawValue,
             ErrorCode.privateApiUnavailable.rawValue,
             ErrorCode.a11yUnavailable.rawValue,
             ErrorCode.capabilityUnavailable.rawValue:
            return .unsupported
        case ErrorCode.xcodeNotFound.rawValue,
             ErrorCode.permissionDenied.rawValue:
            return .permission
        case ErrorCode.confirmationRequired.rawValue:
            return .confirmationRequired
        default:
            return .internalError
        }
    }
}
```

Create `Sources/OpenSimCore/Protocol/Envelope.swift`:

```swift
import Foundation

public struct ResponseMeta: Codable, Sendable, Equatable {
    public var requestId: String
    public var durationMs: Int

    public init(requestId: String, durationMs: Int) {
        self.requestId = requestId
        self.durationMs = durationMs
    }
}

public struct EmptyPayload: Codable, Sendable, Equatable {
    public init() {}
}

public struct Envelope<T: Codable & Sendable>: Codable, Sendable {
    public var schemaVersion: Int
    public var ok: Bool
    public var data: T?
    public var error: OpenSimError?
    public var meta: ResponseMeta

    public init(
        schemaVersion: Int = 1,
        ok: Bool,
        data: T?,
        error: OpenSimError?,
        meta: ResponseMeta
    ) {
        self.schemaVersion = schemaVersion
        self.ok = ok
        self.data = data
        self.error = error
        self.meta = meta
    }

    public static func success(_ data: T, requestId: String, durationMs: Int) -> Envelope<T> {
        Envelope(
            ok: true,
            data: data,
            error: nil,
            meta: ResponseMeta(requestId: requestId, durationMs: durationMs)
        )
    }

    public static func failure(_ error: OpenSimError, requestId: String, durationMs: Int) -> Envelope<T> {
        Envelope(
            ok: false,
            data: nil,
            error: error,
            meta: ResponseMeta(requestId: requestId, durationMs: durationMs)
        )
    }
}

public enum RequestID {
    public static func make() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
    }
}
```

Create `Sources/OpenSimCore/Protocol/JSONCoding.swift`:

```swift
import Foundation

public enum OpenSimDate {
    public static func string(from date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    public static func date(from string: String) -> Date? {
        if let parsed = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
            return parsed
        }
        return try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(string)
    }
}

public enum OpenSimJSON {
    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty {
            formatting.insert(.prettyPrinted)
        }
        encoder.outputFormatting = formatting
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(OpenSimDate.string(from: date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = OpenSimDate.date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO8601 date: \(text)"
                )
            }
            return date
        }
        return decoder
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter ErrorTests
swift test --filter EnvelopeTests
```

Expected: PASS; mỗi filter có `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCore/Domain/CleanResultItem.swift Sources/OpenSimCore/Errors Sources/OpenSimCore/Protocol/Envelope.swift Sources/OpenSimCore/Protocol/JSONCoding.swift Tests/OpenSimCoreTests/ErrorTests.swift Tests/OpenSimCoreTests/EnvelopeTests.swift
git commit -m "feat(core): add error contract, envelope and json coding"
```

---

### Task 4: Service protocols và SimulatorBridge aggregate

**Files:**
- Create: `Sources/OpenSimCore/Protocol/ServiceProtocols.swift`
- Create: `Sources/OpenSimCore/Protocol/SimulatorBridge.swift`
- Test: `Tests/OpenSimCoreTests/BridgeProtocolTests.swift`

**Interfaces:**
- Consumes: toàn bộ domain types của Task 2, bao gồm `BridgeCapabilities`.
- Produces: `DeviceControlling`, `RuntimeControlling`, `AppControlling`, `LogControlling`, `ScreenControlling`, `InputControlling`, `AccessibilityReading`, `StorageManaging`, `MetricsReading`, `DoctorReporting`, `CrashReportReading`; `BridgeService`; `SimulatorBridge`; `SimulatorBridge.supports(_:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimCoreTests/BridgeProtocolTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class BridgeProtocolTests: XCTestCase {
    func testCapabilitiesRoundTrip() throws {
        let capabilities = BridgeCapabilities(
            render: .unknown,
            hid: .unknown,
            accessibility: .unknown,
            screenshot: .available,
            video: .available,
            watch: .unavailable,
            tv: .unavailable
        )
        let data = try OpenSimJSON.encoder(pretty: false).encode(capabilities)
        let decoded = try OpenSimJSON.decoder().decode(BridgeCapabilities.self, from: data)
        XCTAssertEqual(decoded, capabilities)
    }

    func testBridgeServiceCasesAreStable() {
        XCTAssertEqual(BridgeService.screen.rawValue, "screen")
        XCTAssertEqual(BridgeService.input.rawValue, "input")
        XCTAssertEqual(BridgeService.accessibility.rawValue, "accessibility")
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter BridgeProtocolTests
```

Expected: FAIL với `cannot find 'BridgeService' in scope`.

- [ ] **Step 3: Viết protocols**

Create `Sources/OpenSimCore/Protocol/ServiceProtocols.swift`:

```swift
import Foundation

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

public protocol DoctorReporting: Sendable {
    func doctorReport() async throws -> DoctorReport
}

public protocol CrashReportReading: Sendable {
    func crashReports(on device: DeviceID, limit: Int) async throws -> [CrashReport]
}
```

Create `Sources/OpenSimCore/Protocol/SimulatorBridge.swift`:

```swift
import Foundation

public enum BridgeService: String, Codable, Sendable, CaseIterable {
    case screen
    case input
    case accessibility
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

public extension SimulatorBridge {
    func supports(_ service: BridgeService) -> Bool {
        switch service {
        case .screen:
            return screen != nil
        case .input:
            return input != nil
        case .accessibility:
            return accessibility != nil
        }
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter BridgeProtocolTests
```

Expected: PASS; `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCore/Protocol/ServiceProtocols.swift Sources/OpenSimCore/Protocol/SimulatorBridge.swift Tests/OpenSimCoreTests/BridgeProtocolTests.swift
git commit -m "feat(core): add service protocols and bridge aggregate"
```

---

### Task 5: Operation catalog và Plan 1 operations

**Files:**
- Create: `Sources/OpenSimCore/Catalog/Operation.swift`
- Create: `Sources/OpenSimCore/Catalog/OperationCatalog.swift`
- Create: `Sources/OpenSimCore/Catalog/Plan1Operations.swift`
- Test: `Tests/OpenSimCoreTests/CatalogTests.swift`

**Interfaces:**
- Consumes: `BridgeService`.
- Produces: `Operation`, `OperationParameter`, `OperationCatalog`, `OperationCatalog.plan1()`, `OperationCatalog.register(_:)`, `.operation(forCLI:)`, `.operation(forMCP:)`, `.mcpOperations()`, `.validate()`, `.operations`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimCoreTests/CatalogTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class CatalogTests: XCTestCase {
    func testPlan1LookupByCLIAndMCP() throws {
        let catalog = OperationCatalog.plan1()
        XCTAssertEqual(try XCTUnwrap(catalog.operation(forCLI: ["device", "list"])).mcpName, "device_list")
        XCTAssertEqual(try XCTUnwrap(catalog.operation(forCLI: ["doctor"])).mcpName, "doctor_report")
        XCTAssertEqual(try XCTUnwrap(catalog.operation(forMCP: "app_launch")).cliPath, ["app", "launch"])
    }

    func testMCPExposureMatchesSpecSubset() {
        let catalog = OperationCatalog.plan1()
        XCTAssertEqual(catalog.mcpOperations().count, 22)
        let names = Set(catalog.mcpOperations().map(\.mcpName))
        XCTAssertTrue(names.contains("device_list"))
        XCTAssertTrue(names.contains("log_tail"))
        XCTAssertTrue(names.contains("doctor_report"))
        XCTAssertFalse(names.contains("runtime_verify"))
        XCTAssertFalse(names.contains("log_crash"))
    }

    func testCatalogHasNoDuplicateCLIPathOrMCPName() {
        let catalog = OperationCatalog.plan1()
        XCTAssertEqual(catalog.validate(), [])
    }

    func testLeaseAndDestructiveMetadata() throws {
        let catalog = OperationCatalog.plan1()
        for operation in catalog.operations.values {
            if operation.requiresControlLease {
                XCTAssertFalse(operation.readOnly)
            }
            if operation.destructive {
                XCTAssertTrue(operation.parameters.contains { $0.name == "confirm" && $0.required })
            }
        }
        let erase = try XCTUnwrap(catalog.operation(forMCP: "device_erase"))
        XCTAssertTrue(erase.destructive)
        XCTAssertTrue(erase.requiresControlLease)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter CatalogTests
```

Expected: FAIL với `cannot find type 'OperationCatalog' in scope`.

- [ ] **Step 3: Viết catalog**

Create `Sources/OpenSimCore/Catalog/Operation.swift`:

```swift
import Foundation

public struct OperationParameter: Sendable, Equatable {
    public var name: String
    public var type: String
    public var required: Bool
    public var defaultValue: String?

    public init(name: String, type: String, required: Bool, defaultValue: String? = nil) {
        self.name = name
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
    }
}

public struct Operation: Sendable, Equatable {
    public var cliPath: [String]
    public var mcpName: String
    public var summary: String
    public var requiresControlLease: Bool
    public var destructive: Bool
    public var readOnly: Bool
    public var parameters: [OperationParameter]
    public var mcpExposed: Bool
    public var requiredService: BridgeService?

    public init(
        cliPath: [String],
        mcpName: String,
        summary: String,
        requiresControlLease: Bool,
        destructive: Bool,
        readOnly: Bool,
        parameters: [OperationParameter],
        mcpExposed: Bool = true,
        requiredService: BridgeService? = nil
    ) {
        self.cliPath = cliPath
        self.mcpName = mcpName
        self.summary = summary
        self.requiresControlLease = requiresControlLease
        self.destructive = destructive
        self.readOnly = readOnly
        self.parameters = parameters
        self.mcpExposed = mcpExposed
        self.requiredService = requiredService
    }
}
```

Create `Sources/OpenSimCore/Catalog/OperationCatalog.swift`:

```swift
import Foundation

public struct OperationCatalog: Sendable {
    public private(set) var operations: [String: Operation]
    private var byCLIPath: [String: Operation]

    public init(operations: [Operation] = []) {
        self.operations = [:]
        self.byCLIPath = [:]
        for operation in operations {
            register(operation)
        }
    }

    public mutating func register(_ operation: Operation) {
        operations[operation.mcpName] = operation
        byCLIPath[OperationCatalog.cliKey(operation.cliPath)] = operation
    }

    public func operation(forCLI path: [String]) -> Operation? {
        byCLIPath[OperationCatalog.cliKey(path)]
    }

    public func operation(forMCP name: String) -> Operation? {
        operations[name]
    }

    public func mcpOperations() -> [Operation] {
        operations.values
            .filter(\.mcpExposed)
            .sorted { $0.mcpName < $1.mcpName }
    }

    public func cliOperations() -> [Operation] {
        operations.values.sorted { $0.cliPath.joined(separator: " ") < $1.cliPath.joined(separator: " ") }
    }

    public func validate() -> [String] {
        var issues: [String] = []
        var cliKeys: Set<String> = []
        var mcpNames: Set<String> = []
        for operation in operations.values {
            let cliKey = OperationCatalog.cliKey(operation.cliPath)
            if !cliKeys.insert(cliKey).inserted {
                issues.append("duplicate cli path: \(cliKey)")
            }
            if !mcpNames.insert(operation.mcpName).inserted {
                issues.append("duplicate mcp name: \(operation.mcpName)")
            }
            if operation.cliPath.isEmpty {
                issues.append("empty cli path: \(operation.mcpName)")
            }
            if operation.mcpName.isEmpty {
                issues.append("empty mcp name: \(cliKey)")
            }
            if operation.readOnly && operation.requiresControlLease {
                issues.append("read-only operation requires lease: \(operation.mcpName)")
            }
            if operation.destructive {
                let hasConfirm = operation.parameters.contains { $0.name == "confirm" && $0.required }
                if !hasConfirm {
                    issues.append("destructive operation lacks confirm: \(operation.mcpName)")
                }
            }
        }
        return issues.sorted()
    }

    private static func cliKey(_ path: [String]) -> String {
        path.joined(separator: "/")
    }
}
```

Create `Sources/OpenSimCore/Catalog/Plan1Operations.swift`:

```swift
import Foundation

public extension OperationCatalog {
    static func plan1() -> OperationCatalog {
        OperationCatalog(operations: Plan1Operations.all)
    }
}

public enum Plan1Operations {
    private static func parameter(
        _ name: String,
        _ type: String,
        required: Bool = true,
        default defaultValue: String? = nil
    ) -> OperationParameter {
        OperationParameter(name: name, type: type, required: required, defaultValue: defaultValue)
    }

    private static let device = parameter("device", "string", required: false)
    private static let bundleID = parameter("bundleID", "string")
    private static let path = parameter("path", "string")
    private static let identifier = parameter("identifier", "string")
    private static let confirm = parameter("confirm", "boolean")
    private static let wait = parameter("wait", "boolean", required: false, default: "false")
    private static let limit = parameter("limit", "integer", required: false, default: "100")

    public static let all: [Operation] = [
        Operation(
            cliPath: ["device", "list"],
            mcpName: "device_list",
            summary: "List simulator devices",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [
                parameter("platform", "string", required: false),
                parameter("state", "string", required: false),
            ]
        ),
        Operation(
            cliPath: ["device", "get"],
            mcpName: "device_get",
            summary: "Get one simulator device",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [device]
        ),
        Operation(
            cliPath: ["device", "create"],
            mcpName: "device_create",
            summary: "Create a simulator device",
            requiresControlLease: false,
            destructive: false,
            readOnly: false,
            parameters: [
                parameter("name", "string"),
                parameter("deviceType", "string"),
                parameter("runtime", "string", required: false),
            ]
        ),
        Operation(
            cliPath: ["device", "clone"],
            mcpName: "device_clone",
            summary: "Clone a simulator device",
            requiresControlLease: false,
            destructive: false,
            readOnly: false,
            parameters: [device, parameter("name", "string")]
        ),
        Operation(
            cliPath: ["device", "boot"],
            mcpName: "device_boot",
            summary: "Boot a simulator device",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [device, wait]
        ),
        Operation(
            cliPath: ["device", "shutdown"],
            mcpName: "device_shutdown",
            summary: "Shut down a simulator device",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [device, wait]
        ),
        Operation(
            cliPath: ["device", "erase"],
            mcpName: "device_erase",
            summary: "Erase all content from a simulator device",
            requiresControlLease: true,
            destructive: true,
            readOnly: false,
            parameters: [device, confirm]
        ),
        Operation(
            cliPath: ["device", "delete"],
            mcpName: "device_delete",
            summary: "Delete a simulator device",
            requiresControlLease: true,
            destructive: true,
            readOnly: false,
            parameters: [device, confirm]
        ),
        Operation(
            cliPath: ["device", "rename"],
            mcpName: "device_rename",
            summary: "Rename a simulator device",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [device, parameter("name", "string")]
        ),
        Operation(
            cliPath: ["device", "status"],
            mcpName: "device_status",
            summary: "Read simulator device state",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [device]
        ),
        Operation(
            cliPath: ["runtime", "list"],
            mcpName: "runtime_list",
            summary: "List installed simulator runtimes",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [parameter("platform", "string", required: false)]
        ),
        Operation(
            cliPath: ["runtime", "install"],
            mcpName: "runtime_install",
            summary: "Install a simulator runtime from a disk image",
            requiresControlLease: false,
            destructive: false,
            readOnly: false,
            parameters: [path]
        ),
        Operation(
            cliPath: ["runtime", "delete"],
            mcpName: "runtime_delete",
            summary: "Delete an installed simulator runtime",
            requiresControlLease: false,
            destructive: true,
            readOnly: false,
            parameters: [identifier, confirm]
        ),
        Operation(
            cliPath: ["runtime", "verify"],
            mcpName: "runtime_verify",
            summary: "Verify the signature of an installed runtime",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [identifier],
            mcpExposed: false
        ),
        Operation(
            cliPath: ["app", "list"],
            mcpName: "app_list",
            summary: "List applications installed on a device",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [device, parameter("filter", "string", required: false)]
        ),
        Operation(
            cliPath: ["app", "install"],
            mcpName: "app_install",
            summary: "Install an application bundle on a device",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [device, path]
        ),
        Operation(
            cliPath: ["app", "uninstall"],
            mcpName: "app_uninstall",
            summary: "Uninstall an application from a device",
            requiresControlLease: true,
            destructive: true,
            readOnly: false,
            parameters: [device, bundleID, confirm]
        ),
        Operation(
            cliPath: ["app", "launch"],
            mcpName: "app_launch",
            summary: "Launch an application on a device",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [
                device,
                bundleID,
                parameter("args", "array", required: false),
                parameter("env", "object", required: false),
            ]
        ),
        Operation(
            cliPath: ["app", "terminate"],
            mcpName: "app_terminate",
            summary: "Terminate an application on a device",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [device, bundleID]
        ),
        Operation(
            cliPath: ["app", "info"],
            mcpName: "app_info",
            summary: "Read application metadata",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [device, bundleID]
        ),
        Operation(
            cliPath: ["app", "container"],
            mcpName: "app_container",
            summary: "Resolve an application container path",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [device, bundleID, parameter("kind", "string", required: false, default: "app")]
        ),
        Operation(
            cliPath: ["log", "tail"],
            mcpName: "log_tail",
            summary: "Read a page of unified log entries from a device",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [
                device,
                parameter("cursor", "string", required: false),
                limit,
                parameter("filter", "string", required: false),
            ]
        ),
        Operation(
            cliPath: ["log", "crash"],
            mcpName: "log_crash",
            summary: "List crash reports for a device",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: [device, parameter("limit", "integer", required: false, default: "20")],
            mcpExposed: false
        ),
        Operation(
            cliPath: ["doctor"],
            mcpName: "doctor_report",
            summary: "Report environment and capability status",
            requiresControlLease: false,
            destructive: false,
            readOnly: true,
            parameters: []
        ),
    ]
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter CatalogTests
```

Expected: PASS; `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCore/Catalog Tests/OpenSimCoreTests/CatalogTests.swift
git commit -m "feat(core): add operation catalog and plan 1 operations"
```

---

### Task 6: Validation UDID, bundle ID, path và device resolver

**Files:**
- Create: `Sources/OpenSimCore/Validation/IdentifierValidation.swift`
- Create: `Sources/OpenSimCore/Validation/PathPolicy.swift`
- Create: `Sources/OpenSimCore/Validation/DeviceResolver.swift`
- Test: `Tests/OpenSimCoreTests/ValidationTests.swift`

**Interfaces:**
- Consumes: `Device`, `DeviceID`, `OpenSimError`.
- Produces: `IdentifierValidation.isUDID`, `.validateBundleID`, `.validateName`, `.validateRuntimeIdentifier`; `PathPolicy.validateDeveloperDir`, `.validateAppBundle`, `.validateRuntimeImage`, `.validateExistingFile`, `.isContained`; `DeviceResolver.resolve(query:in:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimCoreTests/ValidationTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class ValidationTests: XCTestCase {
    func testUDIDValidation() {
        XCTAssertTrue(IdentifierValidation.isUDID("95B3747B-7065-447E-AB1E-53065142C3FC"))
        XCTAssertFalse(IdentifierValidation.isUDID("95B3747B7065447EAB1E53065142C3FC"))
        XCTAssertFalse(IdentifierValidation.isUDID("booted"))
        XCTAssertFalse(IdentifierValidation.isUDID("95B3747B-7065-447E-AB1E-53065142C3F"))
    }

    func testBundleIDValidation() throws {
        XCTAssertNoThrow(try IdentifierValidation.validateBundleID("com.apple.Preferences"))
        XCTAssertNoThrow(try IdentifierValidation.validateBundleID("dev.opensim.OpenSimFixture"))
        XCTAssertThrowsError(try IdentifierValidation.validateBundleID("Preferences"))
        XCTAssertThrowsError(try IdentifierValidation.validateBundleID("com..apple"))
        XCTAssertThrowsError(try IdentifierValidation.validateBundleID("com.apple Preferences"))
    }

    func testDeveloperDirAllowlist() throws {
        XCTAssertNoThrow(try PathPolicy.validateDeveloperDir("/Applications/Xcode.app/Contents/Developer"))
        XCTAssertNoThrow(try PathPolicy.validateDeveloperDir("/Library/Developer/CommandLineTools"))
        XCTAssertThrowsError(try PathPolicy.validateDeveloperDir("/tmp/Xcode.app/Contents/Developer"))
        XCTAssertThrowsError(try PathPolicy.validateDeveloperDir("/Applications/Other.app/Contents/Developer"))
    }

    func testAppBundleNeedsExistingAppDirectory() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-validation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Sample.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertNoThrow(try PathPolicy.validateAppBundle(app.path))
        let file = root.appendingPathComponent("Sample.txt")
        try Data("x".utf8).write(to: file)
        XCTAssertThrowsError(try PathPolicy.validateAppBundle(file.path))
        XCTAssertThrowsError(try PathPolicy.validateAppBundle("/tmp/does-not-exist.app"))
    }

    func testPathTraversalIsRejected() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-traversal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Escape.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundle)
        XCTAssertThrowsError(try PathPolicy.validateAppBundle(link.path + "/../../../etc"))
    }

    func testDeviceResolverByUDIDAndName() throws {
        let booted = Device(
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
        XCTAssertEqual(try DeviceResolver.resolve(query: nil, in: [booted]).id, booted.id)
        XCTAssertEqual(try DeviceResolver.resolve(query: "iPhone Air", in: [booted]).id, booted.id)
        XCTAssertEqual(try DeviceResolver.resolve(query: booted.id.rawValue.lowercased(), in: [booted]).id, booted.id)
        XCTAssertThrowsError(try DeviceResolver.resolve(query: "Missing", in: [booted]))
    }

    func testDeviceResolverRejectsAmbiguousName() {
        let first = Device(
            id: DeviceID("11111111-1111-1111-1111-111111111111"),
            name: "Same",
            platform: .iOS,
            deviceType: "iPhone-Air",
            runtime: RuntimeID("iOS-27-0"),
            state: .shutdown,
            isAvailable: true,
            dataPath: nil,
            lastBootedAt: nil
        )
        let second = Device(
            id: DeviceID("22222222-2222-2222-2222-222222222222"),
            name: "Same",
            platform: .iOS,
            deviceType: "iPhone-Air",
            runtime: RuntimeID("iOS-27-0"),
            state: .shutdown,
            isAvailable: true,
            dataPath: nil,
            lastBootedAt: nil
        )
        XCTAssertThrowsError(try DeviceResolver.resolve(query: "Same", in: [first, second]))
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter ValidationTests
```

Expected: FAIL với `cannot find type 'IdentifierValidation' in scope`.

- [ ] **Step 3: Viết validation**

Create `Sources/OpenSimCore/Validation/IdentifierValidation.swift`:

```swift
import Foundation

public enum IdentifierValidation {
    public static func isUDID(_ value: String) -> Bool {
        let pattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    public static func validateUDID(_ value: String) throws -> DeviceID {
        guard isUDID(value) else {
            throw OpenSimError.invalidArgument(
                "Invalid device UDID: \(value)",
                recovery: "Use a UDID returned by `opensim device list`"
            )
        }
        return DeviceID(value)
    }

    public static func validateBundleID(_ value: String) throws {
        let pattern = "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$"
        guard value.count <= 255, value.range(of: pattern, options: .regularExpression) != nil else {
            throw OpenSimError.invalidArgument(
                "Invalid bundle identifier: \(value)",
                recovery: "Use a reverse-DNS bundle identifier such as com.example.app"
            )
        }
    }

    public static func validateName(_ value: String, field: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else {
            throw OpenSimError.invalidArgument(
                "\(field) must contain 1 to 128 characters",
                recovery: "Pass a non-empty \(field)"
            )
        }
        guard trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw OpenSimError.invalidArgument("\(field) contains control characters")
        }
    }

    public static func validateRuntimeIdentifier(_ value: String) throws -> RuntimeID {
        let pattern = "^[A-Za-z0-9._-]+$"
        guard value.count <= 255, value.range(of: pattern, options: .regularExpression) != nil else {
            throw OpenSimError.invalidArgument(
                "Invalid runtime identifier: \(value)",
                recovery: "Use an identifier returned by `opensim runtime list`"
            )
        }
        return RuntimeID(value)
    }
}
```

Create `Sources/OpenSimCore/Validation/PathPolicy.swift`:

```swift
import Foundation

public enum PathPolicy {
    public static let developerRoots: [String] = ["/Applications", "/Library/Developer"]

    public static var clientRoots: [String] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .resolvingSymlinksInPath()
            .path
        return [home, "/tmp", "/private/tmp", "/Applications", "/Library/Developer"]
    }

    public static func validateDeveloperDir(_ path: String) throws -> String {
        let url = try standardized(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw OpenSimError.invalidArgument("Developer directory does not exist: \(path)")
        }
        guard url.lastPathComponent == "Developer" || url.lastPathComponent == "CommandLineTools" else {
            throw OpenSimError.invalidArgument(
                "Developer directory must end with Developer or CommandLineTools: \(url.path)",
                recovery: "Run `xcode-select -p` and pass that path"
            )
        }
        guard isContained(url.path, in: developerRoots) else {
            throw OpenSimError(
                code: .permissionDenied,
                message: "Developer directory is outside the allowed roots: \(url.path)",
                details: ["allowed": developerRoots.joined(separator: ",")],
                recovery: "Use an Xcode installation under /Applications or /Library/Developer"
            )
        }
        return url.path
    }

    public static func validateAppBundle(_ path: String) throws -> String {
        try validateExistingFile(path, allowedExtensions: ["app"], requireDirectory: true)
    }

    public static func validateRuntimeImage(_ path: String) throws -> String {
        try validateExistingFile(path, allowedExtensions: ["dmg", "simruntime"], requireDirectory: false)
    }

    public static func validateExistingFile(
        _ path: String,
        allowedExtensions: [String],
        requireDirectory: Bool
    ) throws -> String {
        guard path.hasPrefix("/") else {
            throw OpenSimError.invalidArgument("Path must be absolute: \(path)")
        }
        let url = try standardized(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OpenSimError.invalidArgument("Path does not exist: \(url.path)")
        }
        guard isContained(url.path, in: clientRoots) else {
            throw OpenSimError(
                code: .permissionDenied,
                message: "Path is outside the allowed roots: \(url.path)",
                details: ["allowed": clientRoots.joined(separator: ",")],
                recovery: "Move the file under your home directory, /tmp, or /Applications"
            )
        }
        let extensionName = url.pathExtension.lowercased()
        guard allowedExtensions.map({ $0.lowercased() }).contains(extensionName) else {
            throw OpenSimError.invalidArgument(
                "Unsupported path extension: \(extensionName)",
                details: ["allowed": allowedExtensions.joined(separator: ",")]
            )
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else {
            throw OpenSimError.invalidArgument("Path does not exist: \(url.path)")
        }
        if requireDirectory && !isDirectory.boolValue {
            throw OpenSimError.invalidArgument("Path must be a directory: \(url.path)")
        }
        if !requireDirectory && isDirectory.boolValue && extensionName != "simruntime" {
            throw OpenSimError.invalidArgument("Path must be a file: \(url.path)")
        }
        return url.path
    }

    public static func isContained(_ path: String, in roots: [String]) -> Bool {
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.path
        return roots.contains { root in
            let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
            return candidate == normalizedRoot || candidate.hasPrefix(normalizedRoot + "/")
        }
    }

    private static func standardized(_ path: String) throws -> URL {
        guard path.hasPrefix("/") else {
            throw OpenSimError.invalidArgument("Path must be absolute: \(path)")
        }
        if path.contains("\0") {
            throw OpenSimError.invalidArgument("Path contains a null byte")
        }
        return URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }
}
```

Create `Sources/OpenSimCore/Validation/DeviceResolver.swift`:

```swift
import Foundation

public enum DeviceResolver {
    public static func resolve(query: String?, in devices: [Device]) throws -> Device {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            let booted = devices.filter { $0.state == .booted }
            if booted.count == 1 {
                return booted[0]
            }
            if booted.isEmpty {
                throw OpenSimError(
                    code: .deviceNotFound,
                    message: "No booted device found",
                    recovery: "Boot a device or pass --device <udid|name>"
                )
            }
            throw OpenSimError.invalidArgument(
                "More than one booted device; pass --device",
                details: ["devices": booted.map(\.id.rawValue).joined(separator: ",")]
            )
        }

        if trimmed.lowercased().range(of: "^[0-9a-f-]{36}$", options: .regularExpression) != nil {
            if let match = devices.first(where: { $0.id.rawValue.lowercased() == trimmed.lowercased() }) {
                return match
            }
            throw OpenSimError.deviceNotFound(DeviceID(trimmed))
        }

        let matches = devices.filter { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        if matches.count == 1 {
            return matches[0]
        }
        if matches.isEmpty {
            throw OpenSimError(
                code: .deviceNotFound,
                message: "No device named \(trimmed)",
                recovery: "Run `opensim device list` to see device names"
            )
        }
        throw OpenSimError.invalidArgument(
            "Device name is ambiguous: \(trimmed)",
            details: ["devices": matches.map(\.id.rawValue).joined(separator: ",")],
            recovery: "Pass --device with a UDID"
        )
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter ValidationTests
```

Expected: PASS; `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCore/Validation Tests/OpenSimCoreTests/ValidationTests.swift
git commit -m "feat(core): add identifier and path validation"
```

### Task 7: Simctl argument builder, executor và error mapping

**Files:**
- Modify: `Package.swift` (thêm target `OpenSimBridge` và `OpenSimBridgeTests`)
- Create: `Sources/OpenSimBridge/Simctl/SimctlCommand.swift`
- Create: `Sources/OpenSimBridge/Simctl/SimctlExecutor.swift`
- Create: `Sources/OpenSimBridge/Simctl/SimctlErrorMapper.swift`
- Test: `Tests/OpenSimBridgeTests/SimctlCommandTests.swift`

**Interfaces:**
- Consumes: `DeviceID`, `RuntimeID`, `ContainerKind`, `OpenSimError`.
- Produces: `SimctlCommand` (Equatable, `arguments`, `environment`, `displayString`); `SimctlArguments` builder; `SimctlOutput`; `SimctlExecuting.run(_:timeout:)`; `ProcessSimctlExecutor`; `SimctlErrorMapper.requireSuccess(command:output:)`; `SimctlFailureParts`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeTests/SimctlCommandTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class SimctlCommandTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    func testListCommands() {
        XCTAssertEqual(SimctlArguments.listDevicesJSON().arguments, ["list", "devices", "-j"])
        XCTAssertEqual(SimctlArguments.listRuntimesJSON().arguments, ["list", "runtimes", "-j"])
        XCTAssertEqual(SimctlArguments.listApps(udid).arguments, ["listapps", udid.rawValue])
    }

    func testDeviceLifecycleCommands() {
        XCTAssertEqual(
            SimctlArguments.createDevice(name: "OpenSim IT", deviceType: "iPhone-Air", runtime: RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-27-0")).arguments,
            ["create", "OpenSim IT", "iPhone-Air", "com.apple.CoreSimulator.SimRuntime.iOS-27-0"]
        )
        XCTAssertEqual(SimctlArguments.createDevice(name: "OpenSim IT", deviceType: "iPhone-Air", runtime: nil).arguments, ["create", "OpenSim IT", "iPhone-Air"])
        XCTAssertEqual(SimctlArguments.boot(udid).arguments, ["boot", udid.rawValue])
        XCTAssertEqual(SimctlArguments.bootStatus(udid).arguments, ["bootstatus", udid.rawValue, "-b"])
        XCTAssertEqual(SimctlArguments.erase(udid).arguments, ["erase", udid.rawValue])
        XCTAssertEqual(SimctlArguments.delete(udid).arguments, ["delete", udid.rawValue])
        XCTAssertEqual(SimctlArguments.rename(udid, to: "New Name").arguments, ["rename", udid.rawValue, "New Name"])
    }

    func testRuntimeCommandsUseRuntimeAdd() {
        XCTAssertEqual(SimctlArguments.runtimeAdd(path: "/tmp/iOS.dmg").arguments, ["runtime", "add", "/tmp/iOS.dmg"])
        XCTAssertEqual(SimctlArguments.runtimeDelete(identifier: RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-27-0")).arguments, ["runtime", "delete", "com.apple.CoreSimulator.SimRuntime.iOS-27-0"])
        XCTAssertEqual(SimctlArguments.runtimeVerify(identifier: RuntimeID("runtime-1")).arguments, ["runtime", "verify", "runtime-1"])
    }

    func testAppCommandsAndEnvironmentPrefix() {
        let launch = SimctlArguments.launchApp(
            udid,
            bundleID: "com.apple.Preferences",
            args: ["-AppleLanguages", "(en)"],
            environment: ["OS_ACTIVITY_MODE": "disable"]
        )
        XCTAssertEqual(
            launch.arguments,
            ["launch", udid.rawValue, "com.apple.Preferences", "-AppleLanguages", "(en)"]
        )
        XCTAssertEqual(launch.environment, ["SIMCTL_CHILD_OS_ACTIVITY_MODE": "disable"])
        XCTAssertEqual(
            SimctlArguments.getAppContainer(udid, bundleID: "com.apple.Preferences", kind: .group).arguments,
            ["get_app_container", udid.rawValue, "com.apple.Preferences", "groups"]
        )
    }

    func testLogShowArguments() {
        XCTAssertEqual(
            SimctlArguments.logShow(device: udid, since: nil, last: "5m", predicate: "subsystem == \"com.apple.UIKit\"").arguments,
            ["spawn", udid.rawValue, "log", "show", "--style", "ndjson", "--info", "--debug", "--last", "5m", "--predicate", "subsystem == \"com.apple.UIKit\""]
        )
        XCTAssertEqual(
            SimctlArguments.logShow(device: udid, since: "2026-10-20 10:00:00.000000+0700", last: nil, predicate: nil).arguments,
            ["spawn", udid.rawValue, "log", "show", "--style", "ndjson", "--info", "--debug", "--start", "2026-10-20 10:00:00.000000+0700"]
        )
    }

    func testErrorMapperMapsKnownFailures() {
        let command = SimctlArguments.boot(udid)
        let invalid = SimctlOutput(status: 148, stdout: Data(), stderr: Data("Invalid device: \(udid.rawValue)\n".utf8))
        XCTAssertEqual(SimctlErrorMapper.error(for: command, output: invalid).code, "device_not_found")

        let busy = SimctlOutput(status: 149, stdout: Data(), stderr: Data("Unable to boot device in current state: Booted\n".utf8))
        XCTAssertEqual(SimctlErrorMapper.error(for: command, output: busy).code, "device_busy")

        let stopped = SimctlOutput(status: 149, stdout: Data(), stderr: Data("Unable to lookup in current state: Shutdown\n".utf8))
        XCTAssertEqual(SimctlErrorMapper.error(for: command, output: stopped).code, "device_not_booted")

        let generic = SimctlOutput(status: 1, stdout: Data(), stderr: Data("unknown failure\n".utf8))
        let mapped = SimctlErrorMapper.error(for: command, output: generic)
        XCTAssertEqual(mapped.code, "simctl_failed")
        XCTAssertEqual(mapped.details["exitStatus"], "1")
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter SimctlCommandTests
```

Expected: FAIL với `cannot find type 'SimctlArguments' in scope`.

- [ ] **Step 3: Viết simctl layer**

Modify `Package.swift` để thêm product/target bridge:

```swift
    products: [
        .library(name: "OpenSimCore", targets: ["OpenSimCore"]),
        .library(name: "OpenSimBridge", targets: ["OpenSimBridge"]),
    ],
    targets: [
        .target(name: "OpenSimCore"),
        .target(name: "OpenSimBridge", dependencies: ["OpenSimCore"]),
        .testTarget(name: "OpenSimCoreTests", dependencies: ["OpenSimCore"]),
        .testTarget(name: "OpenSimBridgeTests", dependencies: ["OpenSimBridge", "OpenSimCore"]),
    ],
```

Create `Sources/OpenSimBridge/Simctl/SimctlCommand.swift`:

```swift
import Foundation
import OpenSimCore

public struct SimctlCommand: Sendable, Equatable {
    public var arguments: [String]
    public var environment: [String: String]

    public init(arguments: [String], environment: [String: String] = [:]) {
        self.arguments = arguments
        self.environment = environment
    }

    public var displayString: String {
        (["simctl"] + arguments).joined(separator: " ")
    }
}

public enum SimctlArguments {
    public static func listDevicesJSON() -> SimctlCommand {
        SimctlCommand(arguments: ["list", "devices", "-j"])
    }

    public static func listRuntimesJSON() -> SimctlCommand {
        SimctlCommand(arguments: ["list", "runtimes", "-j"])
    }

    public static func createDevice(name: String, deviceType: String, runtime: RuntimeID?) -> SimctlCommand {
        var arguments = ["create", name, deviceType]
        if let runtime {
            arguments.append(runtime.rawValue)
        }
        return SimctlCommand(arguments: arguments)
    }

    public static func cloneDevice(_ device: DeviceID, name: String) -> SimctlCommand {
        SimctlCommand(arguments: ["clone", device.rawValue, name])
    }

    public static func boot(_ device: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["boot", device.rawValue])
    }

    public static func bootStatus(_ device: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["bootstatus", device.rawValue, "-b"])
    }

    public static func shutdown(_ device: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["shutdown", device.rawValue])
    }

    public static func erase(_ device: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["erase", device.rawValue])
    }

    public static func delete(_ device: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["delete", device.rawValue])
    }

    public static func rename(_ device: DeviceID, to name: String) -> SimctlCommand {
        SimctlCommand(arguments: ["rename", device.rawValue, name])
    }

    public static func pair(watch: DeviceID, phone: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["pair", watch.rawValue, phone.rawValue])
    }

    public static func runtimeAdd(path: String) -> SimctlCommand {
        SimctlCommand(arguments: ["runtime", "add", path])
    }

    public static func runtimeDelete(identifier: RuntimeID) -> SimctlCommand {
        SimctlCommand(arguments: ["runtime", "delete", identifier.rawValue])
    }

    public static func runtimeVerify(identifier: RuntimeID) -> SimctlCommand {
        SimctlCommand(arguments: ["runtime", "verify", identifier.rawValue])
    }

    public static func listApps(_ device: DeviceID) -> SimctlCommand {
        SimctlCommand(arguments: ["listapps", device.rawValue])
    }

    public static func appInfo(_ device: DeviceID, bundleID: String) -> SimctlCommand {
        SimctlCommand(arguments: ["appinfo", device.rawValue, bundleID])
    }

    public static func installApp(_ device: DeviceID, path: String) -> SimctlCommand {
        SimctlCommand(arguments: ["install", device.rawValue, path])
    }

    public static func uninstallApp(_ device: DeviceID, bundleID: String) -> SimctlCommand {
        SimctlCommand(arguments: ["uninstall", device.rawValue, bundleID])
    }

    public static func launchApp(
        _ device: DeviceID,
        bundleID: String,
        args: [String],
        environment: [String: String]
    ) -> SimctlCommand {
        let childEnvironment = Dictionary(
            uniqueKeysWithValues: environment.map { key, value in ("SIMCTL_CHILD_\(key)", value) }
        )
        return SimctlCommand(
            arguments: ["launch", device.rawValue, bundleID] + args,
            environment: childEnvironment
        )
    }

    public static func terminateApp(_ device: DeviceID, bundleID: String) -> SimctlCommand {
        SimctlCommand(arguments: ["terminate", device.rawValue, bundleID])
    }

    public static func getAppContainer(_ device: DeviceID, bundleID: String, kind: ContainerKind) -> SimctlCommand {
        let container: String
        switch kind {
        case .app:
            container = "app"
        case .data:
            container = "data"
        case .group:
            container = "groups"
        }
        return SimctlCommand(arguments: ["get_app_container", device.rawValue, bundleID, container])
    }

    public static func logShow(device: DeviceID, since: String?, last: String?, predicate: String?) -> SimctlCommand {
        var arguments = ["spawn", device.rawValue, "log", "show", "--style", "ndjson", "--info", "--debug"]
        if let since {
            arguments.append(contentsOf: ["--start", since])
        } else if let last {
            arguments.append(contentsOf: ["--last", last])
        }
        if let predicate {
            arguments.append(contentsOf: ["--predicate", predicate])
        }
        return SimctlCommand(arguments: arguments)
    }
}
```

Create `Sources/OpenSimBridge/Simctl/SimctlExecutor.swift`:

```swift
import Darwin
import Foundation
import OpenSimCore

public struct SimctlOutput: Sendable, Equatable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data

    public init(status: Int32, stdout: Data, stderr: Data) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol SimctlExecuting: Sendable {
    func run(_ command: SimctlCommand, timeout: Duration) async throws -> SimctlOutput
}

public struct ProcessSimctlExecutor: SimctlExecuting {
    public let xcrunPath: String

    public init(xcrunPath: String = "/usr/bin/xcrun") {
        self.xcrunPath = xcrunPath
    }

    public func run(_ command: SimctlCommand, timeout: Duration) async throws -> SimctlOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrunPath)
        process.arguments = ["simctl"] + command.arguments
        if !command.environment.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in command.environment {
                environment[key] = value
            }
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let stdoutTask = Task.detached { stdoutHandle.readDataToEndOfFile() }
        let stderrTask = Task.detached { stderrHandle.readDataToEndOfFile() }

        let deadline = ContinuousClock.now + timeout
        while process.isRunning {
            if ContinuousClock.now >= deadline {
                process.terminate()
                try await Task.sleep(for: .milliseconds(200))
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                let stdout = await stdoutTask.value
                let stderr = await stderrTask.value
                throw OpenSimError(
                    code: .simctlFailed,
                    message: "simctl timed out after \(timeout)",
                    details: [
                        "command": command.displayString,
                        "stdout": String(decoding: stdout, as: UTF8.self),
                        "stderr": String(decoding: stderr, as: UTF8.self),
                    ],
                    recovery: "Increase --timeout or check the simulator state",
                    retryable: true
                )
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        let stdout = await stdoutTask.value
        let stderr = await stderrTask.value
        return SimctlOutput(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
```

Create `Sources/OpenSimBridge/Simctl/SimctlErrorMapper.swift`:

```swift
import Foundation
import OpenSimCore

public enum SimctlErrorMapper {
    public static func requireSuccess(command: SimctlCommand, output: SimctlOutput) throws {
        guard output.status == 0 else {
            throw error(for: command, output: output)
        }
    }

    public static func error(for command: SimctlCommand, output: SimctlOutput) -> OpenSimError {
        let stderr = String(decoding: output.stderr, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = String(decoding: output.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = stderr.isEmpty ? "simctl exited with status \(output.status)" : stderr
        var details = [
            "command": command.displayString,
            "exitStatus": "\(output.status)",
        ]
        if !stdout.isEmpty {
            details["stdout"] = stdout
        }

        if message.localizedCaseInsensitiveContains("Invalid device") ||
            message.localizedCaseInsensitiveContains("No devices are booted") {
            return OpenSimError(
                code: .deviceNotFound,
                message: message,
                details: details,
                recovery: "Run `opensim device list` to find the device",
                retryable: false
            )
        }
        if message.localizedCaseInsensitiveContains("current state: Booted") {
            return OpenSimError(
                code: .deviceBusy,
                message: message,
                details: details,
                recovery: "Shut down the device before this operation",
                retryable: false
            )
        }
        if message.localizedCaseInsensitiveContains("current state: Shutdown") ||
            message.localizedCaseInsensitiveContains("found nothing to terminate") {
            return OpenSimError(
                code: .deviceNotBooted,
                message: message,
                details: details,
                recovery: "Boot the device before this operation",
                retryable: false
            )
        }
        if message.localizedCaseInsensitiveContains("Unable to delete") {
            return OpenSimError(
                code: .deviceBusy,
                message: message,
                details: details,
                recovery: "Shut down the device before deleting it",
                retryable: false
            )
        }
        return OpenSimError(
            code: .simctlFailed,
            message: message,
            details: details,
            recovery: "Run `xcrun simctl help` and check the device state",
            retryable: false
        )
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter SimctlCommandTests
```

Expected: PASS; `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Simctl Tests/OpenSimBridgeTests/SimctlCommandTests.swift
git commit -m "feat(bridge): add simctl argument builder and executor"
```

---

### Task 8: SimctlDeviceService lifecycle

**Files:**
- Create: `Sources/OpenSimBridge/Simctl/SimctlPayloads.swift`
- Create: `Sources/OpenSimBridge/Services/SimctlDeviceService.swift`
- Test: `Tests/OpenSimBridgeTests/SimctlDeviceServiceTests.swift`

**Interfaces:**
- Consumes: `SimctlExecuting`, `SimctlArguments`, `SimctlErrorMapper`, `OpenSimJSON`, `IdentifierValidation`, `DeviceResolver`.
- Produces: `SimctlDeviceService(executor:timeout:)` conforms `DeviceControlling`; `SimctlDeviceListPayload`, `SimctlDevicePayload`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeTests/SimctlDeviceServiceTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

actor StubSimctlExecutor: SimctlExecuting {
    private var outputs: [SimctlOutput] = []
    private(set) var commands: [SimctlCommand] = []

    func enqueue(_ output: SimctlOutput) {
        outputs.append(output)
    }

    func run(_ command: SimctlCommand, timeout: Duration) async throws -> SimctlOutput {
        commands.append(command)
        guard !outputs.isEmpty else {
            throw OpenSimError(code: .internalError, message: "stub has no output for \(command.displayString)")
        }
        return outputs.removeFirst()
    }
}

func jsonOutput(_ text: String, status: Int32 = 0) -> SimctlOutput {
    SimctlOutput(status: status, stdout: Data(text.utf8), stderr: Data())
}

let deviceListJSON = """
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"95B3747B-7065-447E-AB1E-53065142C3FC","name":"iPhone Air","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-Air","dataPath":"/tmp/device-data"}]}}
"""

final class SimctlDeviceServiceTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    func testListDevicesParsesRuntimeAndState() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(deviceListJSON))
        let service = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        let devices = try await service.listDevices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].id, udid)
        XCTAssertEqual(devices[0].platform, .iOS)
        XCTAssertEqual(devices[0].state, .booted)
        XCTAssertEqual(devices[0].runtime, RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"))
    }

    func testGetMissingDeviceThrowsNotFound() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(deviceListJSON))
        let service = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        do {
            _ = try await service.device(DeviceID("11111111-1111-1111-1111-111111111111"))
            XCTFail("expected device_not_found")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "device_not_found")
        }
    }

    func testBootWhenAlreadyBootedDoesNotCallBoot() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(deviceListJSON))
        let service = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        let device = try await service.boot(udid, wait: false)
        XCTAssertEqual(device.state, .booted)
        let commands = await executor.commands
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].arguments, ["list", "devices", "-j"])
    }

    func testBootWaitUsesBootStatus() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("""
        {"devices":{"runtime":[{"udid":"95B3747B-7065-447E-AB1E-53065142C3FC","name":"iPhone Air","state":"Shutdown","isAvailable":true}]}}
        """))
        await executor.enqueue(jsonOutput(""))
        await executor.enqueue(jsonOutput("""
        {"devices":{"runtime":[{"udid":"95B3747B-7065-447E-AB1E-53065142C3FC","name":"iPhone Air","state":"Booted","isAvailable":true}]}}
        """))
        let service = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        let device = try await service.boot(udid, wait: true)
        XCTAssertEqual(device.state, .booted)
        let commands = await executor.commands
        XCTAssertEqual(commands.map(\.arguments), [
            ["list", "devices", "-j"],
            ["bootstatus", udid.rawValue, "-b"],
            ["list", "devices", "-j"],
        ])
    }

    func testEraseBootedDeviceReturnsBusy() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(deviceListJSON))
        let service = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        do {
            _ = try await service.erase(udid)
            XCTFail("expected device_busy")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "device_busy")
        }
        let commands = await executor.commands
        XCTAssertEqual(commands.count, 1)
    }

    func testDeleteRunsDeleteCommand() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(""))
        let service = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        try await service.delete(udid)
        let commands = await executor.commands
        XCTAssertEqual(commands[0].arguments, ["delete", udid.rawValue])
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter SimctlDeviceServiceTests
```

Expected: FAIL với `cannot find type 'SimctlDeviceService' in scope`.

- [ ] **Step 3: Viết device service**

Create `Sources/OpenSimBridge/Simctl/SimctlPayloads.swift`:

```swift
import Foundation
import OpenSimCore

struct SimctlDeviceListPayload: Decodable {
    let devices: [String: [SimctlDevicePayload]]
}

struct SimctlDevicePayload: Decodable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool?
    let deviceTypeIdentifier: String?
    let dataPath: String?
    let lastBootedAt: Date?
}

struct SimctlRuntimeListPayload: Decodable {
    let runtimes: [SimctlRuntimePayload]
}

struct SimctlRuntimePayload: Decodable {
    let identifier: String
    let name: String
    let version: String
    let buildversion: String?
    let isAvailable: Bool?
    let platform: String?
    let bundlePath: String?
    let runtimeRoot: String?
}
```

Create `Sources/OpenSimBridge/Services/SimctlDeviceService.swift`:

```swift
import Foundation
import OpenSimCore

public struct SimctlDeviceService: DeviceControlling {
    private let executor: any SimctlExecuting
    private let timeout: Duration

    public init(executor: any SimctlExecuting, timeout: Duration) {
        self.executor = executor
        self.timeout = timeout
    }

    public func listDevices() async throws -> [Device] {
        let command = SimctlArguments.listDevicesJSON()
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let payload = try OpenSimJSON.decoder().decode(SimctlDeviceListPayload.self, from: output.stdout)
        var devices: [Device] = []
        for (runtimeIdentifier, entries) in payload.devices {
            for entry in entries {
                devices.append(map(entry, runtimeIdentifier: runtimeIdentifier))
            }
        }
        return devices.sorted {
            if $0.name == $1.name {
                return $0.id.rawValue < $1.id.rawValue
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func device(_ id: DeviceID) async throws -> Device {
        let devices = try await listDevices()
        guard let match = devices.first(where: { $0.id == id }) else {
            throw OpenSimError.deviceNotFound(id)
        }
        return match
    }

    public func createDevice(name: String, deviceType: String, runtime: RuntimeID?) async throws -> Device {
        try IdentifierValidation.validateName(name, field: "name")
        try IdentifierValidation.validateName(deviceType, field: "deviceType")
        let command = SimctlArguments.createDevice(name: name, deviceType: deviceType, runtime: runtime)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let text = String(decoding: output.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let newID = text.split(separator: "\n").last.map(String.init), IdentifierValidation.isUDID(newID) else {
            throw OpenSimError(
                code: .simctlFailed,
                message: "simctl create did not return a UDID",
                details: ["stdout": text],
                recovery: "Check `xcrun simctl list devices` and delete the partial device"
            )
        }
        return try await device(DeviceID(newID))
    }

    public func cloneDevice(_ id: DeviceID, name: String) async throws -> Device {
        try IdentifierValidation.validateName(name, field: "name")
        _ = try await device(id)
        let command = SimctlArguments.cloneDevice(id, name: name)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let text = String(decoding: output.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let newID = text.split(separator: "\n").last.map(String.init), IdentifierValidation.isUDID(newID) else {
            throw OpenSimError(
                code: .simctlFailed,
                message: "simctl clone did not return a UDID",
                details: ["stdout": text]
            )
        }
        return try await device(DeviceID(newID))
    }

    public func boot(_ id: DeviceID, wait: Bool) async throws -> Device {
        let current = try await device(id)
        if current.state == .booted {
            return current
        }
        if current.state == .booting {
            return wait ? try await waitForState(id, .booted) : current
        }
        if wait {
            let command = SimctlArguments.bootStatus(id)
            let output = try await executor.run(command, timeout: timeout)
            try SimctlErrorMapper.requireSuccess(command: command, output: output)
            return try await waitForState(id, .booted)
        }
        let command = SimctlArguments.boot(id)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        return try await device(id)
    }

    public func shutdown(_ id: DeviceID, wait: Bool) async throws -> Device {
        let current = try await device(id)
        if current.state == .shutdown {
            return current
        }
        let command = SimctlArguments.shutdown(id)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        if wait {
            return try await waitForState(id, .shutdown)
        }
        return try await device(id)
    }

    public func erase(_ id: DeviceID) async throws -> Device {
        let current = try await device(id)
        guard current.state == .shutdown else {
            throw OpenSimError(
                code: .deviceBusy,
                message: "Device must be shut down before erase",
                details: ["udid": id.rawValue, "state": current.state.rawValue],
                recovery: "Run `opensim device shutdown --device \(id.rawValue) --wait` first"
            )
        }
        let command = SimctlArguments.erase(id)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        return try await device(id)
    }

    public func delete(_ id: DeviceID) async throws {
        _ = try await device(id)
        let command = SimctlArguments.delete(id)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
    }

    public func rename(_ id: DeviceID, to name: String) async throws -> Device {
        try IdentifierValidation.validateName(name, field: "name")
        _ = try await device(id)
        let command = SimctlArguments.rename(id, to: name)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        return try await device(id)
    }

    public func pair(watch: DeviceID, phone: DeviceID) async throws {
        _ = try await device(watch)
        _ = try await device(phone)
        let command = SimctlArguments.pair(watch: watch, phone: phone)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
    }

    private func map(_ entry: SimctlDevicePayload, runtimeIdentifier: String) -> Device {
        Device(
            id: DeviceID(entry.udid),
            name: entry.name,
            platform: Device.platform(forRuntimeIdentifier: runtimeIdentifier),
            deviceType: entry.deviceTypeIdentifier ?? "",
            runtime: RuntimeID(runtimeIdentifier),
            state: Device.parseState(entry.state),
            isAvailable: entry.isAvailable ?? true,
            dataPath: entry.dataPath,
            lastBootedAt: entry.lastBootedAt
        )
    }

    private func waitForState(_ id: DeviceID, _ expected: DeviceState) async throws -> Device {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let current = try await device(id)
            if current.state == expected {
                return current
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw OpenSimError(
            code: .deviceBusy,
            message: "Timed out waiting for device \(id.rawValue) to become \(expected.rawValue)",
            details: ["udid": id.rawValue, "expectedState": expected.rawValue],
            recovery: "Increase --timeout and retry",
            retryable: true
        )
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter SimctlDeviceServiceTests
```

Expected: PASS; `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Simctl/SimctlPayloads.swift Sources/OpenSimBridge/Services/SimctlDeviceService.swift Tests/OpenSimBridgeTests/SimctlDeviceServiceTests.swift
git commit -m "feat(bridge): add simctl device lifecycle service"
```

### Task 9: Runtime service, app service và plist parsing

**Files:**
- Create: `Sources/OpenSimBridge/Services/SimctlRuntimeService.swift`
- Create: `Sources/OpenSimBridge/Services/SimctlAppService.swift`
- Create: `Sources/OpenSimBridge/Services/SimctlPlistParser.swift`
- Test: `Tests/OpenSimBridgeTests/SimctlRuntimeServiceTests.swift`
- Test: `Tests/OpenSimBridgeTests/SimctlAppServiceTests.swift`

**Interfaces:**
- Consumes: `SimctlExecuting`, `SimctlArguments`, `SimctlErrorMapper`, `SimctlRuntimeListPayload`, `PathPolicy`, `IdentifierValidation`.
- Produces: `SimctlRuntimeService(executor:timeout:)` conforms `RuntimeControlling`; `SimctlAppService(executor:timeout:)` conforms `AppControlling`; `SimctlPlistParser.appList(from:)`, `.appInfo(from:bundleID:)`, `.bundleID(atAppPath:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeTests/SimctlRuntimeServiceTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class SimctlRuntimeServiceTests: XCTestCase {
    func testListRuntimesParsesPlatformAndBuild() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("""
        {"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","buildversion":"24A434","isAvailable":true,"platform":"iOS","bundlePath":"/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.0.simruntime"}]}
        """))
        let service = SimctlRuntimeService(executor: executor, timeout: .seconds(5))
        let runtimes = try await service.listRuntimes()
        XCTAssertEqual(runtimes.count, 1)
        XCTAssertEqual(runtimes[0].platform, .iOS)
        XCTAssertEqual(runtimes[0].build, "24A434")
        XCTAssertEqual(runtimes[0].version, "27.0")
    }

    func testInstallRuntimeDiffsRuntimeList() async throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("iOS.dmg")
        try Data("runtime".utf8).write(to: image)

        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("""
        {"runtimes":[]}
        """))
        await executor.enqueue(jsonOutput(""))
        await executor.enqueue(jsonOutput("""
        {"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","name":"iOS 27.0","version":"27.0","buildversion":"24A434","isAvailable":true,"platform":"iOS","bundlePath":"/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.0.simruntime"}]}
        """))
        let service = SimctlRuntimeService(executor: executor, timeout: .seconds(5))
        let runtime = try await service.installRuntime(at: image.path)
        XCTAssertEqual(runtime.id, RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"))
        let commands = await executor.commands
        XCTAssertEqual(commands.map(\.arguments), [
            ["list", "runtimes", "-j"],
            ["runtime", "add", image.path],
            ["list", "runtimes", "-j"],
        ])
    }

    func testDeleteRuntimeUsesRuntimeDelete() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(""))
        let service = SimctlRuntimeService(executor: executor, timeout: .seconds(5))
        try await service.deleteRuntime(RuntimeID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"))
        let commands = await executor.commands
        XCTAssertEqual(commands[0].arguments, ["runtime", "delete", "com.apple.CoreSimulator.SimRuntime.iOS-27-0"])
    }
}
```

Create `Tests/OpenSimBridgeTests/SimctlAppServiceTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

let listAppsPlist = """
{
    "com.apple.Preferences" =     {
        ApplicationType = System;
        CFBundleDisplayName = Settings;
        CFBundleIdentifier = "com.apple.Preferences";
        CFBundleName = Settings;
        CFBundleShortVersionString = "1.0";
        CFBundleVersion = "2027.0.10.401";
        DataContainer = "file:///Users/test/Library/Developer/CoreSimulator/Devices/UDID/data/Containers/Data/Application/DATA/";
        Path = "/Applications/Preferences.app";
    };
}
"""

final class SimctlAppServiceTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    func testListAppsParsesOpenStepPlistAndFilters() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(listAppsPlist))
        let service = SimctlAppService(executor: executor, timeout: .seconds(5))
        let all = try await service.listApps(on: udid, filter: nil)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, "com.apple.Preferences")
        XCTAssertEqual(all[0].displayName, "Settings")
        XCTAssertEqual(all[0].version, "1.0")
        XCTAssertEqual(all[0].build, "2027.0.10.401")
        XCTAssertEqual(all[0].dataContainer, "/Users/test/Library/Developer/CoreSimulator/Devices/UDID/data/Containers/Data/Application/DATA")
        XCTAssertEqual(all[0].appContainer, "/Applications/Preferences.app")

        let filtered = try await service.listApps(on: udid, filter: "settings")
        XCTAssertEqual(filtered.count, 1)
        let missing = try await service.listApps(on: udid, filter: "Safari")
        XCTAssertEqual(missing.count, 0)
    }

    func testAppInfoParsesSinglePlist() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("""
        {
            CFBundleDisplayName = Settings;
            CFBundleIdentifier = "com.apple.Preferences";
            CFBundleShortVersionString = "1.0";
            CFBundleVersion = "2027.0.10.401";
            DataContainer = "file:///Users/test/data/";
            Path = "/Applications/Preferences.app";
        }
        """))
        let service = SimctlAppService(executor: executor, timeout: .seconds(5))
        let info = try await service.appInfo(on: udid, bundleID: "com.apple.Preferences")
        XCTAssertEqual(info.displayName, "Settings")
        XCTAssertEqual(info.dataContainer, "/Users/test/data")
    }

    func testLaunchParsesPID() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("com.apple.Preferences: 4321\n"))
        let service = SimctlAppService(executor: executor, timeout: .seconds(5))
        let pid = try await service.launchApp(
            on: udid,
            bundleID: "com.apple.Preferences",
            args: [],
            environment: ["OS_ACTIVITY_MODE": "disable"]
        )
        XCTAssertEqual(pid, 4321)
        let commands = await executor.commands
        XCTAssertEqual(commands[0].environment, ["SIMCTL_CHILD_OS_ACTIVITY_MODE": "disable"])
    }

    func testContainerPathRejectsNull() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput("(null)\n"))
        let service = SimctlAppService(executor: executor, timeout: .seconds(5))
        do {
            _ = try await service.containerPath(on: udid, bundleID: "com.apple.Preferences", kind: .data)
            XCTFail("expected simctl_failed")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "simctl_failed")
        }
    }

    func testTerminateIsIdempotentWhenNothingRuns() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(SimctlOutput(
            status: 1,
            stdout: Data(),
            stderr: Data("found nothing to terminate\n".utf8)
        ))
        let service = SimctlAppService(executor: executor, timeout: .seconds(5))
        try await service.terminateApp(on: udid, bundleID: "com.apple.Preferences")
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter SimctlRuntimeServiceTests
swift test --filter SimctlAppServiceTests
```

Expected: FAIL với `cannot find type 'SimctlRuntimeService' in scope`, `cannot find type 'SimctlAppService' in scope`.

- [ ] **Step 3: Viết runtime và app services**

Create `Sources/OpenSimBridge/Services/SimctlRuntimeService.swift`:

```swift
import Foundation
import OpenSimCore

public struct SimctlRuntimeService: RuntimeControlling {
    private let executor: any SimctlExecuting
    private let timeout: Duration

    public init(executor: any SimctlExecuting, timeout: Duration) {
        self.executor = executor
        self.timeout = timeout
    }

    public func listRuntimes() async throws -> [Runtime] {
        let command = SimctlArguments.listRuntimesJSON()
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let payload = try OpenSimJSON.decoder().decode(SimctlRuntimeListPayload.self, from: output.stdout)
        let runtimes = payload.runtimes.map { entry in
            Runtime(
                id: RuntimeID(entry.identifier),
                name: entry.name,
                platform: entry.platform.map(Platform.init(rawValue:)) ?? Device.platform(forRuntimeIdentifier: entry.identifier),
                version: entry.version,
                build: entry.buildversion ?? "",
                isAvailable: entry.isAvailable ?? true,
                path: entry.bundlePath ?? entry.runtimeRoot
            )
        }
        return runtimes.sorted {
            if $0.platform.rawValue == $1.platform.rawValue {
                return $0.version.localizedStandardCompare($1.version) == .orderedAscending
            }
            return $0.platform.rawValue < $1.platform.rawValue
        }
    }

    public func installRuntime(at path: String) async throws -> Runtime {
        let validated = try PathPolicy.validateRuntimeImage(path)
        let before = Set(try await listRuntimes().map(\.id))
        let command = SimctlArguments.runtimeAdd(path: validated)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let after = try await listRuntimes()
        guard let added = after.first(where: { !before.contains($0.id) }) else {
            throw OpenSimError(
                code: .simctlFailed,
                message: "Runtime was added but did not appear in the runtime list",
                details: ["path": validated],
                recovery: "Run `opensim runtime list` and verify the runtime manually"
            )
        }
        return added
    }

    public func deleteRuntime(_ id: RuntimeID) async throws {
        let command = SimctlArguments.runtimeDelete(identifier: id)
        let output = try await executor.run(command, timeout: timeout)
        guard output.status == 0 else {
            let mapped = SimctlErrorMapper.error(for: command, output: output)
            let text = String(decoding: output.stderr, as: UTF8.self)
            if text.localizedCaseInsensitiveContains("in use") || text.localizedCaseInsensitiveContains("booted") {
                throw OpenSimError(
                    code: .deviceBusy,
                    message: "Runtime is in use: \(id.rawValue)",
                    details: ["runtime": id.rawValue, "stderr": text],
                    recovery: "Shut down devices that use this runtime and retry",
                    retryable: false
                )
            }
            throw mapped
        }
    }

    public func verifyRuntime(_ id: RuntimeID) async throws {
        let command = SimctlArguments.runtimeVerify(identifier: id)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
    }
}
```

Create `Sources/OpenSimBridge/Services/SimctlPlistParser.swift`:

```swift
import Foundation
import OpenSimCore

enum SimctlPlistParser {
    static func appList(from data: Data) throws -> [AppInfo] {
        let object = try propertyList(from: data)
        guard let dictionary = object as? [String: [String: Any]] else {
            throw invalidPlist("listapps root is not a dictionary")
        }
        return dictionary.compactMap { bundleID, fields in
            appInfo(bundleID: bundleID, fields: fields)
        }
        .sorted { $0.id < $1.id }
    }

    static func appInfo(from data: Data, bundleID: String) throws -> AppInfo {
        let object = try propertyList(from: data)
        guard let fields = object as? [String: Any] else {
            throw invalidPlist("appinfo root is not a dictionary")
        }
        guard let info = appInfo(bundleID: bundleID, fields: fields) else {
            throw invalidPlist("appinfo does not contain bundle fields")
        }
        return info
    }

    static func bundleID(atAppPath path: String) throws -> String {
        let infoURL = URL(fileURLWithPath: path).appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL) else {
            throw OpenSimError.invalidArgument(
                "App bundle does not contain Info.plist: \(path)",
                recovery: "Pass an installable .app directory"
            )
        }
        let object = try propertyList(from: data)
        guard let dictionary = object as? [String: Any],
              let bundleID = dictionary["CFBundleIdentifier"] as? String else {
            throw invalidPlist("Info.plist has no CFBundleIdentifier")
        }
        try IdentifierValidation.validateBundleID(bundleID)
        return bundleID
    }

    private static func appInfo(bundleID: String, fields: [String: Any]) -> AppInfo? {
        guard !bundleID.isEmpty else {
            return nil
        }
        return AppInfo(
            id: bundleID,
            displayName: string(fields["CFBundleDisplayName"]) ?? string(fields["CFBundleName"]),
            version: string(fields["CFBundleShortVersionString"]),
            build: string(fields["CFBundleVersion"]),
            dataContainer: path(fields["DataContainer"]),
            appContainer: path(fields["Path"])
        )
    }

    private static func propertyList(from data: Data) throws -> Any {
        do {
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw invalidPlist("Cannot parse property list: \(error.localizedDescription)")
        }
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func path(_ value: Any?) -> String? {
        guard var text = string(value), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("file://") {
            if let url = URL(string: text) {
                text = url.path
            }
        }
        while text.count > 1 && text.hasSuffix("/") {
            text.removeLast()
        }
        return text.isEmpty ? nil : text
    }

    private static func invalidPlist(_ message: String) -> OpenSimError {
        OpenSimError(
            code: .simctlFailed,
            message: message,
            recovery: "Run `xcrun simctl listapps <device>` manually and inspect the output"
        )
    }
}
```

Create `Sources/OpenSimBridge/Services/SimctlAppService.swift`:

```swift
import Foundation
import OpenSimCore

public struct SimctlAppService: AppControlling {
    private let executor: any SimctlExecuting
    private let timeout: Duration

    public init(executor: any SimctlExecuting, timeout: Duration) {
        self.executor = executor
        self.timeout = timeout
    }

    public func listApps(on device: DeviceID, filter: String?) async throws -> [AppInfo] {
        let command = SimctlArguments.listApps(device)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let apps = try SimctlPlistParser.appList(from: output.stdout)
        guard let filter, !filter.isEmpty else {
            return apps
        }
        return apps.filter { app in
            app.id.localizedCaseInsensitiveContains(filter) ||
                (app.displayName ?? "").localizedCaseInsensitiveContains(filter)
        }
    }

    public func installApp(on device: DeviceID, at path: String) async throws -> AppInfo {
        let validated = try PathPolicy.validateAppBundle(path)
        let bundleID = try SimctlPlistParser.bundleID(atAppPath: validated)
        let command = SimctlArguments.installApp(device, path: validated)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        return try await appInfo(on: device, bundleID: bundleID)
    }

    public func uninstallApp(on device: DeviceID, bundleID: String) async throws {
        try IdentifierValidation.validateBundleID(bundleID)
        let command = SimctlArguments.uninstallApp(device, bundleID: bundleID)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
    }

    public func launchApp(
        on device: DeviceID,
        bundleID: String,
        args: [String],
        environment: [String: String]
    ) async throws -> Int32 {
        try IdentifierValidation.validateBundleID(bundleID)
        for key in environment.keys {
            try IdentifierValidation.validateName(key, field: "environment key")
        }
        let command = SimctlArguments.launchApp(device, bundleID: bundleID, args: args, environment: environment)
        let output = try await executor.run(command, timeout: timeout)
        guard output.status == 0 else {
            throw SimctlErrorMapper.error(for: command, output: output)
        }
        let text = String(decoding: output.stdout, as: UTF8.self)
        let lastLine = text
            .split(separator: "\n")
            .last
            .map(String.init) ?? ""
        guard let pidText = lastLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
              let pid = Int32(pidText) else {
            throw OpenSimError(
                code: .simctlFailed,
                message: "simctl launch did not return a pid",
                details: ["stdout": text],
                recovery: "Check that the bundle identifier is installed"
            )
        }
        return pid
    }

    public func terminateApp(on device: DeviceID, bundleID: String) async throws {
        try IdentifierValidation.validateBundleID(bundleID)
        let command = SimctlArguments.terminateApp(device, bundleID: bundleID)
        let output = try await executor.run(command, timeout: timeout)
        if output.status == 0 {
            return
        }
        let text = String(decoding: output.stderr, as: UTF8.self)
        if text.localizedCaseInsensitiveContains("found nothing to terminate") {
            return
        }
        throw SimctlErrorMapper.error(for: command, output: output)
    }

    public func appInfo(on device: DeviceID, bundleID: String) async throws -> AppInfo {
        try IdentifierValidation.validateBundleID(bundleID)
        let command = SimctlArguments.appInfo(device, bundleID: bundleID)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        return try SimctlPlistParser.appInfo(from: output.stdout, bundleID: bundleID)
    }

    public func containerPath(on device: DeviceID, bundleID: String, kind: ContainerKind) async throws -> String {
        try IdentifierValidation.validateBundleID(bundleID)
        let command = SimctlArguments.getAppContainer(device, bundleID: bundleID, kind: kind)
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let text = String(decoding: output.stdout, as: UTF8.self)
        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "(null)" }
        guard let path = lines.first(where: { $0.hasPrefix("/") }) else {
            throw OpenSimError(
                code: .simctlFailed,
                message: "No \(kind.rawValue) container for \(bundleID)",
                details: ["stdout": text, "kind": kind.rawValue],
                recovery: "Check `xcrun simctl get_app_container <device> <bundle> <container>` manually"
            )
        }
        return path
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter SimctlRuntimeServiceTests
swift test --filter SimctlAppServiceTests
```

Expected: PASS; `SimctlRuntimeServiceTests` có `Executed 3 tests, with 0 failures`, `SimctlAppServiceTests` có `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Services/SimctlRuntimeService.swift Sources/OpenSimBridge/Services/SimctlAppService.swift Sources/OpenSimBridge/Services/SimctlPlistParser.swift Tests/OpenSimBridgeTests/SimctlRuntimeServiceTests.swift Tests/OpenSimBridgeTests/SimctlAppServiceTests.swift
git commit -m "feat(bridge): add runtime and app simctl services"
```

---

### Task 10: Log service với cursor và crash report scanner

**Files:**
- Create: `Sources/OpenSimBridge/Services/SimctlLogService.swift`
- Create: `Sources/OpenSimBridge/Services/CrashReportService.swift`
- Test: `Tests/OpenSimBridgeTests/SimctlLogServiceTests.swift`

**Interfaces:**
- Consumes: `SimctlExecuting`, `SimctlArguments.logShow`, `SimctlErrorMapper`, `LogPage`, `LogEntry`.
- Produces: `SimctlLogService(executor:timeout:)` conforms `LogControlling`; `LogCursor`, `LogCursorCodec`; `LogTimestamp`; `SimctlLogPayload`; `CrashReportService(devices:fileManager:)` conforms `CrashReportReading`; `CrashReportScanner.scan(directory:limit:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeTests/SimctlLogServiceTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

private let logLines = """
{"timestamp":"2026-10-20 10:00:00.000001+0700","messageType":"Default","subsystem":"com.apple.UIKit","category":"Application","processImagePath":"/Applications/Preferences.app/Preferences","eventMessage":"first"}
{"timestamp":"2026-10-20 10:00:00.000002+0700","messageType":"Info","subsystem":"com.apple.UIKit","category":"Application","processImagePath":"/Applications/Preferences.app/Preferences","eventMessage":"second"}
{"timestamp":"2026-10-20 10:00:00.000003+0700","messageType":"Error","subsystem":"com.apple.UIKit","category":"Application","processImagePath":"/Applications/Preferences.app/Preferences","eventMessage":"third"}
{"timestamp":"2026-10-20 10:00:00.000004+0700","messageType":"Fault","subsystem":"com.apple.UIKit","category":"Application","processImagePath":"/Applications/Preferences.app/Preferences","eventMessage":"fourth"}
{"timestamp":"2026-10-20 10:00:00.000005+0700","messageType":"Debug","subsystem":"com.apple.UIKit","category":"Application","processImagePath":"/Applications/Preferences.app/Preferences","eventMessage":"fifth"}
"""

final class SimctlLogServiceTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    func testFirstPageUsesLastFiveMinutes() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(logLines))
        let service = SimctlLogService(executor: executor, timeout: .seconds(5))
        let page = try await service.tailLogs(on: udid, cursor: nil, limit: 2, filter: "subsystem == \"com.apple.UIKit\"")
        XCTAssertEqual(page.entries.map(\.message), ["first", "second"])
        XCTAssertEqual(page.entries.map(\.level), [.notice, .info])
        XCTAssertNotNil(page.nextCursor)
        let commands = await executor.commands
        XCTAssertTrue(commands[0].arguments.contains("--last"))
        XCTAssertTrue(commands[0].arguments.contains("5m"))
    }

    func testSecondPageSkipsReturnedEntries() async throws {
        let executor = StubSimctlExecutor()
        await executor.enqueue(jsonOutput(logLines))
        await executor.enqueue(jsonOutput(logLines))
        let service = SimctlLogService(executor: executor, timeout: .seconds(5))
        let first = try await service.tailLogs(on: udid, cursor: nil, limit: 2, filter: nil)
        let second = try await service.tailLogs(on: udid, cursor: first.nextCursor, limit: 2, filter: nil)
        XCTAssertEqual(second.entries.map(\.message), ["third", "fourth"])
        let commands = await executor.commands
        XCTAssertTrue(commands[1].arguments.contains("--start"))
        XCTAssertFalse(commands[1].arguments.contains("--last"))
    }

    func testInvalidCursorIsRejectedBeforeRunningSimctl() async throws {
        let executor = StubSimctlExecutor()
        let service = SimctlLogService(executor: executor, timeout: .seconds(5))
        do {
            _ = try await service.tailLogs(on: udid, cursor: "not-a-cursor", limit: 2, filter: nil)
            XCTFail("expected invalid_argument")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "invalid_argument")
        }
        let commands = await executor.commands
        XCTAssertEqual(commands.count, 0)
    }

    func testCrashReportScannerSortsNewestFirst() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("opensim-crash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Preferences-2026-10-19-100000.ips")
        let new = root.appendingPathComponent("Safari-2026-10-20-100000.ips")
        try Data("old".utf8).write(to: old)
        try Data("new-data".utf8).write(to: new)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: new.path)

        let reports = try CrashReportScanner.scan(directory: root, limit: 10)
        XCTAssertEqual(reports.map(\.processName), ["Safari", "Preferences"])
        XCTAssertEqual(reports[0].sizeBytes, 8)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter SimctlLogServiceTests
```

Expected: FAIL với `cannot find type 'SimctlLogService' in scope`.

- [ ] **Step 3: Viết log và crash services**

Create `Sources/OpenSimBridge/Services/SimctlLogService.swift`:

```swift
import Foundation
import OpenSimCore

struct SimctlLogPayload: Decodable {
    let timestamp: String
    let messageType: String?
    let subsystem: String?
    let category: String?
    let processImagePath: String?
    let eventMessage: String?
    let formatString: String?
}

struct LogCursor: Codable, Sendable, Equatable {
    var timestampMicros: Int64
    var skip: Int
}

enum LogCursorCodec {
    static func encode(_ cursor: LogCursor) throws -> String {
        let data = try JSONEncoder().encode(cursor)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) throws -> LogCursor {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64),
              let cursor = try? JSONDecoder().decode(LogCursor.self, from: data),
              cursor.skip >= 0 else {
            throw OpenSimError.invalidArgument(
                "Invalid log cursor",
                recovery: "Omit --cursor to start a new page"
            )
        }
        return cursor
    }
}

enum LogTimestamp {
    static func parse(_ text: String) -> Date? {
        let formatter = makeFormatter(format: "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZ")
        if let date = formatter.date(from: text) {
            return date
        }
        let fallback = makeFormatter(format: "yyyy-MM-dd HH:mm:ssZZZZ")
        return fallback.date(from: text)
    }

    static func string(fromMicros micros: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(micros) / 1_000_000)
        let formatter = makeFormatter(format: "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZ")
        return formatter.string(from: date)
    }

    static func micros(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    }

    private static func makeFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}

public struct SimctlLogService: LogControlling {
    private let executor: any SimctlExecuting
    private let timeout: Duration

    public init(executor: any SimctlExecuting, timeout: Duration) {
        self.executor = executor
        self.timeout = timeout
    }

    public func tailLogs(
        on device: DeviceID,
        cursor: String?,
        limit: Int,
        filter: String?
    ) async throws -> LogPage {
        guard limit > 0 && limit <= 1_000 else {
            throw OpenSimError.invalidArgument("limit must be between 1 and 1000")
        }
        if let filter, filter.count > 2_000 {
            throw OpenSimError.invalidArgument("filter is too long")
        }
        let decodedCursor = try cursor.map(LogCursorCodec.decode)

        let command: SimctlCommand
        if let decodedCursor {
            command = SimctlArguments.logShow(
                device: device,
                since: LogTimestamp.string(fromMicros: decodedCursor.timestampMicros),
                last: nil,
                predicate: filter
            )
        } else {
            command = SimctlArguments.logShow(
                device: device,
                since: nil,
                last: "5m",
                predicate: filter
            )
        }
        let output = try await executor.run(command, timeout: timeout)
        try SimctlErrorMapper.requireSuccess(command: command, output: output)
        let entries = try parseEntries(output.stdout)
        return try paginate(entries: entries, cursor: decodedCursor, limit: limit)
    }

    private func parseEntries(_ data: Data) throws -> [LogEntry] {
        let text = String(decoding: data, as: UTF8.self)
        var entries: [LogEntry] = []
        for line in text.split(separator: "\n") {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }
            guard let payload = try? JSONDecoder().decode(SimctlLogPayload.self, from: Data(line.utf8)) else {
                continue
            }
            guard let timestamp = LogTimestamp.parse(payload.timestamp) else {
                continue
            }
            let process = payload.processImagePath.map { path in
                URL(fileURLWithPath: path).lastPathComponent
            }
            entries.append(LogEntry(
                timestamp: timestamp,
                level: level(from: payload.messageType),
                subsystem: emptyToNil(payload.subsystem),
                category: emptyToNil(payload.category),
                process: emptyToNil(process),
                message: payload.eventMessage ?? payload.formatString ?? ""
            ))
        }
        return entries.sorted { LogTimestamp.micros($0.timestamp) < LogTimestamp.micros($1.timestamp) }
    }

    private func paginate(entries: [LogEntry], cursor: LogCursor?, limit: Int) throws -> LogPage {
        var selected: [LogEntry] = []
        var lastIndex: Int?
        var skipped = 0
        let requiredSkip = cursor?.skip ?? 0
        for (index, entry) in entries.enumerated() {
            let micros = LogTimestamp.micros(entry.timestamp)
            if let cursor {
                if micros < cursor.timestampMicros {
                    continue
                }
                if micros == cursor.timestampMicros && skipped < requiredSkip {
                    skipped += 1
                    continue
                }
            }
            selected.append(entry)
            lastIndex = index
            if selected.count == limit {
                break
            }
        }
        guard let lastIndex, let last = selected.last else {
            let nextCursor = cursor.flatMap { try? LogCursorCodec.encode($0) }
            return LogPage(entries: [], nextCursor: nextCursor)
        }
        let lastMicros = LogTimestamp.micros(last.timestamp)
        let returnedAtTimestamp = entries[0..<(lastIndex + 1)].filter {
            LogTimestamp.micros($0.timestamp) == lastMicros
        }.count
        let next = LogCursor(timestampMicros: lastMicros, skip: returnedAtTimestamp)
        return LogPage(entries: selected, nextCursor: try LogCursorCodec.encode(next))
    }

    private func level(from messageType: String?) -> LogLevel {
        switch messageType?.lowercased() {
        case "debug":
            return .debug
        case "info":
            return .info
        case "error":
            return .error
        case "fault":
            return .fault
        case "warning":
            return .warning
        default:
            return .notice
        }
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}
```

Create `Sources/OpenSimBridge/Services/CrashReportService.swift`:

```swift
import Foundation
import OpenSimCore

public struct CrashReportScanner: Sendable {
    public static func scan(directory: URL, limit: Int) throws -> [CrashReport] {
        guard limit > 0 && limit <= 500 else {
            throw OpenSimError.invalidArgument("limit must be between 1 and 500")
        }
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey,
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        let allowed = Set(["ips", "crash", "panic"])
        let reports: [CrashReport] = urls.compactMap { url in
            guard allowed.contains(url.pathExtension.lowercased()) else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else {
                return nil
            }
            let name = url.deletingPathExtension().lastPathComponent
            let process = name.split(separator: "-").first.map(String.init) ?? name
            return CrashReport(
                id: url.path,
                processName: process,
                path: url.path,
                modifiedAt: values?.contentModificationDate ?? Date(timeIntervalSince1970: 0),
                sizeBytes: Int64(values?.fileSize ?? 0)
            )
        }
        return reports
            .sorted {
                if $0.modifiedAt == $1.modifiedAt {
                    return $0.path > $1.path
                }
                return $0.modifiedAt > $1.modifiedAt
            }
            .prefix(limit)
            .map { $0 }
    }
}

public struct CrashReportService: CrashReportReading {
    private let devices: any DeviceControlling
    private let fileManager: FileManager

    public init(devices: any DeviceControlling, fileManager: FileManager = .default) {
        self.devices = devices
        self.fileManager = fileManager
    }

    public func crashReports(on device: DeviceID, limit: Int) async throws -> [CrashReport] {
        let info = try await devices.device(device)
        guard let dataPath = info.dataPath else {
            throw OpenSimError(
                code: .deviceNotFound,
                message: "Device has no data path: \(device.rawValue)",
                details: ["udid": device.rawValue]
            )
        }
        let directory = URL(fileURLWithPath: dataPath)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("CrashReporter", isDirectory: true)
        return try CrashReportScanner.scan(directory: directory, limit: limit)
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter SimctlLogServiceTests
```

Expected: PASS; `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Services/SimctlLogService.swift Sources/OpenSimBridge/Services/CrashReportService.swift Tests/OpenSimBridgeTests/SimctlLogServiceTests.swift
git commit -m "feat(bridge): add log paging and crash report scanner"
```

### Task 11: Environment probe, capability evaluator và doctor service

**Files:**
- Create: `Sources/OpenSimBridge/Environment/XcodeLocator.swift`
- Create: `Sources/OpenSimBridge/Environment/FrameworkLocator.swift`
- Create: `Sources/OpenSimBridge/Environment/PrivateFrameworkProbe.swift`
- Create: `Sources/OpenSimBridge/Environment/DaemonStateProbe.swift`
- Create: `Sources/OpenSimBridge/Environment/CapabilityEvaluator.swift`
- Create: `Sources/OpenSimBridge/Environment/DoctorService.swift`
- Test: `Tests/OpenSimBridgeTests/CapabilityEvaluatorTests.swift`

**Interfaces:**
- Consumes: `XcodeInfo`, `FrameworkStatus`, `PrivateAPIStatus`, `DoctorReport`, `DaemonHealth`, `Runtime`, `Device`, `OpenSimPaths`, `PathPolicy`.
- Produces: `XcodeLocator.developerDir()`, `.version(developerDir:)`; `FrameworkLocator.status(developerDir:)`; `PrivateFrameworkProbe.probe(frameworks:)`; `DaemonStateProbe(paths:).health()`; `CapabilityEvaluator.evaluate(runtimes:frameworks:simctlAvailable:)`, `.runtimeCapability(runtimes:)`; `DoctorService` conforms `DoctorReporting`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeTests/CapabilityEvaluatorTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class CapabilityEvaluatorTests: XCTestCase {
    private let frameworks = FrameworkStatus(
        coreSimulatorPath: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework",
        simulatorKitPath: "/Applications/Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework",
        coreSimulatorPresent: true,
        simulatorKitPresent: true
    )

    func testNoRuntimeDisablesPlatformCapabilities() {
        let capabilities = CapabilityEvaluator.evaluate(runtimes: [], frameworks: frameworks, simctlAvailable: true)
        XCTAssertEqual(capabilities.render, .unavailable)
        XCTAssertEqual(capabilities.hid, .unavailable)
        XCTAssertEqual(capabilities.accessibility, .unavailable)
        XCTAssertEqual(capabilities.screenshot, .available)
        XCTAssertEqual(capabilities.video, .available)
        XCTAssertEqual(capabilities.watch, .unavailable)
        XCTAssertEqual(capabilities.tv, .unavailable)
        XCTAssertEqual(CapabilityEvaluator.runtimeCapability(runtimes: []), .unavailable)
    }

    func testWatchRuntimeEnablesWatchCapability() {
        let runtime = Runtime(
            id: RuntimeID("com.apple.CoreSimulator.SimRuntime.watchOS-27-0"),
            name: "watchOS 27.0",
            platform: .watchOS,
            version: "27.0",
            build: "24A434",
            isAvailable: true,
            path: nil
        )
        let capabilities = CapabilityEvaluator.evaluate(runtimes: [runtime], frameworks: frameworks, simctlAvailable: true)
        XCTAssertEqual(capabilities.watch, .available)
        XCTAssertEqual(capabilities.tv, .unavailable)
    }

    func testMissingSimctlMakesScreenshotUnknown() {
        let capabilities = CapabilityEvaluator.evaluate(runtimes: [], frameworks: frameworks, simctlAvailable: false)
        XCTAssertEqual(capabilities.screenshot, .unknown)
        XCTAssertEqual(capabilities.video, .unknown)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter CapabilityEvaluatorTests
```

Expected: FAIL với `cannot find 'CapabilityEvaluator' in scope`.

- [ ] **Step 3: Viết environment và doctor**

Create `Sources/OpenSimBridge/Environment/XcodeLocator.swift`:

```swift
import Foundation
import OpenSimCore

public struct XcodeLocator: Sendable {
    public init() {}

    public func developerDir() throws -> String {
        let result = try run(executable: "/usr/bin/xcode-select", arguments: ["-p"], environment: [:])
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !path.isEmpty else {
            throw OpenSimError(
                code: .xcodeNotFound,
                message: "Full Xcode was not found",
                details: ["stderr": result.stderr],
                recovery: "Install Xcode 27.1 and run `sudo xcode-select -s /Applications/Xcode.app`"
            )
        }
        return try PathPolicy.validateDeveloperDir(path)
    }

    public func version(developerDir: String) throws -> XcodeInfo {
        let result = try run(
            executable: "/usr/bin/xcodebuild",
            arguments: ["-version"],
            environment: ["DEVELOPER_DIR": developerDir]
        )
        guard result.status == 0 else {
            throw OpenSimError(
                code: .xcodeNotFound,
                message: "xcodebuild could not read the Xcode version",
                details: ["stderr": result.stderr],
                recovery: "Run `sudo xcode-select -s /Applications/Xcode.app` and retry"
            )
        }
        let lines = result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var version = ""
        var build = ""
        for line in lines {
            if line.hasPrefix("Xcode ") {
                version = String(line.dropFirst("Xcode ".count))
            }
            if line.hasPrefix("Build version ") {
                build = String(line.dropFirst("Build version ".count))
            }
        }
        guard !version.isEmpty else {
            throw OpenSimError(
                code: .unsupportedXcode,
                message: "Could not parse Xcode version",
                details: ["stdout": result.stdout]
            )
        }
        guard let major = Int(version.split(separator: ".").first ?? ""), major >= 27 else {
            throw OpenSimError(
                code: .unsupportedXcode,
                message: "Xcode 27 or newer is required; found \(version)",
                details: ["version": version, "build": build],
                recovery: "Select Xcode 27.1 with xcode-select"
            )
        }
        return XcodeInfo(
            path: developerDir,
            version: version,
            build: build,
            isFullXcode: developerDir.contains(".app/Contents/Developer")
        )
    }

    private func run(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if !environment.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
        let stderrData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: stdoutData, as: UTF8.self),
            String(decoding: stderrData, as: UTF8.self)
        )
    }
}
```

Create `Sources/OpenSimBridge/Environment/FrameworkLocator.swift`:

```swift
import Foundation
import OpenSimCore

public enum FrameworkLocator {
    public static func status(developerDir: String) -> FrameworkStatus {
        let contents = URL(fileURLWithPath: developerDir).deletingLastPathComponent()
        let simulatorKit = contents
            .appendingPathComponent("SharedFrameworks", isDirectory: true)
            .appendingPathComponent("SimulatorKit.framework", isDirectory: true)
        let coreSimulator = URL(fileURLWithPath: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework", isDirectory: true)
        return FrameworkStatus(
            coreSimulatorPath: coreSimulator.path,
            simulatorKitPath: simulatorKit.path,
            coreSimulatorPresent: FileManager.default.fileExists(atPath: coreSimulator.path),
            simulatorKitPresent: FileManager.default.fileExists(atPath: simulatorKit.path)
        )
    }
}
```

Create `Sources/OpenSimBridge/Environment/PrivateFrameworkProbe.swift`:

```swift
import Darwin
import Foundation
import OpenSimCore

public enum PrivateFrameworkProbe {
    public static func probe(frameworks: FrameworkStatus) -> PrivateAPIStatus {
        var notes: [String: String] = [
            "policy": "class existence only; no selectors are invoked",
        ]
        let coreLoaded = loadFramework(path: frameworks.coreSimulatorPath, notes: &notes, key: "coreSimulator")
        let kitLoaded = loadFramework(path: frameworks.simulatorKitPath, notes: &notes, key: "simulatorKit")
        return PrivateAPIStatus(
            coreSimulatorLoadable: coreLoaded,
            simulatorKitLoadable: kitLoaded,
            simDisplayViewClassFound: NSClassFromString("_TtC12SimulatorKit14SimDisplayView") != nil,
            simDeviceLegacyHIDClientClassFound: NSClassFromString("_TtC12SimulatorKit24SimDeviceLegacyHIDClient") != nil,
            simAccessibilityManagerClassFound: NSClassFromString("_TtC12SimulatorKit23SimAccessibilityManager") != nil,
            notes: notes
        )
    }

    private static func loadFramework(path: String?, notes: inout [String: String], key: String) -> Bool {
        guard let path, !path.isEmpty else {
            notes[key] = "framework path missing"
            return false
        }
        guard let bundle = Bundle(path: path), let executable = bundle.executablePath else {
            notes[key] = "bundle executable missing at \(path)"
            return false
        }
        guard dlopen(executable, RTLD_LAZY | RTLD_LOCAL) != nil else {
            let message = dlerror().map { String(cString: $0) } ?? "dlopen failed"
            notes[key] = message
            return false
        }        notes[key] = "loaded \(executable)"
        return true
    }
}
```

Create `Sources/OpenSimBridge/Environment/DaemonStateProbe.swift`:

```swift
import Darwin
import Foundation
import OpenSimCore

public struct DaemonStateProbe: Sendable {
    private let paths: OpenSimPaths

    public init(paths: OpenSimPaths) {
        self.paths = paths
    }

    public func health() -> DaemonHealth {
        let fileManager = FileManager.default
        let stateURL = paths.daemonStateFile
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return DaemonHealth(status: .notInstalled, pid: nil, port: nil, version: nil, tokenPermissionsOK: nil)
        }
        let attributes = try? fileManager.attributesOfItem(atPath: stateURL.path)
        let permissions = attributes?[.posixPermissions] as? NSNumber
        let permissionsOK = permissions?.intValue == 0o600
        guard let data = try? Data(contentsOf: stateURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pidNumber = object["pid"] as? NSNumber,
              let portNumber = object["port"] as? NSNumber else {
            return DaemonHealth(
                status: .unhealthy,
                pid: nil,
                port: nil,
                version: nil,
                tokenPermissionsOK: permissionsOK
            )
        }
        let pid = pidNumber.int32Value
        let alive = kill(pid, 0) == 0
        return DaemonHealth(
            status: alive ? .running : .notRunning,
            pid: pid,
            port: portNumber.intValue,
            version: object["version"] as? String,
            tokenPermissionsOK: permissionsOK
        )
    }
}
```

Create `Sources/OpenSimBridge/Environment/CapabilityEvaluator.swift`:

```swift
import OpenSimCore

public enum CapabilityEvaluator {
    public static func evaluate(
        runtimes: [Runtime],
        frameworks: FrameworkStatus,
        simctlAvailable: Bool
    ) -> BridgeCapabilities {
        let hasWatch = runtimes.contains { $0.platform == .watchOS && $0.isAvailable }
        let hasTV = runtimes.contains { $0.platform == .tvOS && $0.isAvailable }
        let simctl = simctlAvailable
        return BridgeCapabilities(
            render: .unavailable,
            hid: .unavailable,
            accessibility: .unavailable,
            screenshot: simctl ? .available : .unknown,
            video: simctl ? .available : .unknown,
            watch: hasWatch ? .available : .unavailable,
            tv: hasTV ? .available : .unavailable
        )
    }

    public static func runtimeCapability(runtimes: [Runtime]) -> Capability {
        runtimes.contains { $0.platform == .iOS && $0.isAvailable } ? .available : .unavailable
    }
}
```

Create `Sources/OpenSimBridge/Environment/DoctorService.swift`:

```swift
import Foundation
import OpenSimCore

public struct DoctorService: DoctorReporting {
    private let xcode: XcodeInfo
    private let frameworks: FrameworkStatus
    private let privateAPI: PrivateAPIStatus
    private let devices: any DeviceControlling
    private let runtimes: any RuntimeControlling
    private let daemonProbe: DaemonStateProbe

    public init(
        xcode: XcodeInfo,
        frameworks: FrameworkStatus,
        privateAPI: PrivateAPIStatus,
        devices: any DeviceControlling,
        runtimes: any RuntimeControlling,
        paths: OpenSimPaths
    ) {
        self.xcode = xcode
        self.frameworks = frameworks
        self.privateAPI = privateAPI
        self.devices = devices
        self.runtimes = runtimes
        self.daemonProbe = DaemonStateProbe(paths: paths)
    }

    public func doctorReport() async throws -> DoctorReport {
        let deviceList = try await devices.listDevices()
        let runtimeList = try await runtimes.listRuntimes()
        let capabilities = CapabilityEvaluator.evaluate(
            runtimes: runtimeList,
            frameworks: frameworks,
            simctlAvailable: true
        )
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let macOSVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let diskFree = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        let notes = [
            "bridge": "simctl is the preferred path for lifecycle, runtime, app and log",
            "screen": "ScreenControlling is provided by Plan 2",
            "input": "InputControlling is provided by Plan 2",
            "a11y": "AccessibilityReading is provided by Plan 2",
            "private_api": "Capabilities are probed by class existence only",
        ]
        return DoctorReport(
            generatedAt: Date(),
            macOSVersion: macOSVersion,
            architecture: DoctorService.architecture,
            xcode: xcode,
            frameworks: frameworks,
            privateAPI: privateAPI,
            capabilities: capabilities,
            runtime: CapabilityEvaluator.runtimeCapability(runtimes: runtimeList),
            daemon: daemonProbe.health(),
            diskFreeBytes: Int64(diskFree ?? 0),
            deviceCount: deviceList.count,
            runtimeCount: runtimeList.count,
            notes: notes
        )
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "unknown"
        #endif
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter CapabilityEvaluatorTests
```

Expected: PASS; `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Environment Tests/OpenSimBridgeTests/CapabilityEvaluatorTests.swift
git commit -m "feat(bridge): add environment probes and capability report"
```

---

### Task 12: Operation executor, parameter validation và SimctlBridge aggregate

**Files:**
- Create: `Sources/OpenSimCore/Protocol/OperationParameters.swift`
- Create: `Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift`
- Create: `Sources/OpenSimBridge/SimctlBridge.swift`
- Test: `Tests/OpenSimBridgeTests/BridgeOperationExecutorTests.swift`

**Interfaces:**
- Consumes: `OperationCatalog`, `Operation`, `OperationParameters`, services, `DoctorReporting`, `CrashReportReading`.
- Produces: `OperationParameters.values`, `.string`, `.optionalString`, `.bool`, `.int`, `.jsonArray`, `.jsonObject`, `.validated(against:)`; `BridgeOperationExecutor(bridge:crashReports:doctor:catalog:timeout:).execute(operation:parameters:) -> Data`; `SimctlBridge` conforms `SimulatorBridge`, `DoctorReporting`, `CrashReportReading`; `SimctlBridge.live(timeout:)`; `SimctlBridge.init(devices:runtimes:apps:logs:crashReports:doctor:capabilityProvider:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeTests/BridgeOperationExecutorTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

struct TestDoctor: DoctorReporting {
    func doctorReport() async throws -> DoctorReport {
        throw OpenSimError(code: .internalError, message: "not used")
    }
}

final class BridgeOperationExecutorTests: XCTestCase {
    private let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")

    private func makeBridge(executor: StubSimctlExecutor) -> SimctlBridge {
        let devices = SimctlDeviceService(executor: executor, timeout: .seconds(5))
        let runtimes = SimctlRuntimeService(executor: executor, timeout: .seconds(5))
        let apps = SimctlAppService(executor: executor, timeout: .seconds(5))
        let logs = SimctlLogService(executor: executor, timeout: .seconds(5))
        let crashes = CrashReportService(devices: devices)
        let doctor = TestDoctor()
        let capabilities = BridgeCapabilities(
            render: .unavailable,
            hid: .unavailable,
            accessibility: .unavailable,
            screenshot: .available,
            video: .available,
            watch: .unavailable,
            tv: .unavailable
        )
        return SimctlBridge(
            devices: devices,
            runtimes: runtimes,
            apps: apps,
            logs: logs,
            crashReports: crashes,
            doctor: doctor,
            capabilityProvider: { capabilities }
        )
    }

    func testDeviceListReturnsJSONArray() async throws {
        let stub = StubSimctlExecutor()
        await stub.enqueue(jsonOutput(deviceListJSON))
        let bridge = makeBridge(executor: stub)
        let executor = BridgeOperationExecutor(bridge: bridge)
        let data = try await executor.execute(operation: "device_list", parameters: [:])
        let devices = try OpenSimJSON.decoder().decode([Device].self, from: data)
        XCTAssertEqual(devices.map(\.id), [udid])
    }

    func testDestructiveOperationRequiresConfirmBeforeTouchingSimctl() async throws {
        let stub = StubSimctlExecutor()
        let bridge = makeBridge(executor: stub)
        let executor = BridgeOperationExecutor(bridge: bridge)
        do {
            _ = try await executor.execute(operation: "device_erase", parameters: ["device": udid.rawValue])
            XCTFail("expected confirmation_required")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "confirmation_required")
        }
        let commands = await stub.commands
        XCTAssertEqual(commands.count, 0)
    }

    func testUnknownParameterIsRejected() async throws {
        let stub = StubSimctlExecutor()
        let bridge = makeBridge(executor: stub)
        let executor = BridgeOperationExecutor(bridge: bridge)
        do {
            _ = try await executor.execute(operation: "device_list", parameters: ["unexpected": "value"])
            XCTFail("expected invalid_argument")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "invalid_argument")
        }
    }

    func testMissingRequiredParameterIsRejected() async throws {
        let stub = StubSimctlExecutor()
        let bridge = makeBridge(executor: stub)
        let executor = BridgeOperationExecutor(bridge: bridge)
        do {
            _ = try await executor.execute(operation: "app_uninstall", parameters: ["device": udid.rawValue, "confirm": "true"])
            XCTFail("expected invalid_argument")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "invalid_argument")
        }
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter BridgeOperationExecutorTests
```

Expected: FAIL với `cannot find type 'BridgeOperationExecutor' in scope`.

- [ ] **Step 3: Viết operation executor và bridge**

Create `Sources/OpenSimCore/Protocol/OperationParameters.swift`:

```swift
import Foundation

public struct OperationParameters: Sendable {
    public let values: [String: String]

    public init(_ values: [String: String]) {
        self.values = values
    }

    public func validated(against operation: Operation) throws -> OperationParameters {
        var allowed = Set(operation.parameters.map(\.name))
        if operation.destructive {
            allowed.insert("confirm")
        }
        for key in values.keys where !allowed.contains(key) {
            throw OpenSimError.invalidArgument(
                "Unknown parameter \(key) for \(operation.mcpName)",
                recovery: "Remove the parameter or use `--help`"
            )
        }
        for parameter in operation.parameters where parameter.required {
            guard let value = values[parameter.name], !value.isEmpty else {
                throw OpenSimError.invalidArgument(
                    "Missing required parameter \(parameter.name) for \(operation.mcpName)"
                )
            }
        }
        return self
    }

    public func string(_ name: String) throws -> String {
        guard let value = values[name], !value.isEmpty else {
            throw OpenSimError.invalidArgument("Missing required parameter \(name)")
        }
        return value
    }

    public func optionalString(_ name: String) -> String? {
        guard let value = values[name] else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func bool(_ name: String, default defaultValue: Bool) throws -> Bool {
        guard let value = optionalString(name) else {
            return defaultValue
        }
        switch value.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            throw OpenSimError.invalidArgument("Parameter \(name) must be a boolean")
        }
    }

    public func int(_ name: String, default defaultValue: Int?) throws -> Int {
        guard let value = optionalString(name) else {
            if let defaultValue {
                return defaultValue
            }
            throw OpenSimError.invalidArgument("Missing required parameter \(name)")
        }
        guard let parsed = Int(value) else {
            throw OpenSimError.invalidArgument("Parameter \(name) must be an integer")
        }
        return parsed
    }

    public func jsonArray(_ name: String) throws -> [String]? {
        guard let value = optionalString(name) else {
            return nil
        }
        guard let data = value.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            throw OpenSimError.invalidArgument("Parameter \(name) must be a JSON string array")
        }
        return array
    }

    public func jsonObject(_ name: String) throws -> [String: String]? {
        guard let value = optionalString(name) else {
            return nil
        }
        guard let data = value.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw OpenSimError.invalidArgument("Parameter \(name) must be a JSON string map")
        }
        return object
    }
}
```

Create `Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift`:

```swift
import Foundation
import OpenSimCore

public struct BridgeOperationExecutor: Sendable {
    public let bridge: any SimulatorBridge
    public let crashReports: (any CrashReportReading)?
    public let doctor: (any DoctorReporting)?
    public let catalog: OperationCatalog

    public init(
        bridge: any SimulatorBridge,
        crashReports: (any CrashReportReading)? = nil,
        doctor: (any DoctorReporting)? = nil,
        catalog: OperationCatalog = .plan1()
    ) {
        self.bridge = bridge
        self.crashReports = crashReports
        self.doctor = doctor
        self.catalog = catalog
    }

    public func execute(operation name: String, parameters: [String: String]) async throws -> Data {
        guard let operation = catalog.operation(forMCP: name) else {
            throw OpenSimError.invalidArgument("Unknown operation: \(name)")
        }
        let params = try OperationParameters(parameters).validated(against: operation)
        if operation.destructive, try params.bool("confirm", default: false) == false {
            throw OpenSimError.confirmationRequired(action: operation.mcpName)
        }

        switch name {
        case "device_list":
            var devices = try await bridge.devices.listDevices()
            if let platform = params.optionalString("platform") {
                devices = devices.filter { $0.platform.rawValue.caseInsensitiveCompare(platform) == .orderedSame }
            }
            if let state = params.optionalString("state") {
                let expected = Device.parseState(state)
                devices = devices.filter { $0.state == expected }
            }
            return try encode(devices)

        case "device_get", "device_status":
            let id = try await resolveDevice(params)
            return try encode(bridge.devices.device(id))

        case "device_create":
            let name = try params.string("name")
            let deviceType = try params.string("deviceType")
            let runtime = params.optionalString("runtime").map(RuntimeID.init)
            return try encode(bridge.devices.createDevice(name: name, deviceType: deviceType, runtime: runtime))

        case "device_clone":
            let id = try await resolveDevice(params)
            let name = try params.string("name")
            return try encode(bridge.devices.cloneDevice(id, name: name))

        case "device_boot":
            let id = try await resolveDevice(params)
            return try encode(bridge.devices.boot(id, wait: try params.bool("wait", default: false)))

        case "device_shutdown":
            let id = try await resolveDevice(params)
            return try encode(bridge.devices.shutdown(id, wait: try params.bool("wait", default: false)))

        case "device_erase":
            let id = try await resolveDevice(params)
            return try encode(bridge.devices.erase(id))

        case "device_delete":
            let id = try await resolveDevice(params)
            try await bridge.devices.delete(id)
            return try encode(OperationAck(ok: true, message: "Deleted device \(id.rawValue)"))

        case "device_rename":
            let id = try await resolveDevice(params)
            let name = try params.string("name")
            return try encode(bridge.devices.rename(id, to: name))

        case "runtime_list":
            var runtimes = try await bridge.runtimes.listRuntimes()
            if let platform = params.optionalString("platform") {
                runtimes = runtimes.filter { $0.platform.rawValue.caseInsensitiveCompare(platform) == .orderedSame }
            }
            return try encode(runtimes)

        case "runtime_install":
            let path = try params.string("path")
            return try encode(bridge.runtimes.installRuntime(at: path))

        case "runtime_delete":
            let id = try IdentifierValidation.validateRuntimeIdentifier(try params.string("identifier"))
            try await bridge.runtimes.deleteRuntime(id)
            return try encode(OperationAck(ok: true, message: "Deleted runtime \(id.rawValue)"))

        case "runtime_verify":
            let id = try IdentifierValidation.validateRuntimeIdentifier(try params.string("identifier"))
            try await bridge.runtimes.verifyRuntime(id)
            return try encode(OperationAck(ok: true, message: "Verified runtime \(id.rawValue)"))

        case "app_list":
            let device = try await resolveDevice(params)
            return try encode(bridge.apps.listApps(on: device, filter: params.optionalString("filter")))

        case "app_install":
            let device = try await resolveDevice(params)
            let path = try params.string("path")
            return try encode(bridge.apps.installApp(on: device, at: path))

        case "app_uninstall":
            let device = try await resolveDevice(params)
            let bundleID = try params.string("bundleID")
            try await bridge.apps.uninstallApp(on: device, bundleID: bundleID)
            return try encode(OperationAck(ok: true, message: "Uninstalled \(bundleID)"))

        case "app_launch":
            let device = try await resolveDevice(params)
            let bundleID = try params.string("bundleID")
            let args = try params.jsonArray("args") ?? []
            let environment = try params.jsonObject("env") ?? [:]
            let pid = try await bridge.apps.launchApp(
                on: device,
                bundleID: bundleID,
                args: args,
                environment: environment
            )
            return try encode(AppLaunchResult(bundleID: bundleID, pid: pid))

        case "app_terminate":
            let device = try await resolveDevice(params)
            let bundleID = try params.string("bundleID")
            try await bridge.apps.terminateApp(on: device, bundleID: bundleID)
            return try encode(OperationAck(ok: true, message: "Terminated \(bundleID)"))

        case "app_info":
            let device = try await resolveDevice(params)
            return try encode(bridge.apps.appInfo(on: device, bundleID: try params.string("bundleID")))

        case "app_container":
            let device = try await resolveDevice(params)
            let bundleID = try params.string("bundleID")
            let kindRaw = params.optionalString("kind") ?? "app"
            guard let kind = ContainerKind(rawValue: kindRaw) else {
                throw OpenSimError.invalidArgument("kind must be app, data, or group")
            }
            let path = try await bridge.apps.containerPath(on: device, bundleID: bundleID, kind: kind)
            return try encode(ContainerPathResult(bundleID: bundleID, kind: kind, path: path))

        case "log_tail":
            let device = try await resolveDevice(params)
            let limit = try params.int("limit", default: 100)
            guard limit > 0 && limit <= 1_000 else {
                throw OpenSimError.invalidArgument("limit must be between 1 and 1000")
            }
            let page = try await bridge.logs.tailLogs(
                on: device,
                cursor: params.optionalString("cursor"),
                limit: limit,
                filter: params.optionalString("filter")
            )
            return try encode(page)

        case "log_crash":
            let device = try await resolveDevice(params)
            guard let crashReports else {
                throw OpenSimError.capabilityUnavailable("crash_reports")
            }
            let limit = try params.int("limit", default: 20)
            return try encode(try await crashReports.crashReports(on: device, limit: limit))

        case "doctor_report":
            guard let doctor else {
                throw OpenSimError.capabilityUnavailable("doctor")
            }
            return try encode(try await doctor.doctorReport())

        default:
            throw OpenSimError(
                code: .internalError,
                message: "Catalog operation has no executor: \(name)"
            )
        }
    }

    private func resolveDevice(_ params: OperationParameters) async throws -> DeviceID {
        let query = params.optionalString("device")
        let devices = try await bridge.devices.listDevices()
        return try DeviceResolver.resolve(query: query, in: devices).id
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try OpenSimJSON.encoder(pretty: false).encode(value)
    }
}
```

Create `Sources/OpenSimBridge/SimctlBridge.swift`:

```swift
import Foundation
import OpenSimCore

public struct SimctlBridge: SimulatorBridge, DoctorReporting, CrashReportReading {
    public let devices: any DeviceControlling
    public let runtimes: any RuntimeControlling
    public let apps: any AppControlling
    public let logs: any LogControlling
    public let screen: (any ScreenControlling)?
    public let input: (any InputControlling)?
    public let accessibility: (any AccessibilityReading)?

    private let crashService: any CrashReportReading
    private let doctorService: any DoctorReporting
    private let capabilityProvider: @Sendable () async -> BridgeCapabilities

    public init(
        devices: any DeviceControlling,
        runtimes: any RuntimeControlling,
        apps: any AppControlling,
        logs: any LogControlling,
        crashReports: any CrashReportReading,
        doctor: any DoctorReporting,
        capabilityProvider: @escaping @Sendable () async -> BridgeCapabilities
    ) {
        self.devices = devices
        self.runtimes = runtimes
        self.apps = apps
        self.logs = logs
        self.screen = nil
        self.input = nil
        self.accessibility = nil
        self.crashService = crashReports
        self.doctorService = doctor
        self.capabilityProvider = capabilityProvider
    }

    public var capabilities: BridgeCapabilities {
        get async {
            await capabilityProvider()
        }
    }

    public func doctorReport() async throws -> DoctorReport {
        try await doctorService.doctorReport()
    }

    public func crashReports(on device: DeviceID, limit: Int) async throws -> [CrashReport] {
        try await crashService.crashReports(on: device, limit: limit)
    }

    public static func live(timeout: Duration = .seconds(60)) throws -> SimctlBridge {
        let locator = XcodeLocator()
        let developerDir = try locator.developerDir()
        let xcode = try locator.version(developerDir: developerDir)
        let frameworks = FrameworkLocator.status(developerDir: developerDir)
        let privateAPI = PrivateFrameworkProbe.probe(frameworks: frameworks)
        let executor = ProcessSimctlExecutor()
        let devices = SimctlDeviceService(executor: executor, timeout: timeout)
        let runtimes = SimctlRuntimeService(executor: executor, timeout: timeout)
        let apps = SimctlAppService(executor: executor, timeout: timeout)
        let logs = SimctlLogService(executor: executor, timeout: timeout)
        let crashes = CrashReportService(devices: devices)
        let paths = OpenSimPaths()
        let doctor = DoctorService(
            xcode: xcode,
            frameworks: frameworks,
            privateAPI: privateAPI,
            devices: devices,
            runtimes: runtimes,
            paths: paths
        )
        let runtimesForCapabilities: any RuntimeControlling = runtimes
        let capabilityProvider: @Sendable () async -> BridgeCapabilities = {
            let list = (try? await runtimesForCapabilities.listRuntimes()) ?? []
            return CapabilityEvaluator.evaluate(
                runtimes: list,
                frameworks: frameworks,
                simctlAvailable: true
            )
        }
        return SimctlBridge(
            devices: devices,
            runtimes: runtimes,
            apps: apps,
            logs: logs,
            crashReports: crashes,
            doctor: doctor,
            capabilityProvider: capabilityProvider
        )
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter BridgeOperationExecutorTests
```

Expected: PASS; `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCore/Protocol/OperationParameters.swift Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift Sources/OpenSimBridge/SimctlBridge.swift Tests/OpenSimBridgeTests/BridgeOperationExecutorTests.swift
git commit -m "feat(bridge): add operation executor and simctl bridge"
```

### Task 13: CLI output, table, backend và exit code

**Files:**
- Modify: `Package.swift` (thêm executable `opensim`, target `OpenSimCLI`, `OpenSimCLITests`, dependency `swift-argument-parser`)
- Create: `Sources/OpenSimCLI/Output/Table.swift`
- Create: `Sources/OpenSimCLI/Output/OutputRenderer.swift`
- Create: `Sources/OpenSimCLI/Runtime/CommandBackend.swift`
- Create: `Sources/OpenSimCLI/Runtime/CLIRuntime.swift`
- Create: `Sources/OpenSimCLI/Commands/GlobalOptions.swift`
- Create: `Sources/OpenSimCLI/OpenSimCommand.swift`
- Test: `Tests/OpenSimCLITests/OutputRendererTests.swift`
- Test: `Tests/OpenSimCLITests/ExitCodeTests.swift`

**Interfaces:**
- Consumes: `Envelope`, `OpenSimJSON`, `OpenSimError`, `OpenSimExitCode`, `BridgeOperationExecutor`, `SimctlBridge`.
- Produces: `Table(headers:rows:).rendered()`; `OutputRenderer.success(_:table:durationMs:)`, `.failure(_:durationMs:)`; `CommandBackend`; `DirectCommandBackend`; `CLIRuntime.makeBackend(_:)`, `.run(globals:table:exitCode:body:)`; `GlobalOptions`; root `OpenSimCommand`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimCLITests/OutputRendererTests.swift`:

```swift
import XCTest
@testable import OpenSimCLI
@testable import OpenSimCore

final class LockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func append(_ text: String) {
        lock.lock()
        value += text
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class OutputRendererTests: XCTestCase {
    func testTableAlignment() {
        let table = Table(headers: ["A", "BB"], rows: [["1", "22"], ["333", "4"]])
        XCTAssertEqual(table.rendered(), "A    BB\n1    22\n333  4")
    }

    func testJSONSuccessEnvelope() throws {
        let output = LockedText()
        let errorOutput = LockedText()
        let renderer = OutputRenderer(
            json: true,
            writeOut: { output.append($0) },
            writeErr: { errorOutput.append($0) }
        )
        try renderer.success(["one", "two"], table: nil, durationMs: 9)
        let data = try XCTUnwrap(output.text.data(using: .utf8))
        let envelope = try OpenSimJSON.decoder().decode(Envelope<[String]>.self, from: data)
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.data, ["one", "two"])
        XCTAssertEqual(envelope.meta.durationMs, 9)
        XCTAssertEqual(errorOutput.text, "")
    }

    func testHumanFailureGoesToStderr() {
        let output = LockedText()
        let errorOutput = LockedText()
        let renderer = OutputRenderer(
            json: false,
            writeOut: { output.append($0) },
            writeErr: { errorOutput.append($0) }
        )
        renderer.failure(.invalidArgument("bad value", recovery: "Use a good value"), durationMs: 1)
        XCTAssertEqual(output.text, "")
        XCTAssertTrue(errorOutput.text.contains("error[invalid_argument]"))
        XCTAssertTrue(errorOutput.text.contains("Use a good value"))
    }

    func testJSONFailureEnvelope() throws {
        let errorOutput = LockedText()
        let renderer = OutputRenderer(
            json: true,
            writeOut: { _ in },
            writeErr: { errorOutput.append($0) }
        )
        renderer.failure(.deviceNotFound(DeviceID("11111111-1111-1111-1111-111111111111")), durationMs: 2)
        let data = try XCTUnwrap(errorOutput.text.data(using: .utf8))
        let envelope = try OpenSimJSON.decoder().decode(Envelope<EmptyPayload>.self, from: data)
        XCTAssertFalse(envelope.ok)
        XCTAssertEqual(envelope.error?.code, "device_not_found")
    }
}
```

Create `Tests/OpenSimCLITests/ExitCodeTests.swift`:

```swift
import XCTest
@testable import OpenSimCLI
@testable import OpenSimCore

final class ExitCodeTests: XCTestCase {
    func testExitCodesMatchCLIContract() {
        XCTAssertEqual(OpenSimExitCode.success.rawValue, 0)
        XCTAssertEqual(OpenSimExitCode.usage.rawValue, 2)
        XCTAssertEqual(OpenSimExitCode.notFound.rawValue, 3)
        XCTAssertEqual(OpenSimExitCode.conflict.rawValue, 4)
        XCTAssertEqual(OpenSimExitCode.unsupported.rawValue, 5)
        XCTAssertEqual(OpenSimExitCode.permission.rawValue, 6)
        XCTAssertEqual(OpenSimExitCode.confirmationRequired.rawValue, 7)
        XCTAssertEqual(OpenSimExitCode.internalError.rawValue, 10)
    }

    func testErrorToExitCode() {
        XCTAssertEqual(OpenSimExitCode.forError("invalid_argument"), .usage)
        XCTAssertEqual(OpenSimExitCode.forError("device_not_found"), .notFound)
        XCTAssertEqual(OpenSimExitCode.forError("lease_conflict"), .conflict)
        XCTAssertEqual(OpenSimExitCode.forError("capability_unavailable"), .unsupported)
        XCTAssertEqual(OpenSimExitCode.forError("xcode_not_found"), .permission)
        XCTAssertEqual(OpenSimExitCode.forError("confirmation_required"), .confirmationRequired)
        XCTAssertEqual(OpenSimExitCode.forError("internal"), .internalError)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter OutputRendererTests
swift test --filter ExitCodeTests
```

Expected: FAIL với `cannot find type 'Table' in scope`.

- [ ] **Step 3: Viết CLI foundation**

Modify `Package.swift` để thêm dependency và executable target:

```swift
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
```

Thêm vào `products`:

```swift
        .executable(name: "opensim", targets: ["OpenSimCLI"]),
```

Thêm vào `targets`:

```swift
        .executableTarget(
            name: "OpenSimCLI",
            dependencies: [
                "OpenSimCore",
                "OpenSimBridge",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "OpenSimCLITests",
            dependencies: [
                "OpenSimCLI",
                "OpenSimCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
```

Create `Sources/OpenSimCLI/Output/Table.swift`:

```swift
import Foundation

public struct Table: Sendable, Equatable {
    public var headers: [String]
    public var rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }

    public func rendered() -> String {
        guard !headers.isEmpty else {
            return rows.map { $0.joined(separator: "  ") }.joined(separator: "\n")
        }
        let widths = headers.indices.map { index in
            ([headers] + rows)
                .map { row in row.indices.contains(index) ? row[index].count : 0 }
                .max() ?? 0
        }
        func line(_ row: [String]) -> String {
            let text = headers.indices.map { index in
                let value = row.indices.contains(index) ? row[index] : ""
                return value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }
            .joined(separator: "  ")
            var trimmed = text
            while trimmed.hasSuffix(" ") {
                trimmed.removeLast()
            }
            return trimmed
        }
        return ([line(headers)] + rows.map(line)).joined(separator: "\n")
    }
}
```

Create `Sources/OpenSimCLI/Output/OutputRenderer.swift`:

```swift
import Foundation
import OpenSimCore

public struct OutputRenderer: Sendable {
    public let json: Bool
    private let writeOut: @Sendable (String) -> Void
    private let writeErr: @Sendable (String) -> Void

    public init(
        json: Bool,
        writeOut: @escaping @Sendable (String) -> Void = { text in
            FileHandle.standardOutput.write(Data(text.utf8))
        },
        writeErr: @escaping @Sendable (String) -> Void = { text in
            FileHandle.standardError.write(Data(text.utf8))
        }
    ) {
        self.json = json
        self.writeOut = writeOut
        self.writeErr = writeErr
    }

    public func success<T: Codable & Sendable>(
        _ data: T,
        table: Table?,
        durationMs: Int
    ) throws {
        if json {
            let envelope = Envelope<T>.success(
                data,
                requestId: RequestID.make(),
                durationMs: durationMs
            )
            let encoded = try OpenSimJSON.encoder(pretty: true).encode(envelope)
            writeOut(String(decoding: encoded, as: UTF8.self) + "\n")
            return
        }
        if let table {
            writeOut(table.rendered() + "\n")
        } else {
            writeOut(String(describing: data) + "\n")
        }
    }

    public func failure(_ error: OpenSimError, durationMs: Int) {
        if json {
            let envelope = Envelope<EmptyPayload>.failure(
                error,
                requestId: RequestID.make(),
                durationMs: durationMs
            )
            if let encoded = try? OpenSimJSON.encoder(pretty: true).encode(envelope) {
                writeErr(String(decoding: encoded, as: UTF8.self) + "\n")
            }
            return
        }
        writeErr("error[\(error.code)]: \(error.message)\n")
        if let recovery = error.recovery {
            writeErr("recovery: \(recovery)\n")
        }
    }
}
```

Create `Sources/OpenSimCLI/Runtime/CommandBackend.swift`:

```swift
import Foundation
import OpenSimBridge
import OpenSimCore

public protocol CommandBackend: Sendable {
    func execute<T: Decodable & Sendable>(
        _ operation: String,
        parameters: [String: String],
        as type: T.Type
    ) async throws -> T
}

public struct DirectCommandBackend: CommandBackend {
    private let executor: BridgeOperationExecutor

    public init(executor: BridgeOperationExecutor) {
        self.executor = executor
    }

    public func execute<T: Decodable & Sendable>(
        _ operation: String,
        parameters: [String: String],
        as type: T.Type
    ) async throws -> T {
        let data = try await executor.execute(operation: operation, parameters: parameters)
        return try OpenSimJSON.decoder().decode(T.self, from: data)
    }
}
```

Create `Sources/OpenSimCLI/Commands/GlobalOptions.swift`:

```swift
import ArgumentParser
import OpenSimCore

public struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Device UDID or name")
    public var device: String?

    @Option(name: .long, help: "Timeout in seconds")
    public var timeout: Int = 60

    @Flag(name: .long, help: "Emit a JSON envelope")
    public var json: Bool = false

    @Flag(name: .long, help: "Confirm destructive operations")
    public var yes: Bool = false

    public init() {}

    public func validate() throws {
        guard timeout > 0 && timeout <= 3_600 else {
            throw OpenSimError.invalidArgument(
                "timeout must be between 1 and 3600 seconds"
            )
        }
    }

    public func parameters(_ base: [String: String] = [:]) -> [String: String] {
        var values = base
        if let device, !device.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values["device"] = device
        }
        return values
    }
}
```

Create `Sources/OpenSimCLI/Runtime/CLIRuntime.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimBridge
import OpenSimCore

public enum CLIRuntime {
    public static func makeBackend(_ globals: GlobalOptions) throws -> any CommandBackend {
        try globals.validate()
        let bridge = try SimctlBridge.live(timeout: .seconds(globals.timeout))
        let executor = BridgeOperationExecutor(
            bridge: bridge,
            crashReports: bridge,
            doctor: bridge
        )
        return DirectCommandBackend(executor: executor)
    }

    public static func run<T: Codable & Sendable>(
        globals: GlobalOptions,
        table: @escaping @Sendable (T) -> Table,
        exitCode: @escaping @Sendable (T) -> Int32 = { _ in 0 },
        body: @Sendable (any CommandBackend) async throws -> T
    ) async throws -> T {
        let renderer = OutputRenderer(json: globals.json)
        let started = Date()
        do {
            let backend = try makeBackend(globals)
            let value = try await body(backend)
            let duration = Int(Date().timeIntervalSince(started) * 1_000)
            try renderer.success(value, table: table(value), durationMs: duration)
            let code = exitCode(value)
            if code != 0 {
                throw ExitCode(code)
            }
            return value
        } catch let error as OpenSimError {
            let duration = Int(Date().timeIntervalSince(started) * 1_000)
            renderer.failure(error, durationMs: duration)
            throw ExitCode(OpenSimExitCode.forError(error.code).rawValue)
        } catch let code as ExitCode {
            throw code
        } catch {
            let duration = Int(Date().timeIntervalSince(started) * 1_000)
            let mapped = OpenSimError(
                code: .internalError,
                message: String(describing: error)
            )
            renderer.failure(mapped, durationMs: duration)
            throw ExitCode(OpenSimExitCode.internalError.rawValue)
        }
    }
}
```

Create `Sources/OpenSimCLI/OpenSimCommand.swift`:

```swift
import ArgumentParser
import OpenSimCore

@main
public struct OpenSimCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "opensim",
        abstract: "Control Apple simulators from the command line",
        version: OpenSimVersion.version,
        subcommands: []
    )

    public init() {}
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter OutputRendererTests
swift test --filter ExitCodeTests
swift build
```

Expected: PASS; `OutputRendererTests` có `Executed 4 tests, with 0 failures`; `swift build` kết thúc với `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCLI Tests/OpenSimCLITests/OutputRendererTests.swift Tests/OpenSimCLITests/ExitCodeTests.swift
git commit -m "feat(cli): add output rendering and command backend"
```

---

### Task 14: Root command và nhóm device

**Files:**
- Modify: `Sources/OpenSimCLI/OpenSimCommand.swift`
- Create: `Sources/OpenSimCLI/Commands/DeviceCommand.swift`
- Test: `Tests/OpenSimCLITests/CommandParsingTests.swift`

**Interfaces:**
- Consumes: `CLIRuntime.run`, `GlobalOptions`, `Device`, `OperationAck`.
- Produces: `DeviceCommand` với `list`, `get`, `create`, `clone`, `boot`, `shutdown`, `erase`, `delete`, `rename`, `status`; root command đăng ký `DeviceCommand`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimCLITests/CommandParsingTests.swift`:

```swift
import ArgumentParser
import XCTest
@testable import OpenSimCLI

final class CommandParsingTests: XCTestCase {
    func testParsesDeviceListAtLeaf() throws {
        let command = try OpenSimCommand.parseAsRoot(["device", "list", "--json"])
        let list = try XCTUnwrap(command as? DeviceListCommand)
        XCTAssertTrue(list.globals.json)
    }

    func testParsesDeviceBootWait() throws {
        let command = try OpenSimCommand.parseAsRoot(["device", "boot", "--device", "iPhone Air", "--wait"])
        let boot = try XCTUnwrap(command as? DeviceBootCommand)
        XCTAssertTrue(boot.wait)
        XCTAssertEqual(boot.globals.device, "iPhone Air")
    }

    func testParsesDestructiveConfirmationFlag() throws {
        let command = try OpenSimCommand.parseAsRoot(["device", "delete", "--yes"])
        let delete = try XCTUnwrap(command as? DeviceDeleteCommand)
        XCTAssertTrue(delete.globals.yes)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter CommandParsingTests
```

Expected: FAIL với `cannot find type 'DeviceListCommand' in scope`.

- [ ] **Step 3: Viết root và device commands**

Modify `Sources/OpenSimCLI/OpenSimCommand.swift`:

```swift
import ArgumentParser
import OpenSimCore

@main
public struct OpenSimCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "opensim",
        abstract: "Control Apple simulators from the command line",
        version: OpenSimVersion.version,
        subcommands: [
            DeviceCommand.self,
        ]
    )

    public init() {}
}
```

Create `Sources/OpenSimCLI/Commands/DeviceCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimCore

public struct DeviceCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "device",
        abstract: "Manage simulator devices",
        subcommands: [
            DeviceListCommand.self,
            DeviceGetCommand.self,
            DeviceCreateCommand.self,
            DeviceCloneCommand.self,
            DeviceBootCommand.self,
            DeviceShutdownCommand.self,
            DeviceEraseCommand.self,
            DeviceDeleteCommand.self,
            DeviceRenameCommand.self,
            DeviceStatusCommand.self,
        ]
    )

    public init() {}
}

private func deviceTable(_ device: Device) -> Table {
    Table(
        headers: ["FIELD", "VALUE"],
        rows: [
            ["udid", device.id.rawValue],
            ["name", device.name],
            ["platform", device.platform.rawValue],
            ["deviceType", device.deviceType],
            ["runtime", device.runtime.rawValue],
            ["state", device.state.rawValue],
            ["available", device.isAvailable ? "yes" : "no"],
            ["dataPath", device.dataPath ?? ""],
        ]
    )
}

public struct DeviceListCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "list", abstract: "List devices")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Filter by platform")
    public var platform: String?

    @Option(name: .long, help: "Filter by state")
    public var state: String?

    public init() {}

    public func run() async throws {
        var parameters: [String: String] = [:]
        if let platform {
            parameters["platform"] = platform
        }
        if let state {
            parameters["state"] = state
        }
        _ = try await CLIRuntime.run(globals: globals, table: { devices in
            Table(
                headers: ["UDID", "NAME", "PLATFORM", "RUNTIME", "STATE", "AVAILABLE"],
                rows: devices.map {
                    [$0.id.rawValue, $0.name, $0.platform.rawValue, $0.runtime.rawValue, $0.state.rawValue, $0.isAvailable ? "yes" : "no"]
                }
            )
        }) { backend in
            try await backend.execute("device_list", parameters: parameters, as: [Device].self)
        }
    }
}

public struct DeviceGetCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "get", abstract: "Get one device")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_get", parameters: globals.parameters(), as: Device.self)
        }
    }
}

public struct DeviceCreateCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a device")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Device name")
    public var name: String

    @Option(name: .long, help: "Device type identifier")
    public var type: String

    @Option(name: .long, help: "Runtime identifier")
    public var runtime: String?

    public init() {}

    public func run() async throws {
        var parameters = ["name": name, "deviceType": type]
        if let runtime {
            parameters["runtime"] = runtime
        }
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_create", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceCloneCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "clone", abstract: "Clone a device")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "New device name")
    public var name: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["name": name])
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_clone", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceBootCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "boot", abstract: "Boot a device")

    @OptionGroup public var globals: GlobalOptions

    @Flag(name: .long, help: "Wait until the device is booted")
    public var wait: Bool = false

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["wait": wait ? "true" : "false"])
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_boot", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceShutdownCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "shutdown", abstract: "Shut down a device")

    @OptionGroup public var globals: GlobalOptions

    @Flag(name: .long, help: "Wait until the device is shut down")
    public var wait: Bool = false

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["wait": wait ? "true" : "false"])
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_shutdown", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceEraseCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "erase", abstract: "Erase a device")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["confirm": globals.yes ? "true" : "false"])
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_erase", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceDeleteCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a device")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["confirm": globals.yes ? "true" : "false"])
        _ = try await CLIRuntime.run(globals: globals, table: { ack in
            Table(headers: ["RESULT", "MESSAGE"], rows: [[ack.ok ? "ok" : "failed", ack.message ?? ""]])
        }) { backend in
            try await backend.execute("device_delete", parameters: parameters, as: OperationAck.self)
        }
    }
}

public struct DeviceRenameCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "rename", abstract: "Rename a device")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "New device name")
    public var name: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["name": name])
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_rename", parameters: parameters, as: Device.self)
        }
    }
}

public struct DeviceStatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "status", abstract: "Show device status")

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        _ = try await CLIRuntime.run(globals: globals, table: deviceTable) { backend in
            try await backend.execute("device_status", parameters: globals.parameters(), as: Device.self)
        }
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter CommandParsingTests
```

Expected: PASS; `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCLI/OpenSimCommand.swift Sources/OpenSimCLI/Commands/DeviceCommand.swift Tests/OpenSimCLITests/CommandParsingTests.swift
git commit -m "feat(cli): add root command and device group"
```

### Task 15: Nhóm runtime và app

**Files:**
- Modify: `Sources/OpenSimCLI/OpenSimCommand.swift`
- Create: `Sources/OpenSimCLI/Commands/RuntimeCommand.swift`
- Create: `Sources/OpenSimCLI/Commands/AppCommand.swift`
- Modify: `Tests/OpenSimCLITests/CommandParsingTests.swift`

**Interfaces:**
- Consumes: `CLIRuntime.run`, `Runtime`, `AppInfo`, `OperationAck`, `AppLaunchResult`, `ContainerPathResult`.
- Produces: `RuntimeCommand` với `list`, `install`, `delete`, `verify`; `AppCommand` với `list`, `install`, `uninstall`, `launch`, `terminate`, `info`, `container`; root command đăng ký hai nhóm.

- [ ] **Step 1: Viết test thất bại**

Append vào `Tests/OpenSimCLITests/CommandParsingTests.swift` trước dấu `}` cuối file:

```swift
    func testParsesRuntimeListPlatform() throws {
        let command = try OpenSimCommand.parseAsRoot(["runtime", "list", "--platform", "iOS"])
        let list = try XCTUnwrap(command as? RuntimeListCommand)
        XCTAssertEqual(list.platform, "iOS")
    }

    func testParsesAppLaunchEnvironment() throws {
        let command = try OpenSimCommand.parseAsRoot([
            "app", "launch", "com.apple.Preferences",
            "--device", "iPhone Air",
            "--env", "OS_ACTIVITY_MODE=disable",
        ])
        let launch = try XCTUnwrap(command as? AppLaunchCommand)
        XCTAssertEqual(launch.bundleID, "com.apple.Preferences")
        XCTAssertEqual(launch.environment, ["OS_ACTIVITY_MODE=disable"])
    }

    func testParsesAppContainerKind() throws {
        let command = try OpenSimCommand.parseAsRoot(["app", "container", "com.apple.Preferences", "--kind", "data"])
        let container = try XCTUnwrap(command as? AppContainerCommand)
        XCTAssertEqual(container.kind, "data")
    }
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter CommandParsingTests
```

Expected: FAIL với `cannot find type 'RuntimeListCommand' in scope`.

- [ ] **Step 3: Viết runtime và app commands**

Modify `Sources/OpenSimCLI/OpenSimCommand.swift` thành:

```swift
import ArgumentParser
import OpenSimCore

@main
public struct OpenSimCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "opensim",
        abstract: "Control Apple simulators from the command line",
        version: OpenSimVersion.version,
        subcommands: [
            DeviceCommand.self,
            RuntimeCommand.self,
            AppCommand.self,
        ]
    )

    public init() {}
}
```

Create `Sources/OpenSimCLI/Commands/RuntimeCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimCore

public struct RuntimeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "runtime",
        abstract: "Manage simulator runtimes",
        subcommands: [
            RuntimeListCommand.self,
            RuntimeInstallCommand.self,
            RuntimeDeleteCommand.self,
            RuntimeVerifyCommand.self,
        ]
    )

    public init() {}
}

private func runtimeTable(_ runtime: Runtime) -> Table {
    Table(
        headers: ["FIELD", "VALUE"],
        rows: [
            ["identifier", runtime.id.rawValue],
            ["name", runtime.name],
            ["platform", runtime.platform.rawValue],
            ["version", runtime.version],
            ["build", runtime.build],
            ["available", runtime.isAvailable ? "yes" : "no"],
            ["path", runtime.path ?? ""],
        ]
    )
}

private func ackTable(_ ack: OperationAck) -> Table {
    Table(headers: ["RESULT", "MESSAGE"], rows: [[ack.ok ? "ok" : "failed", ack.message ?? ""]])
}

public struct RuntimeListCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "list", abstract: "List runtimes")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Filter by platform")
    public var platform: String?

    public init() {}

    public func run() async throws {
        var parameters: [String: String] = [:]
        if let platform {
            parameters["platform"] = platform
        }
        _ = try await CLIRuntime.run(globals: globals, table: { runtimes in
            Table(
                headers: ["IDENTIFIER", "NAME", "PLATFORM", "VERSION", "BUILD", "AVAILABLE", "PATH"],
                rows: runtimes.map {
                    [$0.id.rawValue, $0.name, $0.platform.rawValue, $0.version, $0.build, $0.isAvailable ? "yes" : "no", $0.path ?? ""]
                }
            )
        }) { backend in
            try await backend.execute("runtime_list", parameters: parameters, as: [Runtime].self)
        }
    }
}

public struct RuntimeInstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "install", abstract: "Install a runtime image")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Path to a .dmg or .simruntime")
    public var path: String

    public init() {}

    public func run() async throws {
        _ = try await CLIRuntime.run(globals: globals, table: runtimeTable) { backend in
            try await backend.execute("runtime_install", parameters: ["path": path], as: Runtime.self)
        }
    }
}

public struct RuntimeDeleteCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a runtime")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Runtime identifier")
    public var identifier: String

    public init() {}

    public func run() async throws {
        let parameters = ["identifier": identifier, "confirm": globals.yes ? "true" : "false"]
        _ = try await CLIRuntime.run(globals: globals, table: ackTable) { backend in
            try await backend.execute("runtime_delete", parameters: parameters, as: OperationAck.self)
        }
    }
}

public struct RuntimeVerifyCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "verify", abstract: "Verify a runtime signature")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Runtime identifier")
    public var identifier: String

    public init() {}

    public func run() async throws {
        _ = try await CLIRuntime.run(globals: globals, table: ackTable) { backend in
            try await backend.execute("runtime_verify", parameters: ["identifier": identifier], as: OperationAck.self)
        }
    }
}
```

Create `Sources/OpenSimCLI/Commands/AppCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimCore

public struct AppCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Manage applications on a device",
        subcommands: [
            AppListCommand.self,
            AppInstallCommand.self,
            AppUninstallCommand.self,
            AppLaunchCommand.self,
            AppTerminateCommand.self,
            AppInfoCommand.self,
            AppContainerCommand.self,
        ]
    )

    public init() {}
}

private func appTable(_ app: AppInfo) -> Table {
    Table(
        headers: ["FIELD", "VALUE"],
        rows: [
            ["bundleID", app.id],
            ["displayName", app.displayName ?? ""],
            ["version", app.version ?? ""],
            ["build", app.build ?? ""],
            ["dataContainer", app.dataContainer ?? ""],
            ["appContainer", app.appContainer ?? ""],
        ]
    )
}

private func ackTable(_ ack: OperationAck) -> Table {
    Table(headers: ["RESULT", "MESSAGE"], rows: [[ack.ok ? "ok" : "failed", ack.message ?? ""]])
}

private func parseEnvironment(_ pairs: [String]) throws -> [String: String] {
    var result: [String: String] = [:]
    for pair in pairs {
        guard let separator = pair.firstIndex(of: "=") else {
            throw OpenSimError.invalidArgument("--env must use KEY=VALUE")
        }
        let key = String(pair[..<separator])
        let value = String(pair[pair.index(after: separator)..<pair.endIndex])
        guard !key.isEmpty else {
            throw OpenSimError.invalidArgument("--env key must not be empty")
        }
        result[key] = value
    }
    return result
}

public struct AppListCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "list", abstract: "List installed apps")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Case-insensitive bundle or display name filter")
    public var filter: String?

    public init() {}

    public func run() async throws {
        var parameters = globals.parameters()
        if let filter {
            parameters["filter"] = filter
        }
        _ = try await CLIRuntime.run(globals: globals, table: { apps in
            Table(
                headers: ["BUNDLE_ID", "NAME", "VERSION", "BUILD", "DATA", "APP"],
                rows: apps.map {
                    [$0.id, $0.displayName ?? "", $0.version ?? "", $0.build ?? "", $0.dataContainer ?? "", $0.appContainer ?? ""]
                }
            )
        }) { backend in
            try await backend.execute("app_list", parameters: parameters, as: [AppInfo].self)
        }
    }
}

public struct AppInstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "install", abstract: "Install an app bundle")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Path to an .app directory")
    public var path: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["path": path])
        _ = try await CLIRuntime.run(globals: globals, table: appTable) { backend in
            try await backend.execute("app_install", parameters: parameters, as: AppInfo.self)
        }
    }
}

public struct AppUninstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Uninstall an app")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Bundle identifier")
    public var bundleID: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters([
            "bundleID": bundleID,
            "confirm": globals.yes ? "true" : "false",
        ])
        _ = try await CLIRuntime.run(globals: globals, table: ackTable) { backend in
            try await backend.execute("app_uninstall", parameters: parameters, as: OperationAck.self)
        }
    }
}

public struct AppLaunchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "launch", abstract: "Launch an app")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Bundle identifier")
    public var bundleID: String

    @Option(name: .customLong("arg"), help: "Launch argument; repeat for multiple values")
    public var arguments: [String] = []

    @Option(name: .customLong("env"), help: "Environment entry KEY=VALUE; repeat for multiple values")
    public var environment: [String] = []

    public init() {}

    public func run() async throws {
        var parameters = globals.parameters(["bundleID": bundleID])
        if !arguments.isEmpty {
            let data = try JSONEncoder().encode(arguments)
            parameters["args"] = String(decoding: data, as: UTF8.self)
        }
        let parsedEnvironment = try parseEnvironment(environment)
        if !parsedEnvironment.isEmpty {
            let data = try JSONEncoder().encode(parsedEnvironment)
            parameters["env"] = String(decoding: data, as: UTF8.self)
        }
        _ = try await CLIRuntime.run(globals: globals, table: { result in
            Table(headers: ["BUNDLE_ID", "PID"], rows: [[result.bundleID, "\(result.pid)"]])
        }) { backend in
            try await backend.execute("app_launch", parameters: parameters, as: AppLaunchResult.self)
        }
    }
}

public struct AppTerminateCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "terminate", abstract: "Terminate an app")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Bundle identifier")
    public var bundleID: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["bundleID": bundleID])
        _ = try await CLIRuntime.run(globals: globals, table: ackTable) { backend in
            try await backend.execute("app_terminate", parameters: parameters, as: OperationAck.self)
        }
    }
}

public struct AppInfoCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "info", abstract: "Show app metadata")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Bundle identifier")
    public var bundleID: String

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["bundleID": bundleID])
        _ = try await CLIRuntime.run(globals: globals, table: appTable) { backend in
            try await backend.execute("app_info", parameters: parameters, as: AppInfo.self)
        }
    }
}

public struct AppContainerCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "container", abstract: "Resolve an app container path")

    @OptionGroup public var globals: GlobalOptions

    @Argument(help: "Bundle identifier")
    public var bundleID: String

    @Option(name: .long, help: "Container kind: app, data, group")
    public var kind: String = "app"

    public init() {}

    public func run() async throws {
        let parameters = globals.parameters(["bundleID": bundleID, "kind": kind])
        _ = try await CLIRuntime.run(globals: globals, table: { result in
            Table(headers: ["BUNDLE_ID", "KIND", "PATH"], rows: [[result.bundleID, result.kind.rawValue, result.path]])
        }) { backend in
            try await backend.execute("app_container", parameters: parameters, as: ContainerPathResult.self)
        }
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter CommandParsingTests
```

Expected: PASS; `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCLI/OpenSimCommand.swift Sources/OpenSimCLI/Commands/RuntimeCommand.swift Sources/OpenSimCLI/Commands/AppCommand.swift Tests/OpenSimCLITests/CommandParsingTests.swift
git commit -m "feat(cli): add runtime and app command groups"
```

---

### Task 16: Nhóm log, doctor và capability matrix

**Files:**
- Modify: `Sources/OpenSimCLI/OpenSimCommand.swift`
- Modify: `Sources/OpenSimCLI/Output/OutputRenderer.swift`
- Create: `Sources/OpenSimCLI/Commands/LogCommand.swift`
- Create: `Sources/OpenSimCLI/Commands/DoctorCommand.swift`
- Modify: `Tests/OpenSimCLITests/CommandParsingTests.swift`

**Interfaces:**
- Consumes: `LogPage`, `LogEntry`, `CrashReport`, `DoctorReport`, `Capability`, `DaemonStatus`.
- Produces: `LogCommand` với `tail`, `stream`, `crash`; `DoctorCommand`; `OutputRenderer.line(_:)`; root command đủ năm nhóm.

- [ ] **Step 1: Viết test thất bại**

Append vào `Tests/OpenSimCLITests/CommandParsingTests.swift` trước dấu `}` cuối file:

```swift
    func testParsesLogTailLimitAndCursor() throws {
        let command = try OpenSimCommand.parseAsRoot(["log", "tail", "--limit", "25", "--cursor", "abc"])
        let tail = try XCTUnwrap(command as? LogTailCommand)
        XCTAssertEqual(tail.limit, 25)
        XCTAssertEqual(tail.cursor, "abc")
    }

    func testRootHasFiveGroups() {
        let names = OpenSimCommand.configuration.subcommands.map { $0.configuration.commandName }
        XCTAssertEqual(Set(names), Set(["device", "runtime", "app", "log", "doctor"]))
    }
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter CommandParsingTests
```

Expected: FAIL với `cannot find type 'LogTailCommand' in scope`.

- [ ] **Step 3: Viết log và doctor commands**

Modify `Sources/OpenSimCLI/OpenSimCommand.swift` thành:

```swift
import ArgumentParser
import OpenSimCore

@main
public struct OpenSimCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "opensim",
        abstract: "Control Apple simulators from the command line",
        version: OpenSimVersion.version,
        subcommands: [
            DeviceCommand.self,
            RuntimeCommand.self,
            AppCommand.self,
            LogCommand.self,
            DoctorCommand.self,
        ]
    )

    public init() {}
}
```

Modify `Sources/OpenSimCLI/Output/OutputRenderer.swift`: thêm method sau `failure`:

```swift
    public func line(_ text: String) {
        writeOut(text + "\n")
    }
```

Create `Sources/OpenSimCLI/Commands/LogCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimCore

public struct LogCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "Read simulator logs",
        subcommands: [
            LogTailCommand.self,
            LogStreamCommand.self,
            LogCrashCommand.self,
        ]
    )

    public init() {}
}

private func logLine(_ entry: LogEntry) -> String {
    let timestamp = OpenSimDate.string(from: entry.timestamp)
    let process = entry.process ?? "-"
    return "\(timestamp) \(entry.level.rawValue.uppercased()) \(process) \(entry.message)"
}

public struct LogTailCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "tail", abstract: "Read a page of log entries")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Cursor returned by a previous page")
    public var cursor: String?

    @Option(name: .long, help: "Maximum entries in this page")
    public var limit: Int = 100

    @Option(name: .long, help: "NSPredicate filter")
    public var filter: String?

    public init() {}

    public func run() async throws {
        var parameters = globals.parameters()
        if let cursor {
            parameters["cursor"] = cursor
        }
        parameters["limit"] = "\(limit)"
        if let filter {
            parameters["filter"] = filter
        }
        _ = try await CLIRuntime.run(globals: globals, table: { page in
            Table(
                headers: ["TIMESTAMP", "LEVEL", "PROCESS", "MESSAGE"],
                rows: page.entries.map { entry in
                    [OpenSimDate.string(from: entry.timestamp), entry.level.rawValue, entry.process ?? "", entry.message]
                }
            )
        }) { backend in
            try await backend.execute("log_tail", parameters: parameters, as: LogPage.self)
        }
    }
}

public struct LogStreamCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "stream", abstract: "Poll and print new log entries")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "NSPredicate filter")
    public var filter: String?

    @Option(name: .customLong("interval"), help: "Poll interval in milliseconds")
    public var intervalMs: Int = 1_000

    public init() {}

    public func run() async throws {
        guard intervalMs >= 100 && intervalMs <= 60_000 else {
            throw OpenSimError.invalidArgument("interval must be between 100 and 60000 milliseconds")
        }
        try globals.validate()
        let backend = try CLIRuntime.makeBackend(globals)
        let output = OutputRenderer(json: globals.json)
        let deadline = Date().addingTimeInterval(TimeInterval(globals.timeout))
        var cursor: String?
        while Date() < deadline {
            var parameters = globals.parameters()
            parameters["limit"] = "200"
            if let filter {
                parameters["filter"] = filter
            }
            if let cursor {
                parameters["cursor"] = cursor
            }
            let page = try await backend.execute("log_tail", parameters: parameters, as: LogPage.self)
            for entry in page.entries {
                if globals.json {
                    let data = try OpenSimJSON.encoder(pretty: false).encode(entry)
                    output.line(String(decoding: data, as: UTF8.self))
                } else {
                    output.line(logLine(entry))
                }
            }
            if let next = page.nextCursor {
                cursor = next
            }
            try await Task.sleep(for: .milliseconds(intervalMs))
        }
    }
}

public struct LogCrashCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "crash", abstract: "List crash reports")

    @OptionGroup public var globals: GlobalOptions

    @Option(name: .long, help: "Maximum reports")
    public var limit: Int = 20

    public init() {}

    public func run() async throws {
        var parameters = globals.parameters()
        parameters["limit"] = "\(limit)"
        _ = try await CLIRuntime.run(globals: globals, table: { reports in
            Table(
                headers: ["MODIFIED", "PROCESS", "SIZE", "PATH"],
                rows: reports.map {
                    [OpenSimDate.string(from: $0.modifiedAt), $0.processName, "\($0.sizeBytes)", $0.path]
                }
            )
        }) { backend in
            try await backend.execute("log_crash", parameters: parameters, as: [CrashReport].self)
        }
    }
}
```

Create `Sources/OpenSimCLI/Commands/DoctorCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimCore

public struct DoctorCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Report environment and capabilities"
    )

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        _ = try await CLIRuntime.run(
            globals: globals,
            table: { report in doctorTable(report) },
            exitCode: { report in
                guard let xcode = report.xcode else {
                    return OpenSimExitCode.permission.rawValue
                }
                if !xcode.isFullXcode {
                    return OpenSimExitCode.unsupported.rawValue
                }
                return OpenSimExitCode.success.rawValue
            }
        ) { backend in
            try await backend.execute("doctor_report", parameters: [:], as: DoctorReport.self)
        }
    }
}

private func doctorTable(_ report: DoctorReport) -> Table {
    let capabilityRows: [[String]] = [
        ["capability", "render", report.capabilities.render.rawValue, report.notes["screen"] ?? ""],
        ["capability", "hid", report.capabilities.hid.rawValue, report.notes["input"] ?? ""],
        ["capability", "a11y", report.capabilities.accessibility.rawValue, report.notes["a11y"] ?? ""],
        ["capability", "screenshot", report.capabilities.screenshot.rawValue, "simctl io"],
        ["capability", "video", report.capabilities.video.rawValue, "simctl io"],
        ["capability", "runtime", report.runtime.rawValue, "simctl runtime"],
        ["capability", "watch", report.capabilities.watch.rawValue, "watchOS runtime"],
        ["capability", "tv", report.capabilities.tv.rawValue, "tvOS runtime"],
    ]
    let environmentRows: [[String]] = [
        ["environment", "macOS", report.macOSVersion, ""],
        ["environment", "architecture", report.architecture, ""],
        ["environment", "xcode", report.xcode.map { "\($0.version) (\($0.build))" } ?? "missing", report.xcode?.path ?? ""],
        ["environment", "daemon", report.daemon.status.rawValue, ""],
        ["environment", "diskFreeBytes", "\(report.diskFreeBytes)", ""],
        ["environment", "devices", "\(report.deviceCount)", ""],
        ["environment", "runtimes", "\(report.runtimeCount)", ""],
    ]
    return Table(
        headers: ["SECTION", "ITEM", "STATUS", "NOTE"],
        rows: capabilityRows + environmentRows
    )
}
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
swift test --filter CommandParsingTests
swift build
```

Expected: PASS; `Executed 8 tests, with 0 failures`; `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCLI/OpenSimCommand.swift Sources/OpenSimCLI/Output/OutputRenderer.swift Sources/OpenSimCLI/Commands/LogCommand.swift Sources/OpenSimCLI/Commands/DoctorCommand.swift Tests/OpenSimCLITests/CommandParsingTests.swift
git commit -m "feat(cli): add log and doctor commands"
```

---

### Task 17: Integration test với Settings trên simulator thật

**Files:**
- Modify: `Package.swift` (thêm test target `IntegrationTests`)
- Create: `Tests/IntegrationTests/Plan1SettingsIntegrationTests.swift`
- Create: `Tests/IntegrationTests/README.md`

**Interfaces:**
- Consumes: `SimctlBridge.live`, `DeviceControlling`, `AppControlling`, `LogControlling`, `RuntimeControlling`.
- Produces: integration test Settings flow và lifecycle trên device tạo mới, chạy khi `OPENSIM_INTEGRATION=1`.

- [ ] **Step 1: Viết test thất bại**

Modify `Package.swift` để thêm test target:

```swift
        .testTarget(name: "IntegrationTests", dependencies: ["OpenSimCore", "OpenSimBridge"]),
```

Create `Tests/IntegrationTests/Plan1SettingsIntegrationTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class Plan1SettingsIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] == "1",
            "Set OPENSIM_INTEGRATION=1 to run simulator integration tests"
        )
    }

    private func bootedIOSDevice(_ bridge: SimctlBridge) async throws -> Device {
        let devices = try await bridge.devices.listDevices()
        guard let device = devices.first(where: { $0.state == .booted && $0.platform == .iOS }) else {
            throw XCTSkip("No booted iOS simulator")
        }
        return device
    }

    func testSettingsAppFlow() async throws {
        let bridge = try SimctlBridge.live(timeout: .seconds(120))
        let device = try await bootedIOSDevice(bridge)

        let apps = try await bridge.apps.listApps(on: device.id, filter: "Preferences")
        XCTAssertTrue(apps.contains { $0.id == "com.apple.Preferences" })

        let info = try await bridge.apps.appInfo(on: device.id, bundleID: "com.apple.Preferences")
        XCTAssertEqual(info.displayName, "Settings")
        XCTAssertEqual(info.id, "com.apple.Preferences")

        let pid = try await bridge.apps.launchApp(
            on: device.id,
            bundleID: "com.apple.Preferences",
            args: [],
            environment: [:]
        )
        XCTAssertGreaterThan(pid, 0)

        let appPath = try await bridge.apps.containerPath(
            on: device.id,
            bundleID: "com.apple.Preferences",
            kind: .app
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: appPath))

        let page = try await bridge.logs.tailLogs(on: device.id, cursor: nil, limit: 20, filter: nil)
        XCTAssertFalse(page.entries.isEmpty)

        try await bridge.apps.terminateApp(on: device.id, bundleID: "com.apple.Preferences")
    }

    func testTemporaryDeviceLifecycle() async throws {
        let bridge = try SimctlBridge.live(timeout: .seconds(180))
        let runtimes = try await bridge.runtimes.listRuntimes()
        guard let runtime = runtimes.first(where: { $0.platform == .iOS && $0.isAvailable }) else {
            throw XCTSkip("No available iOS runtime")
        }
        let name = "OpenSim IT \(UUID().uuidString.prefix(8))"
        let device = try await bridge.devices.createDevice(
            name: name,
            deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-17e",
            runtime: runtime.id
        )
        do {
            let booted = try await bridge.devices.boot(device.id, wait: true)
            XCTAssertEqual(booted.state, .booted)
            let shutdown = try await bridge.devices.shutdown(device.id, wait: true)
            XCTAssertEqual(shutdown.state, .shutdown)
            let erased = try await bridge.devices.erase(device.id)
            XCTAssertEqual(erased.state, .shutdown)
            try await bridge.devices.delete(device.id)
        } catch {
            try? await bridge.devices.delete(device.id)
            throw error
        }
        let remaining = try await bridge.devices.listDevices()
        XCTAssertFalse(remaining.contains { $0.id == device.id })
    }
}
```

Create `Tests/IntegrationTests/README.md`:

```markdown
# Integration tests

Plan 1 integration tests use the real simulator and are disabled by default.

- `testSettingsAppFlow` requires one booted iOS 27 simulator and the system app `com.apple.Preferences`.
- `testTemporaryDeviceLifecycle` creates a device named `OpenSim IT <suffix>`, boots it, shuts it down, erases it, then deletes it. The test deletes the device on failure as well.

Run:

```bash
swift build
OPENSIM_INTEGRATION=1 swift test --filter Plan1SettingsIntegrationTests
```

Expected: `Executed 2 tests, with 0 failures`.
```

- [ ] **Step 2: Chạy để thấy fail**

Run:

```bash
swift test --filter Plan1SettingsIntegrationTests
```

Expected: PASS-with-skip; output có `Executed 2 tests, with 2 tests skipped` vì `OPENSIM_INTEGRATION` chưa đặt. Đây là trạng thái đỏ theo nghĩa chưa chạy hành vi thật; bước 3 chỉ sửa lỗi biên dịch nếu có.

- [ ] **Step 3: Chạy integration thật**

Run:

```bash
swift build
OPENSIM_INTEGRATION=1 swift test --filter Plan1SettingsIntegrationTests
```

Expected: `Executed 2 tests, with 0 failures`. Nếu chưa có device booted, `testSettingsAppFlow` skip và `testTemporaryDeviceLifecycle` vẫn chạy; để đủ điều kiện, boot trước:

```bash
xcrun simctl boot "iPhone Air"
xcrun simctl bootstatus "iPhone Air" -b
```

Sau đó chạy lại lệnh test. Expected output cuối cùng:

```text
Test Suite 'Plan1SettingsIntegrationTests' passed
Executed 2 tests, with 0 failures (0 unexpected) in <seconds> seconds
```

- [ ] **Step 4: Chạy smoke CLI trên máy thật**

Run:

```bash
BIN="$(swift build --show-bin-path)/opensim"
"$BIN" doctor --json
"$BIN" device list --platform iOS --state booted --json
"$BIN" app info com.apple.Preferences --device "iPhone Air" --json
"$BIN" app launch com.apple.Preferences --device "iPhone Air" --json
"$BIN" log tail --device "iPhone Air" --limit 5 --json
"$BIN" app terminate com.apple.Preferences --device "iPhone Air" --json
```

Expected:

- `doctor --json`: envelope có `"schemaVersion" : 1`, `"ok" : true`; `data.xcode.version` là `"27.1"`; `data.capabilities.render` là `"unavailable"`; `data.daemon.status` là `"notInstalled"`; exit code `0`.
- `device list`: `data` là array không rỗng; mỗi phần tử có `id`, `name`, `platform`, `runtime`, `state`, `isAvailable`; exit code `0`.
- `app info`: `data.id` là `"com.apple.Preferences"`, `data.displayName` là `"Settings"`; exit code `0`.
- `app launch`: `data.bundleID` là `"com.apple.Preferences"`, `data.pid` là số nguyên dương; exit code `0`.
- `log tail`: `data.entries` là array không rỗng, `data.nextCursor` là string; exit code `0`.
- `app terminate`: `data.ok` là `true`; exit code `0`.

Human output check:

```bash
"$BIN" device get --device "iPhone Air"
```

Expected: bảng hai cột với header `FIELD` và `VALUE`; dòng `udid` chứa UDID của device, dòng `name` chứa `iPhone Air`, dòng `platform` chứa `iOS`, dòng `state` chứa `booted`; không có dòng lỗi trên stderr. Căn cột chính xác được kiểm tra trong `OutputRendererTests.testTableAlignment`.

Exit code check:

```bash
"$BIN" device delete --device "OpenSim Missing Device"
echo "exit=$?"
```

Expected: exit code `3`; stderr có `error[device_not_found]`.

```bash
"$BIN" device list --device "iPhone Air" --timeout 0
echo "exit=$?"
```

Expected: exit code `2`; stderr có `error[invalid_argument]`.

- [ ] **Step 5: Commit**

```bash
git add Tests/IntegrationTests/Plan1SettingsIntegrationTests.swift Tests/IntegrationTests/README.md
git commit -m "test(integration): add settings and lifecycle simulator tests"
```

---

## Spec coverage

| Mục spec | Nội dung | Task |
|---|---|---|
| 5.1 | Tầng `OpenSimCore`, `OpenSimBridge`, `OpenSimCLI`; không private API ngoài Bridge | 1, 4, 7, 12 |
| 5.2 | Process model chỉ áp dụng phần CLI direct; daemon defer sang Plan 3 | 13, 17 |
| 5.4 | `simctl` ưu tiên; private API chỉ probe class, capability-gated; developer dir allowlist | 6, 7, 11, 12 |
| 5.6 | macOS 27, Xcode 27.1, fingerprint framework trong doctor | 11 |
| 6 | Domain `Device`, `Runtime`, `AppInfo`, `LogEntry`, `LogPage`, `Key`, `KeyModifiers`, `HardwareButton`, `VideoCodec`, `ContainerKind` | 1, 2 |
| 7.1 | `--json`, `--device`, `--timeout`, `--yes`, exit code, envelope | 3, 13, 14, 15, 16 |
| 7.2 | CLI `device`, `runtime`, `app`, `log`, `doctor` (phần lifecycle) | 14, 15, 16 |
| 8.3 | Error code và `retryable`, `recovery` | 3, 7 |
| 12 | Validate UDID, bundle ID, path; không shell string | 6, 7, 9 |
| 13 | `doctor` kiểm tra macOS, Xcode, framework, capability, disk, device/runtime | 11, 16 |
| 14.1 | Unit test domain, envelope, error, catalog, simctl builder, path | 1-7, 9, 10, 13 |
| 14.2 | Integration Settings trên simulator booted; lifecycle device thật | 17 |
| 15 | SwiftPM, `swift-argument-parser`, không MCP SDK/database | 1 |
| 16 Plan 1 | Core + Bridge + lifecycle + CLI; golden JSON; doctor | tất cả |

Phần ngoài Plan 1: `ui`, screen/input/a11y (Plan 2), daemon/session/MCP (Plan 3: `docs/superpowers/plans/2026-10-20-opensim-plan-3-daemon-session-mcp.md`), app macOS (Plan 4), storage/perf (Plan 5), watch/tv parity (Plan 6), `app data export/import`, `device pair/location/appearance/privacy/push/openurl/pasteboard` (các plan sau đăng ký catalog operation tương ứng).

## Exit criteria

- `swift build` thành công trên macOS 27 với Xcode 27.1.
- `swift test` chạy toàn bộ unit test của `OpenSimCoreTests`, `OpenSimBridgeTests`, `OpenSimCLITests` và pass.
- `OPENSIM_INTEGRATION=1 swift test --filter Plan1SettingsIntegrationTests` pass với một simulator iOS 27 booted; test lifecycle tạo và xoá device `OpenSim IT`.
- `opensim doctor --json` trả envelope hợp lệ, capability `render/hid/a11y` là `unavailable`, `screenshot/video` là `available`, `runtime` là `available`, `watch/tv` phản ánh runtime đã cài.
- `opensim device list`, `device get`, `device boot`, `device shutdown`, `app list`, `app info`, `app launch`, `app terminate`, `app container`, `log tail`, `log crash` chạy được trên device thật.
- Exit code đúng cho success `0`, invalid argument `2`, missing device `3`, confirmation `7`; JSON envelope có `schemaVersion = 1`.
- `SimulatorBridge.screen`, `.input`, `.accessibility` là `nil`; không có target `OpenSimBridgeUI` trong package.
- Không có file daemon, MCP, storage, performance hoặc app UI trong phạm vi Plan 1.

