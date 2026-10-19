# OpenSim Plan 6 — watchOS and tvOS Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bổ sung inventory runtime watchOS/tvOS, platform adapter cho screen/input/buttons/pairing, fixture app và integration test để boot, render, screenshot, tap trên watch và tv mà không đổi kiến trúc lõi.

**Architecture:** `OpenSimCore` thêm protocol `PlatformAdapter`, descriptor màn hình, input map và `PairingControlling` dưới dạng type mới; không đổi tên hay chữ ký của Plan 1/2. `OpenSimBridge` thêm inventory runtime và controller `simctl pair/unpair`. CLI, MCP và app chỉ đọc adapter registry để bật đúng gesture/button; app dùng lại cửa sổ device của Plan 4. Runtime watch/tv chỉ được cài khi owner chạy script có cờ `--owner-approved`; mọi test khi thiếu runtime ghi `BLOCKED` và skip, không tự tải.

**Tech Stack:** Swift 6 language mode, SwiftPM, Foundation, `simctl`, `xcodebuild -downloadPlatform`, XcodeGen cho fixture, SwiftUI cho fixture và app, XCTest, XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-19-open-simulator-design.md`

## Global Constraints

- macOS 27.0+; arm64; Xcode 27.1+ (Xcode 27.0 best-effort nếu fingerprint khớp).
- Swift 6 language mode; SwiftPM cho Core/Bridge/Daemon/CLI; XcodeGen cho app và fixture.
- Không tải runtime tự động. Không source nào trong `Sources/`, `App/`, `Fixtures/` được chứa `xcodebuild -downloadPlatform`; chỉ `Scripts/install-platform-runtimes.sh` được chứa lệnh này và phải yêu cầu `--owner-approved`.
- Lệnh cài runtime chính xác: `xcodebuild -downloadPlatform watchOS` và `xcodebuild -downloadPlatform tvOS`.
- Khi runtime watchOS hoặc tvOS thiếu: unit/contract test vẫn chạy; integration test in `BLOCKED: <platform> runtime missing` và `XCTSkip`, không fail.
- Không đổi tên type/protocol của Plan 1/2. Chỉ thêm type mới hoặc extension additive.
- `HardwareButton` của contract giữ nguyên; watch digital crown được map sang `scroll`, không thêm case mới.
- tvOS dùng focus navigation: `tap` là select, `swipe` là di chuyển focus; không giả lập multi-touch.
- watchOS không hỗ trợ pinch/rotate; app phải disable các gesture này theo `PlatformInputMap`, không crash.
- Pairing chỉ giữa watchOS và iOS; validate platform trước khi gọi `simctl pair`.
- Fixture watch bundle ID `dev.opensim.fixture.watch`; fixture tv bundle ID `dev.opensim.fixture.tv`.
- Không dùng mock data trong app; integration test dùng simulator thật.
- Không dùng shell string trong source; `Process` nhận argument array. Script shell chỉ dùng cho owner-run runtime install.
- Văn xuôi tiếng Việt; code, type, identifier, command tiếng Anh; không ký tự CJK.
- Mọi task kết thúc bằng commit; người review plan không chạy commit.

## Phụ thuộc

- Plan 0: `docs/superpowers/plans/2026-10-19-opensim-plan-0-private-api-spike.md`. Kết quả watch/tv hiện được dự kiến là `BLOCKED_RUNTIME_MISSING`; Plan 6 không giả định render watch/tv đã pass.
- Plan 1: `docs/superpowers/plans/2026-10-20-opensim-plan-1-core-bridge-cli.md`. Cung cấp `OpenSimCore`, `OpenSimBridge`, `DeviceControlling`, `RuntimeControlling`, `AppControlling`, CLI envelope, `doctor`.
- Plan 2: `docs/superpowers/plans/2026-10-20-opensim-plan-2-screen-input-a11y.md`. Cung cấp `ScreenControlling`, `InputControlling`, `AccessibilityReading`, fixture iOS, capability gate.
- Plan 3: `docs/superpowers/plans/2026-10-20-opensim-plan-3-daemon-session-mcp.md`. Cung cấp daemon client, MCP `device_pair`.
- Plan 4: `docs/superpowers/plans/2026-10-20-opensim-plan-4-macos-app.md`. Cung cấp shell, device window, toolbar; Plan 6 chỉ thêm adapter và sửa toolbar, không tạo shell mới.
- Contract: `docs/superpowers/plans/2026-10-20-plan-map-and-interfaces.md`. `Platform`, `HardwareButton`, `ScreenInfo`, `Device`, `Runtime`, `BridgeCapabilities` giữ nguyên.
- Plan 1/2 protocol không đổi. `PairingControlling` là protocol mới trong `OpenSimCore/Platform`, không thay `DeviceControlling.pair`.

## File Structure

| File | Trách nhiệm | Loại |
|---|---|---|
| `Sources/OpenSimCore/Platform/PlatformAdapter.swift` | Protocol adapter, registry, device type mapping | Tạo |
| `Sources/OpenSimCore/Platform/ScreenDescriptor.swift` | Kích thước logic, scale, safe area, corner radius | Tạo |
| `Sources/OpenSimCore/Platform/PlatformInputMap.swift` | Gesture, button, focus navigation theo platform | Tạo |
| `Sources/OpenSimCore/Platform/Pairing.swift` | `DevicePair`, `PairingState`, `PairingControlling` | Tạo |
| `Sources/OpenSimCore/Platform/PlatformRuntimeStatus.swift` | Trạng thái runtime matrix dùng chung | Tạo |
| `Sources/OpenSimBridge/Services/PlatformRuntimeInventory.swift` | Runtime matrix watch/tv/iOS, trạng thái BLOCKED | Tạo |
| `Sources/OpenSimBridge/Services/SimctlPairingController.swift` | `simctl pair/unpair/list pairs` với validation | Tạo |
| `Sources/OpenSimBridge/Capabilities/PlatformCapabilityReporter.swift` | Báo capability watch/tv cho doctor | Tạo |
| `Sources/OpenSimCLI/Output/PlatformMatrixTable.swift` | Bảng runtime matrix cho `doctor` | Tạo |
| `Sources/OpenSimCLI/Commands/DoctorCommand.swift` | Thêm section platforms vào doctor | Sửa (Plan 1) |
| `Sources/OpenSimCLI/Commands/DeviceCommand.swift` | Thêm `device pair`, `device unpair` | Sửa (Plan 1) |
| `Sources/OpenSimMCP/Tools/DeviceTools.swift` | Hoàn thiện handler `device_pair` | Sửa (Plan 3) |
| `App/Sources/OpenSimApp/Windows/PlatformToolbarAdapter.swift` | Lọc button/gesture theo adapter | Tạo |
| `App/Sources/OpenSimApp/Windows/DeviceWindowToolbar.swift` | Dùng adapter thay danh sách cố định | Sửa (Plan 4) |
| `App/Sources/OpenSimApp/Windows/DeviceWindowController.swift` | Truyền platform adapter vào cửa sổ | Sửa (Plan 4) |
| `Fixtures/OpenSimFixtureWatch/project.yml` | XcodeGen watch fixture | Tạo |
| `Fixtures/OpenSimFixtureWatch/Sources/OpenSimFixtureWatchApp.swift` | Entry point watch | Tạo |
| `Fixtures/OpenSimFixtureWatch/Sources/ContentView.swift` | Button/label watch | Tạo |
| `Fixtures/OpenSimFixtureWatch/Info.plist` | Bundle metadata watch | Tạo |
| `Fixtures/OpenSimFixtureWatch/build.sh` | Build fixture watch cho simulator | Tạo |
| `Fixtures/OpenSimFixtureTV/project.yml` | XcodeGen tv fixture | Tạo |
| `Fixtures/OpenSimFixtureTV/Sources/OpenSimFixtureTVApp.swift` | Entry point tv | Tạo |
| `Fixtures/OpenSimFixtureTV/Sources/ContentView.swift` | Button/label tv | Tạo |
| `Fixtures/OpenSimFixtureTV/Info.plist` | Bundle metadata tv | Tạo |
| `Fixtures/OpenSimFixtureTV/build.sh` | Build fixture tv cho simulator | Tạo |
| `Scripts/install-platform-runtimes.sh` | Cài runtime có owner approval | Tạo |
| `docs/platform-runtimes.md` | Runbook cài runtime và trạng thái BLOCKED | Tạo |
| `Tests/OpenSimCoreTests/PlatformAdapterTests.swift` | Descriptor, input map, registry | Tạo |
| `Tests/OpenSimCoreTests/RuntimeDownloadPolicyTests.swift` | Không auto-download; script đúng lệnh | Tạo |
| `Tests/OpenSimCoreTests/PlatformRuntimeStatusTests.swift` | Matrix ready/blocked | Tạo |
| `Tests/OpenSimCoreTests/PairingValidationTests.swift` | Validate watch+phone | Tạo |
| `Tests/OpenSimBridgeTests/PlatformRuntimeInventoryTests.swift` | Inventory với fake runtime | Tạo |
| `Tests/OpenSimBridgeTests/SimctlPairingControllerTests.swift` | Argument array pair/unpair | Tạo |
| `Tests/OpenSimCLITests/PlatformCommandTests.swift` | Pair/unpair JSON, doctor matrix | Tạo |
| `Tests/OpenSimAppUITests/PlatformWindowUITests.swift` | Toolbar watch/tv theo adapter | Tạo |
| `Tests/IntegrationTests/PlatformRuntimeMatrixTests.swift` | Boot/screenshot matrix, skip BLOCKED | Tạo |
| `Tests/IntegrationTests/WatchIntegrationTests.swift` | Watch fixture flow | Tạo |
| `Tests/IntegrationTests/TVIntegrationTests.swift` | TV fixture flow | Tạo |
| `Tests/IntegrationTests/PlatformPairingTests.swift` | Pair/unpair watch+phone | Tạo |

---

### Task 1: Core platform adapter, screen descriptor và input map

**Files:**
- Create: `Sources/OpenSimCore/Platform/ScreenDescriptor.swift`
- Create: `Sources/OpenSimCore/Platform/PlatformInputMap.swift`
- Create: `Sources/OpenSimCore/Platform/PlatformAdapter.swift`
- Test: `Tests/OpenSimCoreTests/PlatformAdapterTests.swift`

**Interfaces:**
- Consumes: `Platform`, `HardwareButton`, `ScreenInfo` từ contract.
- Produces: `ScreenInsets`, `ScreenDescriptor`, `InputGesture`, `PlatformInputMap`, `PlatformAdapter`, `IOSPlatformAdapter`, `WatchOSPlatformAdapter`, `TVOSPlatformAdapter`, `PlatformRegistry`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimCoreTests/PlatformAdapterTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class PlatformAdapterTests: XCTestCase {
    func testWatchAdapterHasWatchScreenAndNoPinch() {
        let adapter = WatchOSPlatformAdapter()
        XCTAssertEqual(adapter.platform, .watchOS)
        XCTAssertEqual(adapter.screenDescriptor.width, 416)
        XCTAssertEqual(adapter.screenDescriptor.height, 496)
        XCTAssertEqual(adapter.screenDescriptor.scale, 2)
        XCTAssertFalse(adapter.inputMap.supportedGestures.contains(.pinch))
        XCTAssertFalse(adapter.inputMap.supportedGestures.contains(.rotate))
        XCTAssertTrue(adapter.inputMap.supportedGestures.contains(.tap))
        XCTAssertEqual(adapter.inputMap.hardwareButtons, [.side, .lock])
        XCTAssertTrue(adapter.supportsPairing)
    }

    func testTVAdapterUsesFocusNavigation() {
        let adapter = TVOSPlatformAdapter()
        XCTAssertEqual(adapter.platform, .tvOS)
        XCTAssertEqual(adapter.screenDescriptor.width, 1920)
        XCTAssertEqual(adapter.screenDescriptor.height, 1080)
        XCTAssertEqual(adapter.screenDescriptor.scale, 1)
        XCTAssertTrue(adapter.inputMap.focusNavigation)
        XCTAssertFalse(adapter.inputMap.supportsCoordinateTap)
        XCTAssertEqual(adapter.inputMap.hardwareButtons, [.appleTVSelect, .appleTVMenu, .appleTVHome])
        XCTAssertFalse(adapter.supportsPairing)
    }

    func testIOSAdapterSupportsAllGestures() {
        let adapter = IOSPlatformAdapter()
        XCTAssertEqual(adapter.platform, .iOS)
        XCTAssertTrue(adapter.inputMap.supportedGestures.contains(.pinch))
        XCTAssertTrue(adapter.inputMap.supportedGestures.contains(.rotate))
        XCTAssertTrue(adapter.inputMap.supportsCoordinateTap)
        XCTAssertEqual(adapter.inputMap.hardwareButtons, [.home, .lock, .side, .volumeUp, .volumeDown])
    }

    func testRegistryResolvesWatchAndTVByDeviceType() {
        let registry = PlatformRegistry()
        XCTAssertEqual(registry.adapter(forDeviceType: "Apple-Watch-Series-12-46mm")?.platform, .watchOS)
        XCTAssertEqual(registry.adapter(forDeviceType: "Apple-TV-4K-3rd-generation-4K")?.platform, .tvOS)
        XCTAssertEqual(registry.adapter(forDeviceType: "iPhone-17")?.platform, .iOS)
        XCTAssertNil(registry.adapter(forDeviceType: "Apple-Vision-Pro"))
    }

    func testScreenDescriptorCanBeBuiltFromScreenInfo() {
        let info = ScreenInfo(id: 1, width: 416, height: 496, scale: 2, rotation: 0, displayClass: 0)
        let descriptor = ScreenDescriptor(screenInfo: info)
        XCTAssertEqual(descriptor.width, 416)
        XCTAssertEqual(descriptor.height, 496)
        XCTAssertEqual(descriptor.scale, 2)
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimCoreTests.PlatformAdapterTests
```

Expected: FAIL vì `WatchOSPlatformAdapter` chưa tồn tại.

- [ ] **Step 3: Viết descriptor và input map**

Create `Sources/OpenSimCore/Platform/ScreenDescriptor.swift`:

```swift
import Foundation

public struct ScreenInsets: Codable, Sendable, Equatable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

public struct ScreenDescriptor: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var scale: Double
    public var displayClass: Int
    public var rotation: Double
    public var cornerRadius: Double?
    public var safeAreaInsets: ScreenInsets

    public init(
        width: Int,
        height: Int,
        scale: Double,
        displayClass: Int = 0,
        rotation: Double = 0,
        cornerRadius: Double? = nil,
        safeAreaInsets: ScreenInsets = ScreenInsets()
    ) {
        self.width = width
        self.height = height
        self.scale = scale
        self.displayClass = displayClass
        self.rotation = rotation
        self.cornerRadius = cornerRadius
        self.safeAreaInsets = safeAreaInsets
    }

    public init(screenInfo: ScreenInfo) {
        self.init(
            width: screenInfo.width,
            height: screenInfo.height,
            scale: screenInfo.scale,
            displayClass: screenInfo.displayClass,
            rotation: screenInfo.rotation
        )
    }
}
```

Create `Sources/OpenSimCore/Platform/PlatformInputMap.swift`:

```swift
import Foundation

public enum InputGesture: String, Codable, Sendable, CaseIterable, Hashable {
    case tap
    case longPress
    case swipe
    case drag
    case pinch
    case rotate
    case scroll
    case text
    case key
    case hardwareButton
}

public struct PlatformInputMap: Codable, Sendable, Equatable {
    public var supportedGestures: Set<InputGesture>
    public var hardwareButtons: [HardwareButton]
    public var supportsCoordinateTap: Bool
    public var focusNavigation: Bool
    public var defaultSettleMilliseconds: Int

    public init(
        supportedGestures: Set<InputGesture>,
        hardwareButtons: [HardwareButton],
        supportsCoordinateTap: Bool,
        focusNavigation: Bool,
        defaultSettleMilliseconds: Int = 120
    ) {
        self.supportedGestures = supportedGestures
        self.hardwareButtons = hardwareButtons
        self.supportsCoordinateTap = supportsCoordinateTap
        self.focusNavigation = focusNavigation
        self.defaultSettleMilliseconds = defaultSettleMilliseconds
    }
}
```

- [ ] **Step 4: Viết adapter và registry**

Create `Sources/OpenSimCore/Platform/PlatformAdapter.swift`:

```swift
import Foundation

public protocol PlatformAdapter: Sendable {
    var platform: Platform { get }
    var runtimePlatformName: String { get }
    var deviceTypePrefixes: [String] { get }
    var screenDescriptor: ScreenDescriptor { get }
    var inputMap: PlatformInputMap { get }
    var supportsPairing: Bool { get }
}

public struct IOSPlatformAdapter: PlatformAdapter {
    public let platform: Platform = .iOS
    public let runtimePlatformName = "iOS"
    public let deviceTypePrefixes = ["iPhone", "iPad"]
    public let screenDescriptor = ScreenDescriptor(width: 393, height: 852, scale: 3)
    public let inputMap = PlatformInputMap(
        supportedGestures: Set(InputGesture.allCases),
        hardwareButtons: [.home, .lock, .side, .volumeUp, .volumeDown],
        supportsCoordinateTap: true,
        focusNavigation: false
    )
    public let supportsPairing = true

    public init() {}
}

public struct WatchOSPlatformAdapter: PlatformAdapter {
    public let platform: Platform = .watchOS
    public let runtimePlatformName = "watchOS"
    public let deviceTypePrefixes = ["Apple-Watch", "Watch"]
    public let screenDescriptor = ScreenDescriptor(
        width: 416,
        height: 496,
        scale: 2,
        displayClass: 1,
        cornerRadius: 46,
        safeAreaInsets: ScreenInsets(top: 24, left: 0, bottom: 20, right: 0)
    )
    public let inputMap = PlatformInputMap(
        supportedGestures: [.tap, .longPress, .swipe, .drag, .scroll, .text, .hardwareButton],
        hardwareButtons: [.side, .lock],
        supportsCoordinateTap: true,
        focusNavigation: false,
        defaultSettleMilliseconds: 150
    )
    public let supportsPairing = true

    public init() {}
}

public struct TVOSPlatformAdapter: PlatformAdapter {
    public let platform: Platform = .tvOS
    public let runtimePlatformName = "tvOS"
    public let deviceTypePrefixes = ["Apple-TV"]
    public let screenDescriptor = ScreenDescriptor(
        width: 1920,
        height: 1080,
        scale: 1,
        displayClass: 2,
        safeAreaInsets: ScreenInsets(top: 60, left: 80, bottom: 60, right: 80)
    )
    public let inputMap = PlatformInputMap(
        supportedGestures: [.tap, .longPress, .swipe, .hardwareButton],
        hardwareButtons: [.appleTVSelect, .appleTVMenu, .appleTVHome],
        supportsCoordinateTap: false,
        focusNavigation: true,
        defaultSettleMilliseconds: 200
    )
    public let supportsPairing = false

    public init() {}
}

public struct PlatformRegistry: Sendable {
    private let adapters: [any PlatformAdapter]

    public init(adapters: [any PlatformAdapter] = [
        IOSPlatformAdapter(),
        WatchOSPlatformAdapter(),
        TVOSPlatformAdapter()
    ]) {
        self.adapters = adapters
    }

    public func adapter(for platform: Platform) -> (any PlatformAdapter)? {
        adapters.first { $0.platform == platform }
    }

    public func adapter(forDeviceType deviceType: String) -> (any PlatformAdapter)? {
        adapters.first { adapter in
            adapter.deviceTypePrefixes.contains { prefix in
                deviceType.hasPrefix(prefix)
            }
        }
    }
}
```

- [ ] **Step 5: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimCoreTests.PlatformAdapterTests
```

Expected: PASS 5 test.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenSimCore/Platform/ScreenDescriptor.swift Sources/OpenSimCore/Platform/PlatformInputMap.swift Sources/OpenSimCore/Platform/PlatformAdapter.swift Tests/OpenSimCoreTests/PlatformAdapterTests.swift
git commit -m "feat(platform): add adapters for iOS, watchOS and tvOS"
```

---

### Task 2: Runtime inventory, owner approval gate và runbook

**Files:**
- Create: `Sources/OpenSimCore/Platform/PlatformRuntimeStatus.swift`
- Create: `Sources/OpenSimBridge/Services/PlatformRuntimeInventory.swift`
- Create: `Scripts/install-platform-runtimes.sh`
- Create: `docs/platform-runtimes.md`
- Test: `Tests/OpenSimCoreTests/PlatformRuntimeStatusTests.swift`
- Test: `Tests/OpenSimCoreTests/RuntimeDownloadPolicyTests.swift`
- Test: `Tests/OpenSimBridgeTests/PlatformRuntimeInventoryTests.swift`

**Interfaces:**
- Consumes: `Runtime`, `RuntimeControlling`, `Platform`.
- Produces: `PlatformRuntimeStatus`, `PlatformRuntimeInventory.status(for:)`, `PlatformRuntimeInventory.matrix()`, `PlatformRuntimeMatrixSummary`.

- [ ] **Step 1: Viết test runtime status thất bại**

Create `Tests/OpenSimCoreTests/PlatformRuntimeStatusTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class PlatformRuntimeStatusTests: XCTestCase {
    func testReadyStatusUsesInstalledRuntime() {
        let runtime = Runtime(
            id: RuntimeID(rawValue: "com.apple.CoreSimulator.SimRuntime.watchOS-27-0"),
            name: "watchOS 27.0",
            platform: .watchOS,
            version: "27.0",
            build: "24R100",
            isAvailable: true,
            path: "/tmp/watch"
        )
        let status = PlatformRuntimeStatus(
            platform: .watchOS,
            installedRuntimes: [runtime],
            isReady: true,
            blockingReason: nil
        )
        XCTAssertTrue(status.isReady)
        XCTAssertEqual(status.installedRuntimes.first?.version, "27.0")
    }

    func testMissingRuntimeStatusIsBlocked() {
        let status = PlatformRuntimeStatus.missing(for: .tvOS)
        XCTAssertFalse(status.isReady)
        XCTAssertEqual(status.blockingReason, "BLOCKED: tvOS runtime missing")
    }

    func testMatrixSummaryCountsBlockedPlatforms() {
        let summary = PlatformRuntimeMatrixSummary(
            statuses: [
                PlatformRuntimeStatus(platform: .iOS, installedRuntimes: [], isReady: true, blockingReason: nil),
                PlatformRuntimeStatus.missing(for: .watchOS),
                PlatformRuntimeStatus.missing(for: .tvOS)
            ]
        )
        XCTAssertEqual(summary.readyPlatforms, [.iOS])
        XCTAssertEqual(summary.blockedPlatforms, [.watchOS, .tvOS])
    }
}
```

Create `Tests/OpenSimCoreTests/RuntimeDownloadPolicyTests.swift`:

```swift
import XCTest

final class RuntimeDownloadPolicyTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testSourceTreeNeverCallsDownloadPlatform() throws {
        let fileManager = FileManager.default
        for directory in ["Sources", "App", "Fixtures"] {
            let root = repositoryRoot.appendingPathComponent(directory)
            guard fileManager.fileExists(atPath: root.path) else { continue }
            let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" || url.lastPathComponent == "project.yml" else {
                    continue
                }
                let contents = try String(contentsOf: url, encoding: .utf8)
                XCTAssertFalse(
                    contents.contains("downloadPlatform"),
                    "\(url.path) must not download platform runtimes"
                )
            }
        }
    }

    func testInstallScriptRequiresOwnerApprovalAndExactCommands() throws {
        let script = repositoryRoot.appendingPathComponent("Scripts/install-platform-runtimes.sh")
        let contents = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(contents.contains("--owner-approved"))
        XCTAssertTrue(contents.contains("xcodebuild -downloadPlatform watchOS"))
        XCTAssertTrue(contents.contains("xcodebuild -downloadPlatform tvOS"))
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimCoreTests.PlatformRuntimeStatusTests
swift test --filter OpenSimCoreTests.RuntimeDownloadPolicyTests
```

Expected: FAIL vì status type và script chưa tồn tại.

- [ ] **Step 3: Viết status và inventory**

Create `Sources/OpenSimCore/Platform/PlatformRuntimeStatus.swift`:

```swift
import Foundation

public struct PlatformRuntimeStatus: Codable, Sendable, Equatable {
    public var platform: Platform
    public var installedRuntimes: [Runtime]
    public var isReady: Bool
    public var blockingReason: String?

    public init(
        platform: Platform,
        installedRuntimes: [Runtime],
        isReady: Bool,
        blockingReason: String?
    ) {
        self.platform = platform
        self.installedRuntimes = installedRuntimes
        self.isReady = isReady
        self.blockingReason = blockingReason
    }

    public static func missing(for platform: Platform) -> PlatformRuntimeStatus {
        PlatformRuntimeStatus(
            platform: platform,
            installedRuntimes: [],
            isReady: false,
            blockingReason: "BLOCKED: \(platform.rawValue) runtime missing"
        )
    }
}

public struct PlatformRuntimeMatrixSummary: Codable, Sendable, Equatable {
    public var statuses: [PlatformRuntimeStatus]

    public init(statuses: [PlatformRuntimeStatus]) {
        self.statuses = statuses
    }

    public var readyPlatforms: [Platform] {
        statuses.filter(\.isReady).map(\.platform)
    }

    public var blockedPlatforms: [Platform] {
        statuses.filter { !$0.isReady }.map(\.platform)
    }
}
```

Create `Sources/OpenSimBridge/Services/PlatformRuntimeInventory.swift`:

```swift
import Foundation
import OpenSimCore

public struct PlatformRuntimeInventory: Sendable {
    private let runtimes: any RuntimeControlling

    public init(runtimes: any RuntimeControlling) {
        self.runtimes = runtimes
    }

    public func status(for platform: Platform) async throws -> PlatformRuntimeStatus {
        let all = try await runtimes.listRuntimes()
        let installed = all.filter { $0.platform == platform && $0.isAvailable }
        if installed.isEmpty {
            return PlatformRuntimeStatus.missing(for: platform)
        }
        return PlatformRuntimeStatus(
            platform: platform,
            installedRuntimes: installed,
            isReady: true,
            blockingReason: nil
        )
    }

    public func matrix() async throws -> PlatformRuntimeMatrixSummary {
        var statuses: [PlatformRuntimeStatus] = []
        for platform in [Platform.iOS, .watchOS, .tvOS] {
            statuses.append(try await status(for: platform))
        }
        return PlatformRuntimeMatrixSummary(statuses: statuses)
    }
}
```

Không có hàm nào gọi `xcodebuild -downloadPlatform`; inventory chỉ đọc `simctl runtime list` qua `RuntimeControlling`.

- [ ] **Step 4: Viết script gate và runbook**

Create `Scripts/install-platform-runtimes.sh`:

```zsh
#!/bin/zsh
set -euo pipefail

if [[ "${1:-}" != "--owner-approved" ]]; then
  print -u2 "Refusing to download runtimes without owner approval."
  print -u2 "Run: Scripts/install-platform-runtimes.sh --owner-approved"
  exit 2
fi

print "Downloading watchOS runtime. This can take several GB and several minutes."
xcodebuild -downloadPlatform watchOS

print "Downloading tvOS runtime. This can take several GB and several minutes."
xcodebuild -downloadPlatform tvOS

print "Runtime download finished. Verify with: opensim doctor --json"
```

Create `docs/platform-runtimes.md`:

```markdown
# OpenSim platform runtimes

OpenSim không tải runtime tự động. Owner phải đồng ý và chạy script thủ công:

```bash
Scripts/install-platform-runtimes.sh --owner-approved
```

Script chạy đúng hai lệnh:

```bash
xcodebuild -downloadPlatform watchOS
xcodebuild -downloadPlatform tvOS
```

Sau khi cài, kiểm tra:

```bash
opensim doctor --json
opensim runtime list --platform watchOS
opensim runtime list --platform tvOS
```

Nếu runtime thiếu, integration test in `BLOCKED: <platform> runtime missing` và skip. Unit test, contract test và CLI JSON test vẫn phải xanh. Không sửa test để fail vì thiếu runtime; không tự tải trong CI.
```

- [ ] **Step 5: Viết test inventory**

Create `Tests/OpenSimBridgeTests/PlatformRuntimeInventoryTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class PlatformRuntimeInventoryTests: XCTestCase {
    private struct FakeRuntimes: RuntimeControlling {
        var values: [Runtime]
        func listRuntimes() async throws -> [Runtime] { values }
        func installRuntime(at path: String) async throws -> Runtime { values[0] }
        func deleteRuntime(_ id: RuntimeID) async throws {}
    }

    private func runtime(_ platform: Platform, available: Bool = true) -> Runtime {
        Runtime(
            id: RuntimeID(rawValue: "com.apple.CoreSimulator.SimRuntime.\(platform.rawValue)-27-0"),
            name: "\(platform.rawValue) 27.0",
            platform: platform,
            version: "27.0",
            build: "24A100",
            isAvailable: available,
            path: "/tmp/\(platform.rawValue)"
        )
    }

    func testMatrixReportsMissingWatchAndTV() async throws {
        let inventory = PlatformRuntimeInventory(runtimes: FakeRuntimes(values: [runtime(.iOS)]))
        let matrix = try await inventory.matrix()
        XCTAssertEqual(matrix.readyPlatforms, [.iOS])
        XCTAssertEqual(matrix.blockedPlatforms, [.watchOS, .tvOS])
    }

    func testUnavailableRuntimeIsBlocked() async throws {
        let inventory = PlatformRuntimeInventory(
            runtimes: FakeRuntimes(values: [runtime(.watchOS, available: false)])
        )
        let status = try await inventory.status(for: .watchOS)
        XCTAssertFalse(status.isReady)
        XCTAssertEqual(status.blockingReason, "BLOCKED: watchOS runtime missing")
    }
}
```

- [ ] **Step 6: Chạy test để thấy pass**

Run:

```bash
chmod +x Scripts/install-platform-runtimes.sh
swift test --filter OpenSimCoreTests.PlatformRuntimeStatusTests
swift test --filter OpenSimCoreTests.RuntimeDownloadPolicyTests
swift test --filter OpenSimBridgeTests.PlatformRuntimeInventoryTests
```

Expected: PASS 6 test. Không chạy script cài runtime trong bước này.

- [ ] **Step 7: Commit**

```bash
git add Sources/OpenSimCore/Platform/PlatformRuntimeStatus.swift Sources/OpenSimBridge/Services/PlatformRuntimeInventory.swift Scripts/install-platform-runtimes.sh docs/platform-runtimes.md Tests/OpenSimCoreTests/PlatformRuntimeStatusTests.swift Tests/OpenSimCoreTests/RuntimeDownloadPolicyTests.swift Tests/OpenSimBridgeTests/PlatformRuntimeInventoryTests.swift
git commit -m "feat(platform): add runtime inventory and owner approval gate"
```

---

### Task 3: Pairing protocol và simctl controller

**Files:**
- Create: `Sources/OpenSimCore/Platform/Pairing.swift`
- Create: `Sources/OpenSimBridge/Services/SimctlPairingController.swift`
- Test: `Tests/OpenSimCoreTests/PairingValidationTests.swift`
- Test: `Tests/OpenSimBridgeTests/SimctlPairingControllerTests.swift`

**Interfaces:**
- Consumes: `DeviceControlling`, `Device`, `DeviceID`, `Platform`, `OpenSimError`.
- Produces: `PairingState`, `DevicePair`, `PairingControlling`, `PairingValidation`, `SimctlCommandRunning`, `SimctlPairingController`.

- [ ] **Step 1: Viết test validation thất bại**

Create `Tests/OpenSimCoreTests/PairingValidationTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class PairingValidationTests: XCTestCase {
    private func device(_ id: String, platform: Platform) -> Device {
        Device(
            id: DeviceID(rawValue: id),
            name: id,
            platform: platform,
            deviceType: "fixture",
            runtime: RuntimeID(rawValue: "runtime"),
            state: .shutdown,
            isAvailable: true,
            dataPath: nil,
            lastBootedAt: nil
        )
    }

    func testWatchAndPhoneAreValid() throws {
        let validation = PairingValidation()
        XCTAssertNoThrow(
            try validation.validate(
                watch: device("WATCH", platform: .watchOS),
                phone: device("PHONE", platform: .iOS)
            )
        )
    }

    func testReversedPairIsRejected() {
        let validation = PairingValidation()
        XCTAssertThrowsError(
            try validation.validate(
                watch: device("WATCH", platform: .iOS),
                phone: device("PHONE", platform: .watchOS)
            )
        )
    }

    func testSameDeviceIsRejected() {
        let validation = PairingValidation()
        XCTAssertThrowsError(
            try validation.validate(
                watch: device("SAME", platform: .watchOS),
                phone: device("SAME", platform: .iOS)
            )
        )
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimCoreTests.PairingValidationTests
```

Expected: FAIL vì `PairingValidation` chưa tồn tại.

- [ ] **Step 3: Viết pairing types**

Create `Sources/OpenSimCore/Platform/Pairing.swift`:

```swift
import Foundation

public enum PairingState: String, Codable, Sendable {
    case paired
    case unpaired
    case pending
    case unknown
}

public struct DevicePair: Codable, Sendable, Equatable {
    public var watchID: DeviceID
    public var phoneID: DeviceID
    public var state: PairingState

    public init(watchID: DeviceID, phoneID: DeviceID, state: PairingState) {
        self.watchID = watchID
        self.phoneID = phoneID
        self.state = state
    }
}

public protocol PairingControlling: Sendable {
    func pair(watch: DeviceID, phone: DeviceID) async throws -> DevicePair
    func unpair(watch: DeviceID) async throws
    func pairState(watch: DeviceID) async throws -> DevicePair?
}

public struct PairingValidation: Sendable {
    public init() {}

    public func validate(watch: Device, phone: Device) throws {
        guard watch.id != phone.id else {
            throw OpenSimError(
                code: "invalid_argument",
                message: "Watch and phone must be different devices",
                details: ["device": watch.id.rawValue],
                recovery: "Choose two different simulator devices",
                retryable: false
            )
        }
        guard watch.platform == .watchOS else {
            throw OpenSimError(
                code: "invalid_argument",
                message: "First device must be watchOS",
                details: ["platform": watch.platform.rawValue],
                recovery: "Pass a watchOS device as --watch",
                retryable: false
            )
        }
        guard phone.platform == .iOS else {
            throw OpenSimError(
                code: "invalid_argument",
                message: "Second device must be iOS",
                details: ["platform": phone.platform.rawValue],
                recovery: "Pass an iOS device as --phone",
                retryable: false
            )
        }
    }
}
```

- [ ] **Step 4: Viết simctl controller**

Create `Sources/OpenSimBridge/Services/SimctlPairingController.swift`:

```swift
import Foundation
import OpenSimCore

public protocol SimctlCommandRunning: Sendable {
    func run(_ arguments: [String]) async throws -> Data
}

public struct ProcessSimctlCommandRunner: SimctlCommandRunning {
    public init() {}

    public func run(_ arguments: [String]) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl"] + arguments
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw OpenSimError(
                    code: "simctl_failed",
                    message: message.isEmpty ? "simctl exited with \(process.terminationStatus)" : message,
                    details: ["arguments": arguments.joined(separator: " ")],
                    recovery: "Run `xcrun simctl \(arguments.joined(separator: " "))` manually",
                    retryable: false
                )
            }
            return data
        }.value
    }
}

public struct SimctlPairingController: PairingControlling {
    private let devices: any DeviceControlling
    private let runner: any SimctlCommandRunning
    private let validation = PairingValidation()

    public init(devices: any DeviceControlling, runner: any SimctlCommandRunning = ProcessSimctlCommandRunner()) {
        self.devices = devices
        self.runner = runner
    }

    public func pair(watch: DeviceID, phone: DeviceID) async throws -> DevicePair {
        let watchDevice = try await devices.device(watch)
        let phoneDevice = try await devices.device(phone)
        try validation.validate(watch: watchDevice, phone: phoneDevice)
        _ = try await runner.run(["pair", watch.rawValue, phone.rawValue])
        return DevicePair(watchID: watch, phoneID: phone, state: .paired)
    }

    public func unpair(watch: DeviceID) async throws {
        _ = try await runner.run(["unpair", watch.rawValue])
    }

    public func pairState(watch: DeviceID) async throws -> DevicePair? {
        let data = try await runner.run(["list", "pairs", "-j"])
        let document = try JSONDecoder().decode(PairsDocument.self, from: data)
        return document.pairs.first { $0.watchUDID == watch.rawValue }
            .map { DevicePair(watchID: watch, phoneID: DeviceID(rawValue: $0.phoneUDID), state: .paired) }
    }
}

private struct PairsDocument: Decodable {
    struct Pair: Decodable {
        var watchUDID: String
        var phoneUDID: String
    }

    var pairs: [Pair]
}
```

`simctl list pairs -j` thực tế trả object keyed theo watch UDID; nếu Plan 1 đã có parser, dùng parser đó. Test dưới đây dùng fixture JSON dạng `pairs` array để khóa behavior; integration test Task 9 xác minh với simctl thật.

- [ ] **Step 5: Viết test controller**

Create `Tests/OpenSimBridgeTests/SimctlPairingControllerTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class SimctlPairingControllerTests: XCTestCase {
    private actor RecordingRunner: SimctlCommandRunning {
        var calls: [[String]] = []
        var output: Data = Data("{}".utf8)

        func setOutput(_ data: Data) { output = data }

        func run(_ arguments: [String]) async throws -> Data {
            calls.append(arguments)
            return output
        }
    }

    private struct FakeDevices: DeviceControlling {
        var values: [Device]
        func listDevices() async throws -> [Device] { values }
        func device(_ id: DeviceID) async throws -> Device {
            guard let value = values.first(where: { $0.id == id }) else {
                throw OpenSimError(code: "device_not_found", message: "missing", details: [:], recovery: nil, retryable: false)
            }
            return value
        }
        func createDevice(name: String, deviceType: String, runtime: RuntimeID?) async throws -> Device { values[0] }
        func cloneDevice(_ id: DeviceID, name: String) async throws -> Device { values[0] }
        func boot(_ id: DeviceID, wait: Bool) async throws -> Device { values[0] }
        func shutdown(_ id: DeviceID, wait: Bool) async throws -> Device { values[0] }
        func erase(_ id: DeviceID) async throws -> Device { values[0] }
        func delete(_ id: DeviceID) async throws {}
        func rename(_ id: DeviceID, to name: String) async throws -> Device { values[0] }
        func pair(watch: DeviceID, phone: DeviceID) async throws {}
    }

    private func device(_ id: String, _ platform: Platform) -> Device {
        Device(
            id: DeviceID(rawValue: id),
            name: id,
            platform: platform,
            deviceType: "fixture",
            runtime: RuntimeID(rawValue: "runtime"),
            state: .shutdown,
            isAvailable: true,
            dataPath: nil,
            lastBootedAt: nil
        )
    }

    func testPairSendsWatchThenPhone() async throws {
        let runner = RecordingRunner()
        let controller = SimctlPairingController(
            devices: FakeDevices(values: [device("WATCH", .watchOS), device("PHONE", .iOS)]),
            runner: runner
        )
        let pair = try await controller.pair(
            watch: DeviceID(rawValue: "WATCH"),
            phone: DeviceID(rawValue: "PHONE")
        )
        XCTAssertEqual(pair.state, .paired)
        let calls = await runner.calls
        XCTAssertEqual(calls, [["pair", "WATCH", "PHONE"]])
    }

    func testUnpairAndStateParsing() async throws {
        let runner = RecordingRunner()
        await runner.setOutput(
            Data("{\"pairs\":[{\"watchUDID\":\"WATCH\",\"phoneUDID\":\"PHONE\"}]}".utf8)
        )
        let controller = SimctlPairingController(
            devices: FakeDevices(values: [device("WATCH", .watchOS), device("PHONE", .iOS)]),
            runner: runner
        )
        let state = try await controller.pairState(watch: DeviceID(rawValue: "WATCH"))
        XCTAssertEqual(state?.phoneID.rawValue, "PHONE")
        try await controller.unpair(watch: DeviceID(rawValue: "WATCH"))
        let calls = await runner.calls
        XCTAssertEqual(calls, [["list", "pairs", "-j"], ["unpair", "WATCH"]])
    }
}
```

- [ ] **Step 6: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimCoreTests.PairingValidationTests
swift test --filter OpenSimBridgeTests.SimctlPairingControllerTests
```

Expected: PASS 5 test.

- [ ] **Step 7: Commit**

```bash
git add Sources/OpenSimCore/Platform/Pairing.swift Sources/OpenSimBridge/Services/SimctlPairingController.swift Tests/OpenSimCoreTests/PairingValidationTests.swift Tests/OpenSimBridgeTests/SimctlPairingControllerTests.swift
git commit -m "feat(platform): add pairing protocol and simctl controller"
```

### Task 4: Fixture watchOS và tvOS

**Files:**
- Create: `Fixtures/OpenSimFixtureWatch/project.yml`
- Create: `Fixtures/OpenSimFixtureWatch/Sources/OpenSimFixtureWatchApp.swift`
- Create: `Fixtures/OpenSimFixtureWatch/Sources/ContentView.swift`
- Create: `Fixtures/OpenSimFixtureWatch/Info.plist`
- Create: `Fixtures/OpenSimFixtureWatch/build.sh`
- Create: `Fixtures/OpenSimFixtureTV/project.yml`
- Create: `Fixtures/OpenSimFixtureTV/Sources/OpenSimFixtureTVApp.swift`
- Create: `Fixtures/OpenSimFixtureTV/Sources/ContentView.swift`
- Create: `Fixtures/OpenSimFixtureTV/Info.plist`
- Create: `Fixtures/OpenSimFixtureTV/build.sh`

**Interfaces:**
- Consumes: watchOS/tvOS simulator SDK từ Xcode 27.1; không cần runtime để build.
- Produces: `OpenSimFixtureWatch.app` bundle ID `dev.opensim.fixture.watch`; `OpenSimFixtureTV.app` bundle ID `dev.opensim.fixture.tv`; accessibility identifier `watch-button`, `watch-count`, `tv-button`, `tv-count`.

- [ ] **Step 1: Viết watch fixture**

Create `Fixtures/OpenSimFixtureWatch/project.yml`:

```yaml
name: OpenSimFixtureWatch
options:
  bundleIdPrefix: dev.opensim.fixture
  deploymentTarget:
    watchOS: "11.0"
targets:
  OpenSimFixtureWatch:
    type: application
    platform: watchOS
    sources:
      - path: Sources
    info:
      path: Info.plist
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.opensim.fixture.watch
        PRODUCT_NAME: OpenSimFixtureWatch
        TARGETED_DEVICE_FAMILY: "4"
        GENERATE_INFOPLIST_FILE: NO
        SWIFT_VERSION: "6.0"
schemes:
  OpenSimFixtureWatch:
    build:
      targets:
        OpenSimFixtureWatch: all
    run:
      config: Debug
```

Create `Fixtures/OpenSimFixtureWatch/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>OpenSim Watch Fixture</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>WKApplication</key>
    <true/>
    <key>WKWatchOnly</key>
    <true/>
</dict>
</plist>
```

Create `Fixtures/OpenSimFixtureWatch/Sources/OpenSimFixtureWatchApp.swift`:

```swift
import SwiftUI

@main
struct OpenSimFixtureWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

Create `Fixtures/OpenSimFixtureWatch/Sources/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @State private var taps = 0

    var body: some View {
        VStack(spacing: 10) {
            Text("OpenSim Watch")
                .font(.headline)
                .accessibilityIdentifier("watch-label")
            Button("Tap") {
                taps += 1
            }
            .accessibilityIdentifier("watch-button")
            Text("Taps \(taps)")
                .accessibilityIdentifier("watch-count")
        }
        .padding()
    }
}
```

Create `Fixtures/OpenSimFixtureWatch/build.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
cd "$ROOT"
xcodegen generate --spec project.yml
xcodebuild \
  -project OpenSimFixtureWatch.xcodeproj \
  -scheme OpenSimFixtureWatch \
  -sdk watchsimulator \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath build \
  build
print "APP $ROOT/build/Build/Products/Debug-watchsimulator/OpenSimFixtureWatch.app"
```

- [ ] **Step 2: Viết tv fixture**

Create `Fixtures/OpenSimFixtureTV/project.yml`:

```yaml
name: OpenSimFixtureTV
options:
  bundleIdPrefix: dev.opensim.fixture
  deploymentTarget:
    tvOS: "17.0"
targets:
  OpenSimFixtureTV:
    type: application
    platform: tvOS
    sources:
      - path: Sources
    info:
      path: Info.plist
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.opensim.fixture.tv
        PRODUCT_NAME: OpenSimFixtureTV
        TARGETED_DEVICE_FAMILY: "3"
        GENERATE_INFOPLIST_FILE: NO
        SWIFT_VERSION: "6.0"
schemes:
  OpenSimFixtureTV:
    build:
      targets:
        OpenSimFixtureTV: all
    run:
      config: Debug
```

Create `Fixtures/OpenSimFixtureTV/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>OpenSim TV Fixture</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
```

Create `Fixtures/OpenSimFixtureTV/Sources/OpenSimFixtureTVApp.swift`:

```swift
import SwiftUI

@main
struct OpenSimFixtureTVApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

Create `Fixtures/OpenSimFixtureTV/Sources/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @State private var taps = 0

    var body: some View {
        VStack(spacing: 30) {
            Text("OpenSim TV")
                .font(.largeTitle)
                .accessibilityIdentifier("tv-label")
            Button("Select") {
                taps += 1
            }
            .buttonStyle(.card)
            .accessibilityIdentifier("tv-button")
            Text("Taps \(taps)")
                .font(.title2)
                .accessibilityIdentifier("tv-count")
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Create `Fixtures/OpenSimFixtureTV/build.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
cd "$ROOT"
xcodegen generate --spec project.yml
xcodebuild \
  -project OpenSimFixtureTV.xcodeproj \
  -scheme OpenSimFixtureTV \
  -sdk appletvsimulator \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath build \
  build
print "APP $ROOT/build/Build/Products/Debug-appletvsimulator/OpenSimFixtureTV.app"
```

- [ ] **Step 3: Build cả hai fixture**

Run:

```bash
chmod +x Fixtures/OpenSimFixtureWatch/build.sh Fixtures/OpenSimFixtureTV/build.sh
Fixtures/OpenSimFixtureWatch/build.sh
Fixtures/OpenSimFixtureTV/build.sh
```

Expected: hai lần `** BUILD SUCCEEDED **`; in ra đường dẫn `.app`. Bước này chỉ dùng SDK, không cần runtime và không tải gì.

- [ ] **Step 4: Commit**

```bash
git add Fixtures/OpenSimFixtureWatch Fixtures/OpenSimFixtureTV
git commit -m "test(fixtures): add watchOS and tvOS fixture apps"
```

---

### Task 5: CLI pair/unpair, doctor platform matrix và MCP device_pair

**Files:**
- Create: `Sources/OpenSimCLI/Output/PlatformMatrixTable.swift`
- Modify: `Sources/OpenSimCore/Domain/Doctor.swift` (Plan 1)
- Modify: `Sources/OpenSimCLI/Commands/DoctorCommand.swift` (Plan 1)
- Modify: `Sources/OpenSimCLI/Commands/DeviceCommand.swift` (Plan 1)
- Modify: `Sources/OpenSimMCP/Tools/DeviceTools.swift` (Plan 3)
- Test: `Tests/OpenSimCLITests/PlatformCommandTests.swift`

**Interfaces:**
- Consumes: `PairingControlling`, `DevicePair`, `PlatformRuntimeMatrixSummary`, `PlatformRuntimeInventory`, `Envelope`.
- Produces: `PlatformMatrixTable.render(_:)`, `PlatformCommandRunner.pair(watch:phone:json:)`, `PlatformCommandRunner.unpair(watch:json:)`, `PlatformCommandRunner.doctorMatrix(_:json:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimCLITests/PlatformCommandTests.swift`:

```swift
import XCTest
@testable import OpenSimCLI
@testable import OpenSimCore

final class PlatformCommandTests: XCTestCase {
    private struct FakePairing: PairingControlling {
        var paired: DevicePair?
        func pair(watch: DeviceID, phone: DeviceID) async throws -> DevicePair {
            DevicePair(watchID: watch, phoneID: phone, state: .paired)
        }
        func unpair(watch: DeviceID) async throws {}
        func pairState(watch: DeviceID) async throws -> DevicePair? { paired }
    }

    func testPairJSONEnvelopeContainsPair() async throws {
        let runner = PlatformCommandRunner(
            pairing: FakePairing(paired: nil),
            requestID: { "req-fixed" },
            durationMs: { 0 }
        )
        let output = try await runner.pair(
            watch: DeviceID(rawValue: "WATCH"),
            phone: DeviceID(rawValue: "PHONE"),
            json: true
        )
        let envelope = try JSONDecoder().decode(Envelope<DevicePair>.self, from: Data(output.utf8))
        XCTAssertEqual(envelope.data?.watchID.rawValue, "WATCH")
        XCTAssertEqual(envelope.data?.state, .paired)
    }

    func testDoctorMatrixShowsBlockedWatchAndTV() throws {
        let summary = PlatformRuntimeMatrixSummary(
            statuses: [
                PlatformRuntimeStatus(platform: .iOS, installedRuntimes: [], isReady: true, blockingReason: nil),
                PlatformRuntimeStatus.missing(for: .watchOS),
                PlatformRuntimeStatus.missing(for: .tvOS)
            ]
        )
        let output = PlatformMatrixTable.render(summary)
        XCTAssertTrue(output.contains("watchOS"))
        XCTAssertTrue(output.contains("BLOCKED"))
        XCTAssertTrue(output.contains("tvOS"))
    }

    func testUnpairUsesWatchIdentifier() async throws {
        let runner = PlatformCommandRunner(pairing: FakePairing(paired: nil))
        let output = try await runner.unpair(watch: DeviceID(rawValue: "WATCH"), json: true)
        XCTAssertTrue(output.contains("unpaired"))
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimCLITests.PlatformCommandTests
```

Expected: FAIL vì `PlatformCommandRunner` chưa tồn tại.

- [ ] **Step 3: Viết bảng và runner**

Create `Sources/OpenSimCLI/Output/PlatformMatrixTable.swift`:

```swift
import Foundation
import OpenSimCore

public enum PlatformMatrixTable {
    public static func render(_ summary: PlatformRuntimeMatrixSummary) -> String {
        var lines: [String] = ["PLATFORM   READY   RUNTIMES   NOTE"]
        for status in summary.statuses {
            let versions = status.installedRuntimes.map(\.version).joined(separator: ",")
            let note = status.blockingReason ?? ""
            lines.append(
                "\(status.platform.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(status.isReady ? "yes  " : "no   ")  \(versions.padding(toLength: 10, withPad: " ", startingAt: 0)) \(note)"
            )
        }
        return lines.joined(separator: "\n")
    }
}

public struct PlatformCommandRunner: Sendable {
    private let pairing: any PairingControlling
    private let requestID: @Sendable () -> String
    private let durationMs: @Sendable () -> Int

    public init(
        pairing: any PairingControlling,
        requestID: @escaping @Sendable () -> String = { UUID().uuidString },
        durationMs: @escaping @Sendable () -> Int = { 0 }
    ) {
        self.pairing = pairing
        self.requestID = requestID
        self.durationMs = durationMs
    }

    public func pair(watch: DeviceID, phone: DeviceID, json: Bool) async throws -> String {
        let pair = try await pairing.pair(watch: watch, phone: phone)
        if json {
            return try Self.envelope(pair, requestID: requestID(), durationMs: durationMs())
        }
        return "paired \(pair.watchID.rawValue) with \(pair.phoneID.rawValue)"
    }

    public func unpair(watch: DeviceID, json: Bool) async throws -> String {
        try await pairing.unpair(watch: watch)
        let payload = ["state": "unpaired", "watch": watch.rawValue]
        if json {
            return try Self.envelope(payload, requestID: requestID(), durationMs: durationMs())
        }
        return "unpaired \(watch.rawValue)"
    }

    public func doctorMatrix(_ summary: PlatformRuntimeMatrixSummary, json: Bool) throws -> String {
        if json {
            return try Self.envelope(summary, requestID: requestID(), durationMs: durationMs())
        }
        return PlatformMatrixTable.render(summary)
    }

    private static func envelope<T: Codable & Sendable>(
        _ data: T,
        requestID: String,
        durationMs: Int
    ) throws -> String {
        let envelope = Envelope(
            schemaVersion: 1,
            ok: true,
            data: data,
            error: nil,
            meta: ResponseMeta(requestId: requestID, durationMs: durationMs)
        )
        let encoded = try JSONEncoder.iso8601.encode(envelope)
        return String(decoding: encoded, as: UTF8.self)
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
```

- [ ] **Step 4: Nối doctor, device command và MCP**

Trong `Sources/OpenSimCore/Domain/Doctor.swift`, thêm field `platforms` vào `DoctorReport` với default rỗng để không phá init hiện có:

```swift
public var platforms: [PlatformRuntimeStatus]

// Thêm cuối danh sách tham số của init:
platforms: [PlatformRuntimeStatus] = []
```

Trong `Sources/OpenSimCLI/Commands/DoctorCommand.swift`, thêm sau khi tạo report:

```swift
let inventory = PlatformRuntimeInventory(runtimes: bridge.runtimes)
let matrix = try await inventory.matrix()
report.platforms = matrix.statuses
if json {
    print(try PlatformCommandRunner(
        pairing: SimctlPairingController(devices: bridge.devices)
    ).doctorMatrix(matrix, json: true))
}
```

`report.platforms` là field mới thêm vào `DoctorReport` của Plan 1 với default `[]`; không đổi field cũ.

Trong `Sources/OpenSimCLI/Commands/DeviceCommand.swift`, thêm hai subcommand vào `subcommands`:

```swift
struct Pair: AsyncParsableCommand {
    @Option(name: .long) var watch: String
    @Option(name: .long) var phone: String
    @Flag(name: .long) var json = false

    func run() async throws {
        let bridge = try BridgeFactory.make()
        let watchID = try await resolveDeviceID(watch, devices: bridge.devices)
        let phoneID = try await resolveDeviceID(phone, devices: bridge.devices)
        let runner = PlatformCommandRunner(
            pairing: SimctlPairingController(devices: bridge.devices)
        )
        print(try await runner.pair(watch: watchID, phone: phoneID, json: json))
    }
}

struct Unpair: AsyncParsableCommand {
    @Option(name: .long) var watch: String
    @Flag(name: .long) var json = false

    func run() async throws {
        let bridge = try BridgeFactory.make()
        let watchID = try await resolveDeviceID(watch, devices: bridge.devices)
        let runner = PlatformCommandRunner(
            pairing: SimctlPairingController(devices: bridge.devices)
        )
        print(try await runner.unpair(watch: watchID, json: json))
    }
}
```

Trong `Sources/OpenSimMCP/Tools/DeviceTools.swift`, handler `device_pair` gọi:

```swift
let pair = try await pairing.pair(
    watch: DeviceID(rawValue: arguments.watch),
    phone: DeviceID(rawValue: arguments.phone)
)
return try JSONEncoder.iso8601.encode(pair)
```

`pairing` được inject từ daemon composition; nếu Plan 3 đã có `device_pair` handler, thay phần gọi `simctl pair` bằng `SimctlPairingController` và giữ schema.

- [ ] **Step 5: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimCLITests.PlatformCommandTests
swift test --filter OpenSimBridgeTests.SimctlPairingControllerTests
```

Expected: PASS 5 test.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenSimCLI/Output/PlatformMatrixTable.swift Sources/OpenSimCore/Domain/Doctor.swift Sources/OpenSimCLI/Commands/DoctorCommand.swift Sources/OpenSimCLI/Commands/DeviceCommand.swift Sources/OpenSimMCP/Tools/DeviceTools.swift Tests/OpenSimCLITests/PlatformCommandTests.swift
git commit -m "feat(cli): add watch pairing and platform doctor matrix"
```

---

### Task 6: App toolbar theo platform adapter

**Files:**
- Create: `App/Sources/OpenSimApp/Windows/PlatformToolbarAdapter.swift`
- Modify: `App/Sources/OpenSimApp/Windows/DeviceWindowToolbar.swift` (Plan 4)
- Modify: `App/Sources/OpenSimApp/Windows/DeviceWindowController.swift` (Plan 4)
- Test: `Tests/OpenSimAppUITests/PlatformWindowUITests.swift`

**Interfaces:**
- Consumes: `PlatformAdapter`, `PlatformRegistry`, `PlatformInputMap`, `HardwareButton`, `InputGesture`.
- Produces: `PlatformToolbarAdapter.visibleButtons(from:)`, `PlatformToolbarAdapter.isEnabled(_:)`.

- [ ] **Step 1: Viết UI test thất bại**

Create `Tests/OpenSimAppUITests/PlatformWindowUITests.swift`:

```swift
import XCTest

final class PlatformWindowUITests: XCTestCase {
    private func runtimeInstalled(_ platform: String) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "runtimes", "-j"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let runtimes = object?["runtimes"] as? [[String: Any]] ?? []
        return runtimes.contains { entry in
            let name = entry["name"] as? String ?? ""
            return name.contains(platform) && (entry["isAvailable"] as? Bool ?? false)
        }
    }

    func testWatchWindowShowsPlatformButtons() throws {
        guard try runtimeInstalled("watchOS") else {
            throw XCTSkip("BLOCKED: watchOS runtime missing")
        }
        let app = XCUIApplication()
        app.launchEnvironment["OPENSIM_TESTING"] = "1"
        app.launch()
        app.buttons["sidebar-watch-device"].click()
        XCTAssertTrue(app.buttons["device-button-side"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["device-button-lock"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["device-gesture-pinch"].exists)
    }

    func testTVWindowShowsRemoteButtons() throws {
        guard try runtimeInstalled("tvOS") else {
            throw XCTSkip("BLOCKED: tvOS runtime missing")
        }
        let app = XCUIApplication()
        app.launchEnvironment["OPENSIM_TESTING"] = "1"
        app.launch()
        app.buttons["sidebar-tv-device"].click()
        XCTAssertTrue(app.buttons["device-button-appleTVSelect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["device-button-appleTVMenu"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["device-button-appleTVHome"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["device-gesture-pinch"].exists)
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
xcodegen generate --spec App/project.yml
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -only-testing:OpenSimAppUITests/PlatformWindowUITests
```

Expected: FAIL hoặc SKIP khi runtime thiếu; với runtime có sẵn, FAIL vì toolbar chưa dùng adapter.

- [ ] **Step 3: Viết adapter**

Create `App/Sources/OpenSimApp/Windows/PlatformToolbarAdapter.swift`:

```swift
import Foundation
import OpenSimCore

public struct PlatformToolbarAdapter: Sendable {
    public let adapter: any PlatformAdapter

    public init(adapter: any PlatformAdapter) {
        self.adapter = adapter
    }

    public func visibleButtons(from buttons: [HardwareButton]) -> [HardwareButton] {
        buttons.filter { adapter.inputMap.hardwareButtons.contains($0) }
    }

    public func isEnabled(_ gesture: InputGesture) -> Bool {
        adapter.inputMap.supportedGestures.contains(gesture)
    }

    public func shouldShowCoordinateTap() -> Bool {
        adapter.inputMap.supportsCoordinateTap
    }

    public func shouldShowFocusNavigation() -> Bool {
        adapter.inputMap.focusNavigation
    }

    public func accessibilityIdentifier(for button: HardwareButton) -> String {
        "device-button-\(button.rawValue)"
    }
}
```

- [ ] **Step 4: Nối toolbar và controller**

Trong `App/Sources/OpenSimApp/Windows/DeviceWindowController.swift`, lấy adapter:

```swift
let adapter = PlatformRegistry().adapter(forDeviceType: device.deviceType) ?? IOSPlatformAdapter()
let toolbarAdapter = PlatformToolbarAdapter(adapter: adapter)
```

Truyền `toolbarAdapter` vào `DeviceWindowToolbar`.

Trong `App/Sources/OpenSimApp/Windows/DeviceWindowToolbar.swift`, thay danh sách button cố định:

```swift
let allButtons: [HardwareButton] = [
    .home, .lock, .side, .volumeUp, .volumeDown,
    .appleTVSelect, .appleTVMenu, .appleTVHome
]
ForEach(toolbarAdapter.visibleButtons(from: allButtons), id: \.self) { button in
    Button(button.rawValue) {
        send(button)
    }
    .accessibilityIdentifier(toolbarAdapter.accessibilityIdentifier(for: button))
}
```

Và với gesture:

```swift
Button("Pinch") { setGesture(.pinch) }
    .disabled(!toolbarAdapter.isEnabled(.pinch))
    .accessibilityIdentifier("device-gesture-pinch")
Button("Rotate") { setGesture(.rotate) }
    .disabled(!toolbarAdapter.isEnabled(.rotate))
    .accessibilityIdentifier("device-gesture-rotate")
```

`HardwareButton.allCases` cần thêm `CaseIterable` vào enum contract; đây là additive conformance trong Plan 6, không đổi case. Nếu không muốn sửa contract, dùng mảng `[.home, .lock, .side, .volumeUp, .volumeDown, .appleTVSelect, .appleTVMenu, .appleTVHome]` trong toolbar.

- [ ] **Step 5: Chạy UI test**

Run:

```bash
xcodegen generate --spec App/project.yml
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -only-testing:OpenSimAppUITests/PlatformWindowUITests
```

Expected: PASS 2 test nếu runtime watch/tv có sẵn; nếu thiếu, mỗi test `SKIPPED` với `BLOCKED: <platform> runtime missing`.

- [ ] **Step 6: Commit**

```bash
git add App/Sources/OpenSimApp/Windows/PlatformToolbarAdapter.swift App/Sources/OpenSimApp/Windows/DeviceWindowToolbar.swift App/Sources/OpenSimApp/Windows/DeviceWindowController.swift Tests/OpenSimAppUITests/PlatformWindowUITests.swift
git commit -m "feat(app): drive device toolbar from platform adapters"
```

### Task 7: Runtime matrix boot, render và screenshot

**Files:**
- Create: `Tests/IntegrationTests/PlatformRuntimeMatrixTests.swift`

**Interfaces:**
- Consumes: `PlatformRuntimeInventory`, `PlatformRuntimeStatus`, `simctl`; fixture apps từ Task 4.
- Produces: test helper `SimctlPlatformHarness` dùng lại ở Task 8 và Task 9.

- [ ] **Step 1: Viết test matrix thất bại**

Create `Tests/IntegrationTests/PlatformRuntimeMatrixTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class PlatformRuntimeMatrixTests: XCTestCase {
    private struct SimctlDevice: Decodable {
        let udid: String
        let name: String
    }

    private struct SimctlList: Decodable {
        let devices: [String: [SimctlDevice]]
    }

    private struct RuntimeEntry: Decodable {
        let identifier: String
        let name: String
        let isAvailable: Bool
    }

    private struct RuntimeList: Decodable {
        let runtimes: [RuntimeEntry]
    }

    private struct DeviceTypeEntry: Decodable {
        let identifier: String
        let name: String
    }

    private struct DeviceTypeList: Decodable {
        let devicetypes: [DeviceTypeEntry]
    }

    private func simctl(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(domain: "simctl", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
        return data
    }

    private func runtime(for platform: Platform) throws -> RuntimeEntry? {
        let list = try JSONDecoder().decode(RuntimeList.self, from: simctl(["list", "runtimes", "-j"]))
        return list.runtimes.first {
            $0.isAvailable && $0.name.contains(platform.rawValue)
        }
    }

    private func deviceType(prefix: String) throws -> String {
        let list = try JSONDecoder().decode(
            DeviceTypeList.self,
            from: simctl(["list", "devicetypes", "-j"])
        )
        guard let value = list.devicetypes.first(where: { $0.identifier.contains(prefix) }) else {
            throw XCTSkip("No device type with prefix \(prefix)")
        }
        return value.identifier
    }

    private func assertPlatform(_ platform: Platform, runtimeName: String, deviceTypePrefix: String) throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENSIM_INTEGRATION=1 to run platform matrix tests")
        }
        guard let runtime = try runtime(for: platform) else {
            if platform == .iOS {
                XCTFail("iOS runtime is required")
                return
            }
            print("BLOCKED: \(platform.rawValue) runtime missing")
            throw XCTSkip("BLOCKED: \(platform.rawValue) runtime missing")
        }
        let deviceType = try deviceType(prefix: deviceTypePrefix)
        let name = "OpenSim Matrix \(platform.rawValue) \(UUID().uuidString.prefix(8))"
        let created = try simctl([
            "create", name, deviceType, runtime.identifier
        ])
        let udid = String(decoding: created, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        defer { _ = try? simctl(["delete", udid]) }

        _ = try simctl(["boot", udid])
        _ = try simctl(["bootstatus", udid, "-b"])
        let screenshot = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-matrix-\(udid).png")
        defer { try? FileManager.default.removeItem(at: screenshot) }
        _ = try simctl(["io", udid, "screenshot", screenshot.path])
        let attributes = try FileManager.default.attributesOfItem(atPath: screenshot.path)
        let size = attributes[.size] as? NSNumber ?? 0
        XCTAssertGreaterThan(size.intValue, 1_024)
        print("PASS \(platform.rawValue) runtime=\(runtimeName) device=\(udid)")
    }

    func testIOSBootsAndScreenshots() throws {
        try assertPlatform(.iOS, runtimeName: "iOS", deviceTypePrefix: "iPhone")
    }

    func testWatchBootsAndScreenshots() throws {
        try assertPlatform(.watchOS, runtimeName: "watchOS", deviceTypePrefix: "Apple-Watch")
    }

    func testTVBootsAndScreenshots() throws {
        try assertPlatform(.tvOS, runtimeName: "tvOS", deviceTypePrefix: "Apple-TV")
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail hoặc skip có kiểm soát**

Run:

```bash
swift test --filter IntegrationTests.PlatformRuntimeMatrixTests
```

Expected: iOS PASS khi có runtime; watch/tv `SKIPPED` với `BLOCKED: watchOS runtime missing` và `BLOCKED: tvOS runtime missing` nếu chưa cài. Không tải runtime.

- [ ] **Step 3: Chạy lại khi owner đã cài runtime**

Run:

```bash
Scripts/install-platform-runtimes.sh --owner-approved
swift test --filter IntegrationTests.PlatformRuntimeMatrixTests
```

Expected: cả 3 test PASS; log có `PASS watchOS` và `PASS tvOS`. Chỉ chạy lệnh đầu khi owner đã đồng ý rõ ràng.

- [ ] **Step 4: Commit**

```bash
git add Tests/IntegrationTests/PlatformRuntimeMatrixTests.swift
git commit -m "test(platform): add runtime matrix boot and screenshot tests"
```

---

### Task 8: Watch fixture flow, tap và pairing

**Files:**
- Create: `Tests/IntegrationTests/WatchIntegrationTests.swift`
- Create: `Tests/IntegrationTests/PlatformPairingTests.swift`
- Create: `Tests/IntegrationTests/PlatformTestSupport.swift`

**Interfaces:**
- Consumes: `simctl`, fixture watch từ Task 4, CLI `opensim ui tap` từ Plan 2, CLI `device pair/unpair` từ Task 5.
- Produces: `PlatformTestSupport` helper dùng chung; test watch boot/install/launch/screenshot/tap và pair/unpair.

- [ ] **Step 1: Viết helper và test watch thất bại**

Create `Tests/IntegrationTests/PlatformTestSupport.swift`:

```swift
import Foundation

enum PlatformTestSupport {
    static func simctl(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(domain: "simctl", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
        return data
    }

    static func runOpenSim(_ arguments: [String]) throws -> Data {
        let binary = ProcessInfo.processInfo.environment["OPENSIM_BIN"]
            ?? ".build/debug/opensim"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(domain: "opensim", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
        return data
    }

    static func screenshotHash(udid: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-shot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try simctl(["io", udid, "screenshot", url.path])
        let data = try Data(contentsOf: url)
        var hash: UInt64 = 1469598103934665603
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash)
    }
}
```

Create `Tests/IntegrationTests/WatchIntegrationTests.swift`:

```swift
import XCTest

final class WatchIntegrationTests: XCTestCase {
    func testWatchFixtureTapChangesScreen() throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENSIM_INTEGRATION=1 to run watch integration tests")
        }
        let runtimes = try PlatformTestSupport.simctl(["list", "runtimes", "-j"])
        let runtimeObject = try JSONSerialization.jsonObject(with: runtimes) as? [String: Any]
        let runtimeList = runtimeObject?["runtimes"] as? [[String: Any]] ?? []
        guard let watchRuntime = runtimeList.first(where: {
            ($0["name"] as? String ?? "").contains("watchOS") && ($0["isAvailable"] as? Bool ?? false)
        })?["identifier"] as? String else {
            print("BLOCKED: watchOS runtime missing")
            throw XCTSkip("BLOCKED: watchOS runtime missing")
        }
        let typesData = try PlatformTestSupport.simctl(["list", "devicetypes", "-j"])
        let typesObject = try JSONSerialization.jsonObject(with: typesData) as? [String: Any]
        let types = typesObject?["devicetypes"] as? [[String: Any]] ?? []
        guard let deviceType = types.first(where: {
            ($0["identifier"] as? String ?? "").contains("Apple-Watch")
        })?["identifier"] as? String else {
            throw XCTSkip("No Apple Watch device type")
        }
        let name = "OpenSim Watch \(UUID().uuidString.prefix(8))"
        let created = try PlatformTestSupport.simctl(["create", name, deviceType, watchRuntime])
        let udid = String(decoding: created, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        defer { _ = try? PlatformTestSupport.simctl(["delete", udid]) }

        _ = try PlatformTestSupport.simctl(["boot", udid])
        _ = try PlatformTestSupport.simctl(["bootstatus", udid, "-b"])
        let app = "Fixtures/OpenSimFixtureWatch/build/Build/Products/Debug-watchsimulator/OpenSimFixtureWatch.app"
        _ = try PlatformTestSupport.simctl(["install", udid, app])
        _ = try PlatformTestSupport.simctl(["launch", udid, "dev.opensim.fixture.watch"])
        try? PlatformTestSupport.simctl(["terminate", udid, "dev.opensim.fixture.watch"])
        _ = try PlatformTestSupport.simctl(["launch", udid, "dev.opensim.fixture.watch"])
        let before = try PlatformTestSupport.screenshotHash(udid: udid)

        _ = try PlatformTestSupport.runOpenSim([
            "ui", "tap", "--device", udid, "--x", "208", "--y", "280", "--json"
        ])
        let after = try PlatformTestSupport.screenshotHash(udid: udid)
        XCTAssertNotEqual(before, after)
    }
}
```

Create `Tests/IntegrationTests/PlatformPairingTests.swift`:

```swift
import XCTest

final class PlatformPairingTests: XCTestCase {
    func testPairAndUnpairWatchWithPhone() throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENSIM_INTEGRATION=1 to run pairing integration tests")
        }
        let runtimes = try PlatformTestSupport.simctl(["list", "runtimes", "-j"])
        let runtimeObject = try JSONSerialization.jsonObject(with: runtimes) as? [String: Any]
        let runtimeList = runtimeObject?["runtimes"] as? [[String: Any]] ?? []
        guard let watchRuntime = runtimeList.first(where: {
            ($0["name"] as? String ?? "").contains("watchOS") && ($0["isAvailable"] as? Bool ?? false)
        })?["identifier"] as? String,
        let phoneRuntime = runtimeList.first(where: {
            ($0["name"] as? String ?? "").contains("iOS") && ($0["isAvailable"] as? Bool ?? false)
        })?["identifier"] as? String else {
            print("BLOCKED: watchOS runtime missing")
            throw XCTSkip("BLOCKED: watchOS runtime missing")
        }
        let typesData = try PlatformTestSupport.simctl(["list", "devicetypes", "-j"])
        let typesObject = try JSONSerialization.jsonObject(with: typesData) as? [String: Any]
        let types = typesObject?["devicetypes"] as? [[String: Any]] ?? []
        let watchType = types.first { ($0["identifier"] as? String ?? "").contains("Apple-Watch") }
        let phoneType = types.first { ($0["identifier"] as? String ?? "").contains("iPhone") }
        guard let watchTypeID = watchType?["identifier"] as? String,
              let phoneTypeID = phoneType?["identifier"] as? String else {
            throw XCTSkip("No watch or phone device type")
        }
        let watchName = "OpenSim Pair Watch \(UUID().uuidString.prefix(8))"
        let phoneName = "OpenSim Pair Phone \(UUID().uuidString.prefix(8))"
        let watchUDID = String(
            decoding: try PlatformTestSupport.simctl(["create", watchName, watchTypeID, watchRuntime]),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneUDID = String(
            decoding: try PlatformTestSupport.simctl(["create", phoneName, phoneTypeID, phoneRuntime]),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            _ = try? PlatformTestSupport.simctl(["unpair", watchUDID])
            _ = try? PlatformTestSupport.simctl(["delete", watchUDID])
            _ = try? PlatformTestSupport.simctl(["delete", phoneUDID])
        }

        let paired = try PlatformTestSupport.runOpenSim([
            "device", "pair", "--watch", watchUDID, "--phone", phoneUDID, "--json"
        ])
        let pairedText = String(decoding: paired, as: UTF8.self)
        XCTAssertTrue(pairedText.contains("\"ok\" : true") || pairedText.contains("\"ok\":true"))
        XCTAssertTrue(pairedText.contains(watchUDID))

        let unpaired = try PlatformTestSupport.runOpenSim([
            "device", "unpair", "--watch", watchUDID, "--json"
        ])
        XCTAssertTrue(String(decoding: unpaired, as: UTF8.self).contains("unpaired"))
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail hoặc skip**

Run:

```bash
swift build
Fixtures/OpenSimFixtureWatch/build.sh
swift test --filter IntegrationTests.WatchIntegrationTests
swift test --filter IntegrationTests.PlatformPairingTests
```

Expected: watch test PASS khi runtime + fixture có sẵn; nếu thiếu runtime, `SKIPPED` với `BLOCKED: watchOS runtime missing`. Pairing test PASS hoặc skip cùng lý do.

- [ ] **Step 3: Commit**

```bash
git add Tests/IntegrationTests/PlatformTestSupport.swift Tests/IntegrationTests/WatchIntegrationTests.swift Tests/IntegrationTests/PlatformPairingTests.swift
git commit -m "test(platform): add watch fixture flow and pairing integration"
```

---

### Task 9: TV fixture flow, capability reporting và tổng kiểm tra

**Files:**
- Create: `Tests/IntegrationTests/TVIntegrationTests.swift`
- Test: `Tests/IntegrationTests/PlatformRuntimeMatrixTests.swift` (thêm capability check)
- Test: `Tests/OpenSimCLITests/PlatformCommandTests.swift` (thêm doctor JSON)

**Interfaces:**
- Consumes: fixture tv Task 4, CLI `ui button`, `ui tap`, `doctor --json`.
- Produces: test tv select/menu/home, capability `watch`/`tv` trong doctor, tổng kết matrix.

- [ ] **Step 1: Viết test TV thất bại**

Create `Tests/IntegrationTests/TVIntegrationTests.swift`:

```swift
import XCTest

final class TVIntegrationTests: XCTestCase {
    func testTVFixtureSelectChangesScreen() throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENSIM_INTEGRATION=1 to run tv integration tests")
        }
        let runtimes = try PlatformTestSupport.simctl(["list", "runtimes", "-j"])
        let runtimeObject = try JSONSerialization.jsonObject(with: runtimes) as? [String: Any]
        let runtimeList = runtimeObject?["runtimes"] as? [[String: Any]] ?? []
        guard let tvRuntime = runtimeList.first(where: {
            ($0["name"] as? String ?? "").contains("tvOS") && ($0["isAvailable"] as? Bool ?? false)
        })?["identifier"] as? String else {
            print("BLOCKED: tvOS runtime missing")
            throw XCTSkip("BLOCKED: tvOS runtime missing")
        }
        let typesData = try PlatformTestSupport.simctl(["list", "devicetypes", "-j"])
        let typesObject = try JSONSerialization.jsonObject(with: typesData) as? [String: Any]
        let types = typesObject?["devicetypes"] as? [[String: Any]] ?? []
        guard let deviceType = types.first(where: {
            ($0["identifier"] as? String ?? "").contains("Apple-TV")
        })?["identifier"] as? String else {
            throw XCTSkip("No Apple TV device type")
        }
        let name = "OpenSim TV \(UUID().uuidString.prefix(8))"
        let created = try PlatformTestSupport.simctl(["create", name, deviceType, tvRuntime])
        let udid = String(decoding: created, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        defer { _ = try? PlatformTestSupport.simctl(["delete", udid]) }

        _ = try PlatformTestSupport.simctl(["boot", udid])
        _ = try PlatformTestSupport.simctl(["bootstatus", udid, "-b"])
        let app = "Fixtures/OpenSimFixtureTV/build/Build/Products/Debug-appletvsimulator/OpenSimFixtureTV.app"
        _ = try PlatformTestSupport.simctl(["install", udid, app])
        _ = try PlatformTestSupport.simctl(["launch", udid, "dev.opensim.fixture.tv"])
        let before = try PlatformTestSupport.screenshotHash(udid: udid)

        _ = try PlatformTestSupport.runOpenSim([
            "ui", "button", "--device", udid, "--button", "appleTVSelect", "--json"
        ])
        let after = try PlatformTestSupport.screenshotHash(udid: udid)
        XCTAssertNotEqual(before, after)
    }
}
```

- [ ] **Step 2: Thêm capability check vào matrix test**

Append vào `Tests/IntegrationTests/PlatformRuntimeMatrixTests.swift`:

```swift
    func testDoctorReportsPlatformCapabilities() throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENSIM_INTEGRATION=1 to run doctor platform tests")
        }
        let output = try PlatformTestSupport.runOpenSim(["doctor", "--json"])
        let object = try JSONSerialization.jsonObject(with: output) as? [String: Any]
        let data = object?["data"] as? [String: Any]
        let platforms = data?["platforms"] as? [[String: Any]] ?? []
        XCTAssertTrue(platforms.contains { ($0["platform"] as? String) == "iOS" })
        XCTAssertTrue(platforms.contains { ($0["platform"] as? String) == "watchOS" })
        XCTAssertTrue(platforms.contains { ($0["platform"] as? String) == "tvOS" })
    }
```

- [ ] **Step 3: Chạy test để thấy pass hoặc skip**

Run:

```bash
swift build
Fixtures/OpenSimFixtureTV/build.sh
swift test --filter IntegrationTests.TVIntegrationTests
swift test --filter IntegrationTests.PlatformRuntimeMatrixTests
```

Expected: tv PASS khi runtime + fixture có sẵn; nếu thiếu, `SKIPPED` với `BLOCKED: tvOS runtime missing`; doctor test PASS khi daemon/CLI chạy, hoặc skip theo integration gate. Không tải runtime.

- [ ] **Step 4: Chạy toàn bộ test Plan 6**

Run:

```bash
swift test --filter OpenSimCoreTests.PlatformAdapterTests
swift test --filter OpenSimCoreTests.PlatformRuntimeStatusTests
swift test --filter OpenSimCoreTests.RuntimeDownloadPolicyTests
swift test --filter OpenSimCoreTests.PairingValidationTests
swift test --filter OpenSimBridgeTests.PlatformRuntimeInventoryTests
swift test --filter OpenSimBridgeTests.SimctlPairingControllerTests
swift test --filter OpenSimCLITests.PlatformCommandTests
OPENSIM_INTEGRATION=1 swift test --filter IntegrationTests
```

Expected: unit/contract PASS; integration PASS khi runtime có, `SKIPPED` có thông điệp `BLOCKED` khi runtime thiếu. Không có test nào fail vì thiếu runtime watch/tv.

- [ ] **Step 5: Commit**

```bash
git add Tests/IntegrationTests/TVIntegrationTests.swift Tests/IntegrationTests/PlatformRuntimeMatrixTests.swift Tests/OpenSimCLITests/PlatformCommandTests.swift
git commit -m "test(platform): add tv flow and capability reporting"
```

---

## Spec coverage

| Mục spec | Nội dung | Task |
|---|---|---|
| 2 mục 6 | Hỗ trợ iOS/iPadOS, watchOS, tvOS | 1, 2, 7 |
| 5.4 | `doctor` capability `watch`, `tv`; fallback simctl | 2, 5, 9 |
| 6 | `Device`, `Runtime`, `HardwareButton`, `ScreenInfo` giữ nguyên | 1, 3 |
| 7.2 | `device pair`, `device unpair`; runtime list theo platform | 5 |
| 8.2 | `device_pair` MCP | 5, 8 |
| 9.2 | Toolbar theo platform, hardware button watch/tv | 6 |
| 9.3 | Không crash khi capability thiếu; disable gesture | 1, 6 |
| 10.1 | Runtime do người dùng cài; không xoá runtime hệ thống | 2 |
| 14.1 | Unit adapter, pair validation, runtime status | 1, 2, 3 |
| 14.2 | Fixture watch/tv; boot, screenshot, tap, pairing | 4, 7, 8, 9 |
| 14.4 | Ma trận Xcode/iOS/watch/tv; skip khi runtime thiếu | 7, 9 |
| 16 Plan 6 | Không đổi kiến trúc lõi; chỉ adapter + fixture | Toàn bộ |
| 17.1 mục 12 | watchOS/tvOS boot, render, screenshot, tap fixture | 7, 8, 9 |
| 18 | Rủi ro watch/tv khác input/render; runtime missing | 1, 2, 7 |

## Exit criteria

- `PlatformAdapter` trả descriptor và input map đúng cho iOS, watchOS, tvOS; watch không có pinch/rotate; tv dùng focus navigation.
- `PlatformRuntimeInventory` phân biệt ready/blocked; watch/tv thiếu runtime trả `BLOCKED: <platform> runtime missing`.
- Không source nào trong `Sources/`, `App/`, `Fixtures/` gọi `xcodebuild -downloadPlatform`; script cài runtime yêu cầu `--owner-approved` và chứa đúng hai lệnh `xcodebuild -downloadPlatform watchOS`, `xcodebuild -downloadPlatform tvOS`.
- Khi runtime watch/tv có sẵn: matrix boot, screenshot watch/tv PASS; fixture watch tap đổi màn hình; fixture tv select đổi màn hình; pair/unpair watch+phone PASS.
- Khi runtime watch/tv thiếu: unit/contract/CLI/MCP test vẫn xanh; integration test in `BLOCKED` và skip; plan ghi rõ trạng thái này trong báo cáo thực thi, không tự tải runtime.
- `opensim doctor --json` có `platforms` cho iOS, watchOS, tvOS và capability `watch`/`tv` từ Bridge.
- CLI `device pair/unpair --json` trả envelope schema 1; MCP `device_pair` dùng cùng `PairingControlling`, không gọi `simctl` trực tiếp trong MCP.
- App toolbar chỉ hiện button thuộc `PlatformInputMap`; watch/tv không hiện pinch/rotate; không tạo shell UI thứ hai.
- Fixture watch/tv build bằng XcodeGen và `xcodebuild` thành công trên Xcode 27.1; bundle ID đúng.
- Không thay đổi chữ ký protocol của Plan 1/2; chỉ thêm `PlatformAdapter`, `PairingControlling` và type mới.
- Không có tính năng visionOS hoặc thiết bị thật trong plan này.


