# OpenSim Plan 5 — Storage and Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bổ sung quản trị dung lượng (scan, plan, apply) và đo CPU/RAM/process theo device vào daemon, CLI, MCP và hai tab Storage/Performance của app macOS, dùng dữ liệu thật từ simulator và filesystem.

**Architecture:** `OpenSimCore` giữ kiểu dữ liệu, quy tắc an toàn và ngưỡng; `OpenSimDaemon` giữ I/O filesystem, process sampling, plan token và các HTTP/SSE endpoint mới. `OpenSimCLI` và `OpenSimMCP` chỉ gọi operation catalog qua daemon; app dùng lại shell của Plan 4 và thay placeholder bằng view thật. Không có daemon thứ hai, không có UI shell thứ hai, không có mock data trong app.

**Tech Stack:** Swift 6 language mode, SwiftPM, Foundation, CryptoKit, libproc (`proc_listallpids`, `proc_pid_rusage`, `proc_pidinfo`), `sysctl(KERN_PROCARGS2)`, Hummingbird 2.x (daemon từ Plan 3), swift-argument-parser, SwiftUI + AppKit (app từ Plan 4), XCTest và XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-19-open-simulator-design.md`

## Global Constraints

- macOS 27.0+; arm64; Xcode 27.1+ (Xcode 27.0 best-effort nếu fingerprint khớp).
- Swift 6 language mode; SwiftPM cho Core/Bridge/Daemon/CLI/MCP; XcodeGen cho app.
- Dependencies chỉ gồm `swift-argument-parser`, `swift-log`, `Hummingbird` 2.x; không MCP SDK, không database.
- Daemon bind `127.0.0.1`, port động, Bearer token 32 byte trong `~/Library/Application Support/OpenSim/daemon.json` quyền `0600`.
- Mọi thao tác ghi cần lease `control`; đọc không cần lease. Plan 3 xử lý lease và audit ở tầng HTTP.
- Storage clean luôn qua plan/apply; plan token TTL 5 phút, dùng một lần.
- Không auto-delete, không dọn định kỳ, không xoá runtime hệ thống, không xoá `iOS DeviceSupport`, không xoá thư mục Xcode không xác định.
- Xoá Xcode artifact bằng `FileManager.trashItem`; xoá simulator/runtime/app bằng `simctl` với argument array; không dùng shell string.
- Ngưỡng mặc định: CPU > 150% trong 30 giây, RAM > 2 GB, disk free < 10 GB; ngưỡng cấu hình được.
- Metrics sample mỗi 1 giây khi Performance được bật hoặc có subscriber; ring buffer 10 phút; UI chỉ subscribe SSE khi view Performance mở và flag bật.
- `DaemonRunner` phải mount storage/perf routes qua `DaemonRouteProvider`, tạo `StorageService`/`MetricsSampler`, gọi `sampler.start()` khi Performance bật và `stop()` khi shutdown; thiếu route/sampler thì Plan 5 chưa hoàn thành.
- Kết thúc Plan 5: đổi `AppFeature.performance = true` và thay `case .performance: EmptyView()` trong `AppShell` bằng `PerformanceTabView`; cập nhật `ServiceShellUITests` để assert `sidebar-performance` tồn tại.
- Khi dung lượng thu hồi > 20 GB, apply yêu cầu gõ đúng tên nhóm (`ARCHIVES`, `DERIVEDDATA`, `SIMULATORS`, `CACHES`, `LOGS`, `RUNTIMES`, `APPDATA`, `MULTIPLE`).
- Không hiển thị hoặc ghi log nội dung file; chỉ ghi path, size, category và lỗi.
- Không dùng mock data trong app; UI test dùng daemon thật với root fixture trong thư mục tạm.
- Không tạo shell UI mới. Plan 4 giữ Storage shell; Performance ẩn sau `AppFeature.performance=false`. Plan 5 thay Storage shell bằng `StorageTabView` và bật Performance sau khi nối metrics.
- Văn xuôi tiếng Việt; code, type, identifier, command tiếng Anh; không ký tự CJK.
- Mọi task kết thúc bằng commit; người thực thi không chạy commit khi review plan.

## Phụ thuộc và điểm nối

- Plan 1: `docs/superpowers/plans/2026-10-20-opensim-plan-1-core-bridge-cli.md`. Cung cấp `OpenSimCore`, `OpenSimBridge`, `DeviceControlling`, `RuntimeControlling`, `AppControlling`, `OperationCatalog`, envelope CLI và exit code.
- Plan 2: `docs/superpowers/plans/2026-10-20-opensim-plan-2-screen-input-a11y.md`. Cung cấp `ScreenControlling`, `InputControlling`, `AccessibilityReading`, fixture iOS.
- Plan 3: `docs/superpowers/plans/2026-10-20-opensim-plan-3-daemon-session-mcp.md`. Cung cấp `OpenSimProtocol`, HTTP server, SSE hub, lease middleware, `DaemonClient` và MCP tool registry. Plan 5 thêm route module và operation handler; không sửa semantics lease.
- Plan 4: `docs/superpowers/plans/2026-10-20-opensim-plan-4-macos-app.md`. Cung cấp sidebar native, `StorageShellView`, `AppFeature.performance=false` và `DaemonClient` struct. Plan 5 thay Storage shell bằng view thật và bật Performance sau khi nối metrics.
- Contract: `docs/superpowers/plans/2026-10-20-plan-map-and-interfaces.md`. Tên type trong plan này tuân theo mục 4 và 5 của contract. Các type mới được định nghĩa đầy đủ trong task tương ứng.
- Điểm nối thực tế: Plan 3 dùng `EventHub.publish`, `MCPHandler`/`ToolCatalogAdapter`, `DaemonServer` với `DaemonRouteProvider`; Plan 4 dùng `AppTab`, `AppShell`, `DaemonClient` struct. Plan 5 đăng ký route provider/operation catalog, không tạo `SSEHub`/`ToolRegistry` song song. Không còn câu “nếu tên khác thì sửa sau”; mọi signature lấy từ Plan 3/4 hiện có.

## File Structure

| File | Trách nhiệm | Loại |
|---|---|---|
| `Sources/OpenSimCore/Storage/StorageItemID.swift` | ID ổn định theo category và relative path | Tạo |
| `Sources/OpenSimCore/Storage/StorageCategoryMetadata.swift` | Metadata theo category, `StorageItemDetail`, `CleanPlanDetail` | Tạo |
| `Sources/OpenSimCore/Storage/StorageSafety.swift` | Quy tắc safe/unsafe, action, lý do chặn | Tạo |
| `Sources/OpenSimCore/Storage/StorageScanOptions.swift` | Option scan và tổng hợp reclaimable | Tạo |
| `Sources/OpenSimCore/Metrics/MetricsThresholds.swift` | Ngưỡng, warning, snapshot theo device | Tạo |
| `Sources/OpenSimProtocol/StorageEvents.swift` | Payload SSE `storage.scan.progress`/`storage.scan.completed` | Tạo |
| `Sources/OpenSimProtocol/StorageMessages.swift` | Body HTTP scan/plan/apply | Tạo |
| `Sources/OpenSimDaemon/Storage/StorageFileSystem.swift` | Protocol filesystem + implementation `FileManager` | Tạo |
| `Sources/OpenSimDaemon/Storage/AllocatedSizeWalker.swift` | Đo allocated size, symlink, inaccessible, approximate | Tạo |
| `Sources/OpenSimDaemon/Storage/StorageRoots.swift` | Root allowlist, canonical path, test override | Tạo |
| `Sources/OpenSimDaemon/Storage/StorageMetadataReader.swift` | Đọc plist DerivedData/Archive | Tạo |
| `Sources/OpenSimDaemon/Storage/StorageIndexCache.swift` | Cache JSON, invalidate theo mtime | Tạo |
| `Sources/OpenSimDaemon/Storage/StorageCategorySource.swift` | Protocol source + kiểu kết quả | Tạo |
| `Sources/OpenSimDaemon/Storage/SimulatorStorageSource.swift` | Device, cache, log, app container | Tạo |
| `Sources/OpenSimDaemon/Storage/XcodeStorageSource.swift` | DerivedData, Archives | Tạo |
| `Sources/OpenSimDaemon/Storage/RuntimeStorageSource.swift` | Runtime do người dùng cài | Tạo |
| `Sources/OpenSimDaemon/Storage/StorageScanner.swift` | Điều phối scan, progress, cache | Tạo |
| `Sources/OpenSimDaemon/Storage/BridgeStorageMetadata.swift` | Adapter từ Bridge protocols sang metadata | Tạo |
| `Sources/OpenSimDaemon/Storage/CleanPlanStore.swift` | Token, TTL, one-time use, snapshot | Tạo |
| `Sources/OpenSimDaemon/Storage/CleanExecutor.swift` | Trash, simctl delete/uninstall/runtime delete, audit | Tạo |
| `Sources/OpenSimDaemon/Storage/StorageService.swift` | Actor điều phối scan/plan/apply, `StorageManaging` | Tạo |
| `Sources/OpenSimDaemon/Storage/StorageHTTP.swift` | Controller cho endpoint storage | Tạo |
| `Sources/OpenSimDaemon/Storage/StorageHTTPAdapter.swift` | Adapter HTTP của Plan 3 sang controller | Tạo |
| `Sources/OpenSimDaemon/Storage/StorageOperationHandler.swift` | Map operation catalog sang StorageService | Tạo |
| `Sources/OpenSimDaemon/Metrics/ProcessRecord.swift` | Kiểu process và protocol sampler | Tạo |
| `Sources/OpenSimDaemon/Metrics/LibProcProcessSampler.swift` | libproc, rusage, argv/env | Tạo |
| `Sources/OpenSimDaemon/Metrics/ProcessMapper.swift` | Map process theo UDID, process tree, env, unknown | Tạo |
| `Sources/OpenSimDaemon/Metrics/MetricsRingBuffer.swift` | Ring 10 phút | Tạo |
| `Sources/OpenSimDaemon/Metrics/MetricsThresholdEvaluator.swift` | CPU sustained, RAM, disk free | Tạo |
| `Sources/OpenSimDaemon/Metrics/MetricsConfigurationStore.swift` | Đọc `config.json`, reload theo mtime | Tạo |
| `Sources/OpenSimDaemon/Metrics/MetricsSampler.swift` | Tick 1 giây, aggregate, SSE | Tạo |
| `Sources/OpenSimDaemon/Metrics/MetricsHTTP.swift` | Controller/adapter HTTP read-only cho perf | Tạo |
| `Sources/OpenSimDaemon/Metrics/MetricsOperationHandler.swift` | Map perf operation sang MetricsSampler | Tạo |
| `Sources/OpenSimCore/Catalog/StoragePerformanceOperations.swift` | Đăng ký `storage`/`perf` vào catalog | Tạo |
| `Sources/OpenSimCore/Catalog/OpenSimCatalog.swift` | Factory duy nhất `openSim()`; Plan 9/10 mở rộng additive | Tạo |
| `Sources/OpenSimCLI/Commands/StorageCommand.swift` | `opensim storage scan/list/clean/reveal` | Tạo |
| `Sources/OpenSimCLI/Commands/PerformanceCommand.swift` | `opensim perf top/watch/stats` | Tạo |
| `Sources/OpenSimCLI/Output/StorageTable.swift` | Bảng text cho storage | Tạo |
| `Sources/OpenSimCLI/Output/PerformanceTable.swift` | Bảng text cho perf | Tạo |
| `Sources/OpenSimMCP/Tools/ToolCatalogAdapter.swift` | Sinh tool storage/perf từ catalog; không tool layer riêng | Đọc (Plan 3) |
| `Sources/OpenSimDaemon/Runtime/DaemonRunner.swift` | Mount storage/perf route provider, start/stop sampler | Sửa (Plan 3) |
| `App/Sources/OpenSimApp/Storage/StorageTabView.swift` | Tab Storage thật | Tạo |
| `App/Sources/OpenSimApp/Storage/StorageTabModel.swift` | State, scan, plan, apply | Tạo |
| `App/Sources/OpenSimApp/Storage/StorageItemTable.swift` | `Table` item native; thay chart/card | Tạo |
| `App/Sources/OpenSimApp/Storage/StorageCleanSheet.swift` | Preview, cảnh báo, gõ tên nhóm | Tạo |
| `App/Sources/OpenSimApp/Performance/PerformanceTabView.swift` | Tab Performance thật | Tạo |
| `App/Sources/OpenSimApp/Performance/PerformanceTabModel.swift` | Subscribe SSE, snapshot, action | Tạo |
| `App/Sources/OpenSimApp/Performance/PerformanceDeviceTable.swift` | `Table` device native; không card/sparkline | Tạo |
| `App/Sources/OpenSimApp/Performance/PerformanceHistoryView.swift` | `Chart` native cho lịch sử 10 phút | Tạo |
| `App/Sources/OpenSimApp/Performance/ProcessTableView.swift` | Process `Table` + action | Tạo |
| `App/Sources/OpenSimApp/Performance/PerformanceThresholdBanner.swift` | Banner ngưỡng | Tạo |
| `App/Sources/OpenSimApp/App/AppShell.swift` | Thay Storage shell; thêm PerformanceTabView | Sửa (Plan 4) |
| `App/Sources/OpenSimApp/App/AppFeature.swift` | Bật `performance` sau khi nối metrics | Sửa (Plan 4) |
| `App/Sources/OpenSimApp/App/DaemonClient.swift` | Thêm method storage/perf | Sửa (Plan 4) |
| `Sources/OpenSimDaemon/Server/DaemonServer.swift` | Gọi adapter route storage/perf | Sửa (Plan 3) |
| `Sources/OpenSimDaemon/Events/EventHub.swift` | Dùng `publish` sẵn có | Đọc (Plan 3) |
| `Tests/OpenSimCoreTests/StorageItemIDTests.swift` | ID ổn định | Tạo |
| `Tests/OpenSimCoreTests/StorageSafetyTests.swift` | Bảng safe/unsafe | Tạo |
| `Tests/OpenSimCoreTests/MetricsThresholdsTests.swift` | Ngưỡng và warning | Tạo |
| `Tests/OpenSimDaemonTests/AllocatedSizeWalkerTests.swift` | Size, symlink, clone | Tạo |
| `Tests/OpenSimDaemonTests/StorageRootsTests.swift` | Allowlist, symlink escape | Tạo |
| `Tests/OpenSimDaemonTests/StorageMetadataReaderTests.swift` | Plist DerivedData/Archive | Tạo |
| `Tests/OpenSimDaemonTests/StorageIndexCacheTests.swift` | Cache, invalidate, corrupt | Tạo |
| `Tests/OpenSimDaemonTests/StorageScannerTests.swift` | Scan fixture, classification | Tạo |
| `Tests/OpenSimDaemonTests/CleanPlanStoreTests.swift` | TTL, reuse, snapshot | Tạo |
| `Tests/OpenSimDaemonTests/CleanExecutorTests.swift` | Trash, simctl, audit, partial failure | Tạo |
| `Tests/OpenSimDaemonTests/StorageHTTPTests.swift` | Endpoint contract | Tạo |
| `Tests/OpenSimDaemonTests/StorageServiceTests.swift` | In-use blocking sau plan | Tạo |
| `Tests/OpenSimDaemonTests/ProcessMapperTests.swift` | Mapping UDID/tree/env/unknown | Tạo |
| `Tests/OpenSimDaemonTests/MetricsSamplerTests.swift` | Sample, ring, threshold | Tạo |
| `Tests/OpenSimDaemonTests/PerformanceHTTPTests.swift` | Endpoint perf + action | Tạo |
| `Tests/OpenSimCLITests/StorageCommandTests.swift` | JSON golden storage | Tạo |
| `Tests/OpenSimCLITests/PerformanceCommandTests.swift` | JSON golden perf | Tạo |
| `Tests/OpenSimCLITests/Goldens/storage-scan.json` | Golden storage | Tạo |
| `Tests/OpenSimCLITests/Goldens/perf-top.json` | Golden perf | Tạo |
| `Tests/OpenSimCLITests/Support/GoldenDocument.swift` | Scrub dữ liệu động | Tạo |
| `Tests/OpenSimMCPTests/StorageToolsTests.swift` | Tool schema, destructive gate | Tạo |
| `Tests/OpenSimMCPTests/PerformanceToolsTests.swift` | Tool schema, read-only | Tạo |
| `Tests/OpenSimAppUITests/StorageTabUITests.swift` | Tab với scan data thật | Tạo |
| `Tests/OpenSimAppUITests/PerformanceTabUITests.swift` | Tab với metric thật | Tạo |
| `Tests/IntegrationTests/StorageIntegrationTests.swift` | Scan/plan/apply trên fixture | Tạo |
| `Tests/IntegrationTests/MetricsIntegrationTests.swift` | Mapping trên device booted | Tạo |

---

### Task 1: Core storage identity, metadata và safety rules

**Files:**
- Create: `Sources/OpenSimCore/Storage/StorageItemID.swift`
- Create: `Sources/OpenSimCore/Storage/StorageCategoryMetadata.swift`
- Create: `Sources/OpenSimCore/Storage/StorageSafety.swift`
- Create: `Sources/OpenSimCore/Storage/StorageScanOptions.swift`
- Test: `Tests/OpenSimCoreTests/StorageItemIDTests.swift`
- Test: `Tests/OpenSimCoreTests/StorageSafetyTests.swift`

**Interfaces:**
- Consumes: `StorageCategory`, `StorageItem`, `StorageScan`, `CleanPlan`, `CleanResultItem`, `DeviceID`, `Platform`, `ContainerKind` từ contract.
- Produces: `StorageItemID.make(category:relativePath:)`, `StorageItemDetail`, `CleanPlanDetail`, `BlockedStorageItem`, `StorageCategoryMetadata` và các metadata struct, `StorageCleanAction`, `StorageSafetyFacts`, `StorageSafetyVerdict`, `StorageSafety.evaluate(_:)`, `StorageScanOptions`, `StorageScanTotals.reclaimableBytes(in:)`.

- [ ] **Step 1: Viết test thất bại cho ID và safety**

Create `Tests/OpenSimCoreTests/StorageItemIDTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class StorageItemIDTests: XCTestCase {
    func testItemIDIsStableAcrossAbsoluteRoots() {
        let first = StorageItemID.make(category: .derivedData, relativePath: "Build/Products")
        let second = StorageItemID.make(category: .derivedData, relativePath: "/Build/Products/")
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.rawValue.hasPrefix("derivedData-"))
    }

    func testItemIDDiffersByCategory() {
        let data = StorageItemID.make(category: .derivedData, relativePath: "Build")
        let archive = StorageItemID.make(category: .archive, relativePath: "Build")
        XCTAssertNotEqual(data, archive)
    }

    func testItemIDKeepsPathCase() {
        let upper = StorageItemID.make(category: .archive, relativePath: "MyApp.xcarchive")
        let lower = StorageItemID.make(category: .archive, relativePath: "myapp.xcarchive")
        XCTAssertNotEqual(upper, lower)
    }
}
```

Create `Tests/OpenSimCoreTests/StorageSafetyTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class StorageSafetyTests: XCTestCase {
    private func facts(
        category: StorageCategory,
        booted: Bool = false,
        inUse: Bool = false,
        systemOwned: Bool = false,
        anyBooted: Bool = false,
        insideRoot: Bool = true,
        symlink: Bool = false,
        categoryRoot: Bool = false
    ) -> StorageSafetyFacts {
        StorageSafetyFacts(
            category: category,
            insideAllowedRoot: insideRoot,
            isSymbolicLink: symlink,
            isBootedDevice: booted,
            isDeviceInUse: inUse,
            isSystemOwned: systemOwned,
            hasBootedSimulator: anyBooted,
            isCategoryRoot: categoryRoot
        )
    }

    func testBootedDeviceIsBlocked() {
        let verdict = StorageSafety.evaluate(facts(category: .simulatorDevice, booted: true))
        XCTAssertFalse(verdict.safeToDelete)
        XCTAssertEqual(verdict.action, .none)
        XCTAssertEqual(verdict.reason, "Device is booted")
    }

    func testSimulatorCacheBlockedWhenAnyDeviceBooted() {
        let verdict = StorageSafety.evaluate(facts(category: .simulatorCache, anyBooted: true))
        XCTAssertFalse(verdict.safeToDelete)
        XCTAssertEqual(verdict.reason, "A simulator is booted")
    }

    func testSimulatorLogAndDerivedDataAreTrashable() {
        XCTAssertEqual(StorageSafety.evaluate(facts(category: .simulatorLog)).action, .trash)
        XCTAssertEqual(StorageSafety.evaluate(facts(category: .derivedData)).action, .trash)
        XCTAssertEqual(StorageSafety.evaluate(facts(category: .archive)).action, .trash)
    }

    func testSystemRuntimeIsBlocked() {
        let verdict = StorageSafety.evaluate(facts(category: .runtime, systemOwned: true))
        XCTAssertFalse(verdict.safeToDelete)
        XCTAssertEqual(verdict.reason, "System runtime is managed by Xcode")
    }

    func testRuntimeInUseIsBlocked() {
        let verdict = StorageSafety.evaluate(facts(category: .runtime, inUse: true))
        XCTAssertFalse(verdict.safeToDelete)
        XCTAssertEqual(verdict.reason, "Runtime is used by an existing device")
    }

    func testAppDataOnBootedDeviceIsBlocked() {
        let verdict = StorageSafety.evaluate(facts(category: .appData, booted: true))
        XCTAssertFalse(verdict.safeToDelete)
        XCTAssertEqual(verdict.reason, "Device is booted; shut down before removing app data")
    }

    func testCategoryRootIsNeverACleanTarget() {
        XCTAssertFalse(StorageSafety.evaluate(facts(category: .archive, categoryRoot: true)).safeToDelete)
    }

    func testPathOutsideRootAndSymlinkAreBlocked() {
        XCTAssertFalse(StorageSafety.evaluate(facts(category: .archive, insideRoot: false)).safeToDelete)
        XCTAssertFalse(StorageSafety.evaluate(facts(category: .archive, symlink: true)).safeToDelete)
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimCoreTests.StorageItemIDTests
```

Expected: FAIL vì `StorageItemID` chưa tồn tại.

- [ ] **Step 3: Viết kiểu ID và metadata**

Create `Sources/OpenSimCore/Storage/StorageItemID.swift`:

```swift
import CryptoKit
import Foundation

public struct StorageItemID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make(category: StorageCategory, relativePath: String) -> StorageItemID {
        let normalized = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
        let digest = SHA256.hash(data: Data("\(category.rawValue):\(normalized)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return StorageItemID(rawValue: "\(category.rawValue)-\(hex.prefix(24))")
    }
}
```

Create `Sources/OpenSimCore/Storage/StorageCategoryMetadata.swift`:

```swift
import Foundation

public struct AppContainerSummary: Codable, Sendable, Equatable {
    public var bundleID: String
    public var displayName: String?
    public var sizeBytes: Int64

    public init(bundleID: String, displayName: String?, sizeBytes: Int64) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.sizeBytes = sizeBytes
    }
}

public struct SimulatorDeviceMetadata: Codable, Sendable, Equatable {
    public var platform: Platform
    public var runtimeIdentifier: String
    public var runtimeVersion: String
    public var lastBootedAt: Date?
    public var appCount: Int
    public var isBooted: Bool
    public var topApps: [AppContainerSummary]

    public init(
        platform: Platform,
        runtimeIdentifier: String,
        runtimeVersion: String,
        lastBootedAt: Date?,
        appCount: Int,
        isBooted: Bool,
        topApps: [AppContainerSummary]
    ) {
        self.platform = platform
        self.runtimeIdentifier = runtimeIdentifier
        self.runtimeVersion = runtimeVersion
        self.lastBootedAt = lastBootedAt
        self.appCount = appCount
        self.isBooted = isBooted
        self.topApps = topApps
    }
}

public struct RuntimeStorageMetadata: Codable, Sendable, Equatable {
    public var platform: Platform
    public var runtimeIdentifier: String
    public var version: String
    public var build: String
    public var isSystemOwned: Bool
    public var isInUse: Bool
    public var usedByDeviceIDs: [DeviceID]

    public init(
        platform: Platform,
        runtimeIdentifier: String,
        version: String,
        build: String,
        isSystemOwned: Bool,
        isInUse: Bool,
        usedByDeviceIDs: [DeviceID]
    ) {
        self.platform = platform
        self.runtimeIdentifier = runtimeIdentifier
        self.version = version
        self.build = build
        self.isSystemOwned = isSystemOwned
        self.isInUse = isInUse
        self.usedByDeviceIDs = usedByDeviceIDs
    }
}

public struct DerivedDataMetadata: Codable, Sendable, Equatable {
    public var projectName: String?
    public var workspacePath: String?
    public var lastUsedAt: Date?

    public init(projectName: String? = nil, workspacePath: String? = nil, lastUsedAt: Date? = nil) {
        self.projectName = projectName
        self.workspacePath = workspacePath
        self.lastUsedAt = lastUsedAt
    }
}

public struct ArchiveMetadata: Codable, Sendable, Equatable {
    public var appName: String?
    public var bundleID: String?
    public var version: String?
    public var build: String?
    public var createdAt: Date?

    public init(
        appName: String? = nil,
        bundleID: String? = nil,
        version: String? = nil,
        build: String? = nil,
        createdAt: Date? = nil
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.version = version
        self.build = build
        self.createdAt = createdAt
    }
}

public struct AppDataMetadata: Codable, Sendable, Equatable {
    public var bundleID: String
    public var containerKind: ContainerKind

    public init(bundleID: String, containerKind: ContainerKind) {
        self.bundleID = bundleID
        self.containerKind = containerKind
    }
}

public enum StorageCategoryMetadata: Codable, Sendable, Equatable {
    case simulatorDevice(SimulatorDeviceMetadata)
    case runtime(RuntimeStorageMetadata)
    case derivedData(DerivedDataMetadata)
    case archive(ArchiveMetadata)
    case appData(AppDataMetadata)
    case notApplicable
}

public struct StorageItemDetail: Codable, Sendable, Identifiable, Equatable {
    public var item: StorageItem
    public var metadata: StorageCategoryMetadata

    public var id: String { item.id }

    public init(item: StorageItem, metadata: StorageCategoryMetadata) {
        self.item = item
        self.metadata = metadata
    }
}

public struct BlockedStorageItem: Codable, Sendable, Equatable {
    public var item: StorageItem
    public var reason: String

    public init(item: StorageItem, reason: String) {
        self.item = item
        self.reason = reason
    }
}

public struct CleanPlanDetail: Codable, Sendable {
    public var plan: CleanPlan
    public var items: [StorageItemDetail]
    public var blocked: [BlockedStorageItem]
    public var totalBytes: Int64
    public var approximate: Bool
    public var requiresTypedConfirmation: Bool
    public var confirmationPhrase: String?
}
```

- [ ] **Step 4: Viết safety rules và scan options**

Create `Sources/OpenSimCore/Storage/StorageSafety.swift`:

```swift
import Foundation

public enum StorageCleanAction: String, Codable, Sendable, Equatable {
    case trash
    case simulatorDelete
    case runtimeDelete
    case appUninstall
    case none
}

public struct StorageSafetyFacts: Sendable, Equatable {
    public var category: StorageCategory
    public var insideAllowedRoot: Bool
    public var isSymbolicLink: Bool
    public var isBootedDevice: Bool
    public var isDeviceInUse: Bool
    public var isSystemOwned: Bool
    public var hasBootedSimulator: Bool
    public var isCategoryRoot: Bool

    public init(
        category: StorageCategory,
        insideAllowedRoot: Bool = true,
        isSymbolicLink: Bool = false,
        isBootedDevice: Bool = false,
        isDeviceInUse: Bool = false,
        isSystemOwned: Bool = false,
        hasBootedSimulator: Bool = false,
        isCategoryRoot: Bool = false
    ) {
        self.category = category
        self.insideAllowedRoot = insideAllowedRoot
        self.isSymbolicLink = isSymbolicLink
        self.isBootedDevice = isBootedDevice
        self.isDeviceInUse = isDeviceInUse
        self.isSystemOwned = isSystemOwned
        self.hasBootedSimulator = hasBootedSimulator
        self.isCategoryRoot = isCategoryRoot
    }
}

public struct StorageSafetyVerdict: Codable, Sendable, Equatable {
    public var safeToDelete: Bool
    public var reason: String?
    public var action: StorageCleanAction

    public init(safeToDelete: Bool, reason: String?, action: StorageCleanAction) {
        self.safeToDelete = safeToDelete
        self.reason = reason
        self.action = action
    }
}

public enum StorageSafety {
    public static func evaluate(_ facts: StorageSafetyFacts) -> StorageSafetyVerdict {
        if facts.isCategoryRoot {
            return StorageSafetyVerdict(
                safeToDelete: false,
                reason: "Category root is not a clean target",
                action: .none
            )
        }
        if !facts.insideAllowedRoot {
            return StorageSafetyVerdict(
                safeToDelete: false,
                reason: "Outside allowed storage roots",
                action: .none
            )
        }
        if facts.isSymbolicLink {
            return StorageSafetyVerdict(
                safeToDelete: false,
                reason: "Symbolic links are not followed",
                action: .none
            )
        }
        switch facts.category {
        case .simulatorDevice:
            if facts.isBootedDevice {
                return StorageSafetyVerdict(safeToDelete: false, reason: "Device is booted", action: .none)
            }
            if facts.isDeviceInUse {
                return StorageSafetyVerdict(safeToDelete: false, reason: "Device is in use", action: .none)
            }
            return StorageSafetyVerdict(safeToDelete: true, reason: nil, action: .simulatorDelete)
        case .simulatorCache:
            if facts.hasBootedSimulator {
                return StorageSafetyVerdict(safeToDelete: false, reason: "A simulator is booted", action: .none)
            }
            return StorageSafetyVerdict(safeToDelete: true, reason: nil, action: .trash)
        case .simulatorLog:
            return StorageSafetyVerdict(safeToDelete: true, reason: nil, action: .trash)
        case .runtime:
            if facts.isSystemOwned {
                return StorageSafetyVerdict(
                    safeToDelete: false,
                    reason: "System runtime is managed by Xcode",
                    action: .none
                )
            }
            if facts.isDeviceInUse {
                return StorageSafetyVerdict(
                    safeToDelete: false,
                    reason: "Runtime is used by an existing device",
                    action: .none
                )
            }
            return StorageSafetyVerdict(safeToDelete: true, reason: nil, action: .runtimeDelete)
        case .derivedData, .archive:
            return StorageSafetyVerdict(safeToDelete: true, reason: nil, action: .trash)
        case .appData:
            if facts.isBootedDevice {
                return StorageSafetyVerdict(
                    safeToDelete: false,
                    reason: "Device is booted; shut down before removing app data",
                    action: .none
                )
            }
            if facts.isDeviceInUse {
                return StorageSafetyVerdict(safeToDelete: false, reason: "App is running", action: .none)
            }
            return StorageSafetyVerdict(safeToDelete: true, reason: nil, action: .appUninstall)
        }
    }
}
```

Create `Sources/OpenSimCore/Storage/StorageScanOptions.swift`:

```swift
import Foundation

public struct StorageScanOptions: Codable, Sendable, Equatable {
    public var categories: [StorageCategory]?
    public var refresh: Bool
    public var includeAppContainers: Bool

    public init(
        categories: [StorageCategory]? = nil,
        refresh: Bool = false,
        includeAppContainers: Bool = true
    ) {
        self.categories = categories
        self.refresh = refresh
        self.includeAppContainers = includeAppContainers
    }
}

public enum StorageScanTotals {
    public static func reclaimableBytes(in items: [StorageItem]) -> Int64 {
        func visit(_ item: StorageItem, hasSafeAncestor: Bool) -> Int64 {
            if item.safeToDelete {
                return hasSafeAncestor ? 0 : item.sizeBytes + item.children.reduce(0) { partial, child in
                    partial + visit(child, hasSafeAncestor: true)
                }
            }
            return item.children.reduce(0) { partial, child in
                partial + visit(child, hasSafeAncestor: hasSafeAncestor)
            }
        }
        return items.reduce(0) { $0 + visit($1, hasSafeAncestor: false) }
    }
}
```

- [ ] **Step 5: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimCoreTests.StorageItemIDTests
swift test --filter OpenSimCoreTests.StorageSafetyTests
```

Expected: PASS toàn bộ; 11 test trong hai suite.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenSimCore/Storage Tests/OpenSimCoreTests/StorageItemIDTests.swift Tests/OpenSimCoreTests/StorageSafetyTests.swift
git commit -m "feat(storage): add storage identity, metadata and safety rules"
```

---

### Task 2: Filesystem abstraction và allocated size walker

**Files:**
- Create: `Sources/OpenSimDaemon/Storage/StorageFileSystem.swift`
- Create: `Sources/OpenSimDaemon/Storage/AllocatedSizeWalker.swift`
- Test: `Tests/OpenSimDaemonTests/AllocatedSizeWalkerTests.swift`

**Interfaces:**
- Consumes: không có type từ task trước.
- Produces: `StorageEntry`, `StorageFileSystem`, `FileManagerStorage`, `SizeMeasurement`, `DirectorySizeWalker.measure(path:progress:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/AllocatedSizeWalkerTests.swift`:

```swift
import Darwin
import XCTest
@testable import OpenSimDaemon

final class AllocatedSizeWalkerTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        let data = Data(repeating: 0x41, count: byteCount)
        try data.write(to: url)
    }

    func testMeasuresAllocatedBytesOfNestedFiles() throws {
        let root = try makeDirectory()
        let nested = root.appendingPathComponent("Build/Products", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeFile(root.appendingPathComponent("first.bin"), byteCount: 262_144)
        try writeFile(nested.appendingPathComponent("second.bin"), byteCount: 524_288)

        let measurement = DirectorySizeWalker(fileSystem: FileManagerStorage())
            .measure(path: root.path, progress: nil)

        XCTAssertEqual(measurement.fileCount, 2)
        XCTAssertGreaterThanOrEqual(measurement.allocatedBytes, 786_432)
        XCTAssertEqual(measurement.inaccessiblePaths, [])
        XCTAssertTrue(measurement.approximate)
    }

    func testDoesNotFollowSymlinkOutsideRoot() throws {
        let root = try makeDirectory()
        let outside = try makeDirectory()
        try writeFile(outside.appendingPathComponent("secret.bin"), byteCount: 131_072)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        let measurement = DirectorySizeWalker(fileSystem: FileManagerStorage())
            .measure(path: root.path, progress: nil)

        XCTAssertEqual(measurement.fileCount, 0)
        XCTAssertEqual(measurement.skippedSymlinks, 1)
    }

    func testSymlinkRootIsNotMeasured() throws {
        let root = try makeDirectory()
        let link = root.appendingPathComponent("root-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)

        let measurement = DirectorySizeWalker(fileSystem: FileManagerStorage())
            .measure(path: link.path, progress: nil)

        XCTAssertEqual(measurement.allocatedBytes, 0)
        XCTAssertTrue(measurement.approximate)
        XCTAssertEqual(measurement.skippedSymlinks, 1)
    }

    func testAPFSCloneProducesApproximateMeasurement() throws {
        let root = try makeDirectory()
        let source = root.appendingPathComponent("source.bin")
        let clone = root.appendingPathComponent("clone.bin")
        try writeFile(source, byteCount: 1_048_576)
        let result = source.path.withCString { sourcePath in
            clone.path.withCString { clonePath in
                clonefile(sourcePath, clonePath, 0)
            }
        }
        if result != 0 {
            throw XCTSkip("APFS clonefile is not available on this volume")
        }

        let measurement = DirectorySizeWalker(fileSystem: FileManagerStorage())
            .measure(path: root.path, progress: nil)

        XCTAssertEqual(measurement.fileCount, 2)
        XCTAssertTrue(measurement.approximate)
        XCTAssertGreaterThanOrEqual(measurement.allocatedBytes, 2_048_000)
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimDaemonTests.AllocatedSizeWalkerTests
```

Expected: FAIL vì module chưa có `DirectorySizeWalker`.

- [ ] **Step 3: Viết filesystem abstraction**

Create `Sources/OpenSimDaemon/Storage/StorageFileSystem.swift`:

```swift
import Foundation

public struct StorageEntry: Sendable, Equatable {
    public var path: String
    public var isDirectory: Bool
    public var isSymbolicLink: Bool
    public var allocatedBytes: Int64
    public var logicalBytes: Int64
    public var hasAllocatedSize: Bool
    public var modificationDate: Date?

    public init(
        path: String,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        allocatedBytes: Int64,
        logicalBytes: Int64,
        hasAllocatedSize: Bool,
        modificationDate: Date?
    ) {
        self.path = path
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.hasAllocatedSize = hasAllocatedSize
        self.modificationDate = modificationDate
    }
}

public protocol StorageFileSystem: Sendable {
    func entry(atPath path: String) throws -> StorageEntry
    func children(ofDirectory path: String) throws -> [StorageEntry]
    func readData(atPath path: String) throws -> Data
    func modificationDate(atPath path: String) -> Date?
    func fileExists(atPath path: String) -> Bool
}

public struct FileManagerStorage: StorageFileSystem, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func entry(atPath path: String) throws -> StorageEntry {
        let attributes = try fileManager.attributesOfItem(atPath: path)
        let type = attributes[.type] as? FileAttributeType
        let isSymbolicLink = type == .typeSymbolicLink
        let isDirectory = type == .typeDirectory
        var allocated: Int64 = 0
        var logical: Int64 = 0
        var hasAllocatedSize = false
        var modificationDate: Date?
        if let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]) {
            if let total = values.totalFileAllocatedSize {
                allocated = Int64(total)
                hasAllocatedSize = true
            } else if let fileAllocated = values.fileAllocatedSize {
                allocated = Int64(fileAllocated)
                hasAllocatedSize = true
            }
            logical = Int64(values.fileSize ?? 0)
            modificationDate = values.contentModificationDate
        }
        if !hasAllocatedSize, let size = attributes[.size] as? NSNumber, !isDirectory {
            logical = size.int64Value
            allocated = size.int64Value
        }
        return StorageEntry(
            path: path,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            allocatedBytes: allocated,
            logicalBytes: logical,
            hasAllocatedSize: hasAllocatedSize,
            modificationDate: modificationDate
        )
    }

    public func children(ofDirectory path: String) throws -> [StorageEntry] {
        let names = try fileManager.contentsOfDirectory(atPath: path)
        return try names.map { name in
            try entry(atPath: (path as NSString).appendingPathComponent(name))
        }
    }

    public func readData(atPath path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    public func modificationDate(atPath path: String) -> Date? {
        (try? entry(atPath: path))?.modificationDate
    }

    public func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }
}
```

- [ ] **Step 4: Viết walker**

Create `Sources/OpenSimDaemon/Storage/AllocatedSizeWalker.swift`:

```swift
import Foundation

public struct SizeMeasurement: Sendable, Equatable {
    public var allocatedBytes: Int64
    public var fileCount: Int
    public var inaccessiblePaths: [String]
    public var skippedSymlinks: Int
    public var approximate: Bool

    public init(
        allocatedBytes: Int64 = 0,
        fileCount: Int = 0,
        inaccessiblePaths: [String] = [],
        skippedSymlinks: Int = 0,
        approximate: Bool = false
    ) {
        self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount
        self.inaccessiblePaths = inaccessiblePaths
        self.skippedSymlinks = skippedSymlinks
        self.approximate = approximate
    }
}

public struct DirectorySizeWalker: Sendable {
    private let fileSystem: any StorageFileSystem

    public init(fileSystem: any StorageFileSystem) {
        self.fileSystem = fileSystem
    }

    public func measure(path: String, progress: (@Sendable (Int64) -> Void)?) -> SizeMeasurement {
        var measurement = SizeMeasurement()
        guard let rootEntry = try? fileSystem.entry(atPath: path) else {
            measurement.inaccessiblePaths.append(path)
            measurement.approximate = true
            return measurement
        }
        if rootEntry.isSymbolicLink {
            measurement.skippedSymlinks = 1
            measurement.approximate = true
            return measurement
        }
        if !rootEntry.isDirectory {
            measurement.fileCount = 1
            measurement.allocatedBytes = rootEntry.allocatedBytes
            measurement.approximate = !rootEntry.hasAllocatedSize || rootEntry.logicalBytes > rootEntry.allocatedBytes
            return measurement
        }

        var stack: [String] = [path]
        var visitedDirectories = 0
        while let directory = stack.popLast() {
            visitedDirectories += 1
            let children: [StorageEntry]
            do {
                children = try fileSystem.children(ofDirectory: directory)
            } catch {
                measurement.inaccessiblePaths.append(directory)
                measurement.approximate = true
                continue
            }
            for child in children {
                if child.isSymbolicLink {
                    measurement.skippedSymlinks += 1
                    measurement.approximate = true
                    continue
                }
                if child.isDirectory {
                    stack.append(child.path)
                    continue
                }
                measurement.fileCount += 1
                measurement.allocatedBytes += child.allocatedBytes
                if !child.hasAllocatedSize {
                    measurement.approximate = true
                }
                if child.logicalBytes > child.allocatedBytes {
                    measurement.approximate = true
                }
                if visitedDirectories % 8 == 0, let progress {
                    progress(measurement.allocatedBytes)
                }
            }
        }
        measurement.approximate = true
        if let progress {
            progress(measurement.allocatedBytes)
        }
        return measurement
    }
}
```

`approximate = true` ở cuối là quyết định có chủ đích: APFS clone và hardlink làm tổng allocated size lớn hơn dung lượng thực sự giải phóng, và không có API công khai để phát hiện clone. Spec mục 10.2 yêu cầu ghi `approximate: true` trong trường hợp này.

- [ ] **Step 5: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimDaemonTests.AllocatedSizeWalkerTests
```

Expected: PASS 4 test; test clone in `SKIPPED` nếu volume không hỗ trợ `clonefile`.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenSimDaemon/Storage/StorageFileSystem.swift Sources/OpenSimDaemon/Storage/AllocatedSizeWalker.swift Tests/OpenSimDaemonTests/AllocatedSizeWalkerTests.swift
git commit -m "feat(storage): add allocated size walker with APFS awareness"
```

---

### Task 3: Storage roots và path allowlist

**Files:**
- Create: `Sources/OpenSimDaemon/Storage/StorageRoots.swift`
- Test: `Tests/OpenSimDaemonTests/StorageRootsTests.swift`

**Interfaces:**
- Consumes: `StorageCategory`, `StorageScanOptions`.
- Produces: `StorageRoot`, `StorageRootResolver.roots()`, `StorageRootResolver.isAllowed(path:category:)`, `StorageRootResolver.fromEnvironment(_:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/StorageRootsTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon

final class StorageRootsTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-roots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }

    func testDefaultRootsMatchSpecPaths() {
        let resolver = StorageRootResolver(homeDirectory: "/Users/tester")
        let paths = Dictionary(uniqueKeysWithValues: resolver.roots().map { ($0.category, $0.path) })
        XCTAssertEqual(paths[.simulatorDevice], "/Users/tester/Library/Developer/CoreSimulator/Devices")
        XCTAssertEqual(paths[.simulatorCache], "/Users/tester/Library/Developer/CoreSimulator/Caches")
        XCTAssertEqual(paths[.simulatorLog], "/Users/tester/Library/Logs/CoreSimulator")
        XCTAssertEqual(paths[.derivedData], "/Users/tester/Library/Developer/Xcode/DerivedData")
        XCTAssertEqual(paths[.archive], "/Users/tester/Library/Developer/Xcode/Archives")
    }

    func testAllowsPathInsideRootOnly() throws {
        let root = try makeDirectory()
        let child = root.appendingPathComponent("Build/Products", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let resolver = StorageRootResolver(homeDirectory: "/Users/tester", overrides: [.derivedData: root.path])

        XCTAssertTrue(resolver.isAllowed(path: child.path, category: .derivedData))
        XCTAssertFalse(resolver.isAllowed(path: "/Users/tester/Library/Developer/Xcode/Archives/2026", category: .derivedData))
    }

    func testRejectsSymlinkEscape() throws {
        let root = try makeDirectory()
        let outside = try makeDirectory()
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let resolver = StorageRootResolver(homeDirectory: "/Users/tester", overrides: [.derivedData: root.path])

        XCTAssertFalse(resolver.isAllowed(path: link.appendingPathComponent("file.bin").path, category: .derivedData))
    }

    func testAppDataIsAllowedUnderDeviceRoot() throws {
        let devices = try makeDirectory()
        let container = devices.appendingPathComponent("UDID/data/Containers/Data/Application/ABC", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let resolver = StorageRootResolver(homeDirectory: "/Users/tester", overrides: [.simulatorDevice: devices.path])

        XCTAssertTrue(resolver.isAllowed(path: container.path, category: .appData))
    }

    func testRuntimePathsAreIndividualRoots() throws {
        let runtimeA = try makeDirectory()
        let runtimeB = try makeDirectory()
        let resolver = StorageRootResolver(
            homeDirectory: "/Users/tester",
            runtimePaths: [runtimeA.path, runtimeB.path],
            overrides: [:]
        )

        XCTAssertTrue(resolver.isAllowed(path: runtimeA.appendingPathComponent("Contents").path, category: .runtime))
        XCTAssertTrue(resolver.isAllowed(path: runtimeB.appendingPathComponent("Contents").path, category: .runtime))
    }

    func testEnvironmentOverrideRequiresTestingFlagAndTempPath() throws {
        let tempRoot = try makeDirectory()
        let encoded = try JSONSerialization.data(withJSONObject: ["derivedData": tempRoot.path])
        let json = String(decoding: encoded, as: UTF8.self)

        let enabled = StorageRootResolver.fromEnvironment([
            "OPENSIM_TESTING": "1",
            "OPENSIM_STORAGE_ROOTS": json
        ])
        XCTAssertTrue(enabled.isAllowed(path: tempRoot.appendingPathComponent("Build").path, category: .derivedData))

        let disabled = StorageRootResolver.fromEnvironment([
            "OPENSIM_STORAGE_ROOTS": json
        ])
        XCTAssertFalse(disabled.isAllowed(path: tempRoot.appendingPathComponent("Build").path, category: .derivedData))
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimDaemonTests.StorageRootsTests
```

Expected: FAIL vì `StorageRootResolver` chưa tồn tại.

- [ ] **Step 3: Viết root resolver**

Create `Sources/OpenSimDaemon/Storage/StorageRoots.swift`:

```swift
import Foundation

public struct StorageRoot: Sendable, Equatable, Codable {
    public var category: StorageCategory
    public var path: String
    public var displayName: String

    public init(category: StorageCategory, path: String, displayName: String) {
        self.category = category
        self.path = path
        self.displayName = displayName
    }
}

public struct StorageRootResolver: Sendable {
    public var homeDirectory: String
    public var runtimePaths: [String]
    public var overrides: [StorageCategory: String]

    public init(
        homeDirectory: String = NSHomeDirectory(),
        runtimePaths: [String] = [],
        overrides: [StorageCategory: String] = [:]
    ) {
        self.homeDirectory = homeDirectory
        self.runtimePaths = runtimePaths
        self.overrides = overrides
    }

    public func roots() -> [StorageRoot] {
        let library = (homeDirectory as NSString).appendingPathComponent("Library")
        let developer = (library as NSString).appendingPathComponent("Developer")
        let coreSimulator = (developer as NSString).appendingPathComponent("CoreSimulator")
        let xcode = (developer as NSString).appendingPathComponent("Xcode")
        var result: [StorageRoot] = [
            StorageRoot(
                category: .simulatorDevice,
                path: overrides[.simulatorDevice] ?? (coreSimulator as NSString).appendingPathComponent("Devices"),
                displayName: "Simulator devices"
            ),
            StorageRoot(
                category: .simulatorCache,
                path: overrides[.simulatorCache] ?? (coreSimulator as NSString).appendingPathComponent("Caches"),
                displayName: "Simulator caches"
            ),
            StorageRoot(
                category: .simulatorLog,
                path: overrides[.simulatorLog] ?? (library as NSString).appendingPathComponent("Logs/CoreSimulator"),
                displayName: "Simulator logs"
            ),
            StorageRoot(
                category: .derivedData,
                path: overrides[.derivedData] ?? (xcode as NSString).appendingPathComponent("DerivedData"),
                displayName: "DerivedData"
            ),
            StorageRoot(
                category: .archive,
                path: overrides[.archive] ?? (xcode as NSString).appendingPathComponent("Archives"),
                displayName: "Archives"
            )
        ]
        if let override = overrides[.runtime] {
            result.append(StorageRoot(category: .runtime, path: override, displayName: "Runtimes"))
        } else {
            for path in runtimePaths {
                result.append(StorageRoot(category: .runtime, path: path, displayName: "Runtime"))
            }
        }
        return result
    }

    public func isAllowed(path: String, category: StorageCategory) -> Bool {
        let target = Self.canonical(path)
        let candidateRoots: [String]
        if category == .appData {
            candidateRoots = roots().filter { $0.category == .simulatorDevice }.map(\.path)
        } else {
            candidateRoots = roots().filter { $0.category == category }.map(\.path)
        }
        return candidateRoots.contains { root in
            let base = Self.canonical(root)
            return target == base || target.hasPrefix(base + "/")
        }
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> StorageRootResolver {
        guard environment["OPENSIM_TESTING"] == "1",
              let raw = environment["OPENSIM_STORAGE_ROOTS"],
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return StorageRootResolver()
        }
        let temporary = canonical(NSTemporaryDirectory())
        var mapped: [StorageCategory: String] = [:]
        for (key, value) in decoded {
            guard let category = StorageCategory(rawValue: key) else { continue }
            let candidate = canonical(value)
            guard candidate.hasPrefix(temporary) else { continue }
            mapped[category] = candidate
        }
        return StorageRootResolver(overrides: mapped)
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
```

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimDaemonTests.StorageRootsTests
```

Expected: PASS 6 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimDaemon/Storage/StorageRoots.swift Tests/OpenSimDaemonTests/StorageRootsTests.swift
git commit -m "feat(storage): add root allowlist and canonical path validation"
```

### Task 4: Metadata reader và index cache

**Files:**
- Create: `Sources/OpenSimDaemon/Storage/StorageMetadataReader.swift`
- Create: `Sources/OpenSimDaemon/Storage/StorageIndexCache.swift`
- Test: `Tests/OpenSimDaemonTests/StorageMetadataReaderTests.swift`
- Test: `Tests/OpenSimDaemonTests/StorageIndexCacheTests.swift`

**Interfaces:**
- Consumes: `DerivedDataMetadata`, `ArchiveMetadata`, `StorageItemDetail` từ Task 1; `StorageFileSystem` từ Task 2.
- Produces: `StorageMetadataReader.derivedDataMetadata(at:)`, `StorageMetadataReader.archiveMetadata(at:)`, `StorageIndexDocument`, `StorageIndexRoot`, `StorageIndexCache.cachedRoot(category:path:modificationTime:)`, `StorageIndexCache.store(_:)`.

- [ ] **Step 1: Viết test metadata thất bại**

Create `Tests/OpenSimDaemonTests/StorageMetadataReaderTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon

final class StorageMetadataReaderTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }

    func testReadsDerivedDataProjectAndDate() throws {
        let directory = try makeDirectory()
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let plist: [String: Any] = [
            "WorkspacePath": "/Users/tester/Code/MyApp/MyApp.xcworkspace",
            "LastAccessedDate": date
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try data.write(to: directory.appendingPathComponent("info.plist"))

        let metadata = StorageMetadataReader(fileSystem: FileManagerStorage())
            .derivedDataMetadata(at: directory.path)

        XCTAssertEqual(metadata.projectName, "MyApp")
        XCTAssertEqual(metadata.workspacePath, "/Users/tester/Code/MyApp/MyApp.xcworkspace")
        XCTAssertEqual(metadata.lastUsedAt, date)
    }

    func testReadsArchiveApplicationProperties() throws {
        let directory = try makeDirectory()
        let archive = directory.appendingPathComponent("MyApp 2026-10-20.xcarchive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let created = Date(timeIntervalSince1970: 1_781_000_000)
        let plist: [String: Any] = [
            "Name": "MyApp",
            "CreationDate": created,
            "ApplicationProperties": [
                "CFBundleIdentifier": "dev.opensim.fixture",
                "CFBundleShortVersionString": "2.3.0",
                "CFBundleVersion": "231"
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try data.write(to: archive.appendingPathComponent("Info.plist"))

        let metadata = StorageMetadataReader(fileSystem: FileManagerStorage())
            .archiveMetadata(at: archive.path)

        XCTAssertEqual(metadata.appName, "MyApp")
        XCTAssertEqual(metadata.bundleID, "dev.opensim.fixture")
        XCTAssertEqual(metadata.version, "2.3.0")
        XCTAssertEqual(metadata.build, "231")
        XCTAssertEqual(metadata.createdAt, created)
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimDaemonTests.StorageMetadataReaderTests
```

Expected: FAIL vì `StorageMetadataReader` chưa tồn tại.

- [ ] **Step 3: Viết metadata reader**

Create `Sources/OpenSimDaemon/Storage/StorageMetadataReader.swift`:

```swift
import Foundation

public struct StorageMetadataReader: Sendable {
    private let fileSystem: any StorageFileSystem

    public init(fileSystem: any StorageFileSystem) {
        self.fileSystem = fileSystem
    }

    public func derivedDataMetadata(at path: String) -> DerivedDataMetadata {
        guard let plist = readPlist(at: path + "/info.plist") else {
            return DerivedDataMetadata()
        }
        let workspace = plist["WorkspacePath"] as? String
        let lastUsed = plist["LastAccessedDate"] as? Date
        let projectName = workspace.map {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
        }
        return DerivedDataMetadata(projectName: projectName, workspacePath: workspace, lastUsedAt: lastUsed)
    }

    public func archiveMetadata(at path: String) -> ArchiveMetadata {
        guard let plist = readPlist(at: path + "/Info.plist") else {
            return ArchiveMetadata()
        }
        let properties = plist["ApplicationProperties"] as? [String: Any]
        return ArchiveMetadata(
            appName: (plist["Name"] as? String) ?? (properties?["CFBundleDisplayName"] as? String),
            bundleID: properties?["CFBundleIdentifier"] as? String,
            version: properties?["CFBundleShortVersionString"] as? String,
            build: properties?["CFBundleVersion"] as? String,
            createdAt: plist["CreationDate"] as? Date
        )
    }

    private func readPlist(at path: String) -> [String: Any]? {
        guard let data = try? fileSystem.readData(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any]
        else {
            return nil
        }
        return dictionary
    }
}
```

- [ ] **Step 4: Viết test cache thất bại**

Create `Tests/OpenSimDaemonTests/StorageIndexCacheTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon

final class StorageIndexCacheTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }

    private func makeRoot(category: StorageCategory, path: String, date: Date) -> StorageIndexRoot {
        let item = StorageItem(
            id: StorageItemID.make(category: category, relativePath: ".").rawValue,
            category: category,
            path: path,
            sizeBytes: 1_024,
            lastUsedAt: date,
            safeToDelete: false,
            reason: "Category root is not a clean target",
            children: []
        )
        return StorageIndexRoot(
            category: category,
            path: path,
            modificationTime: date,
            measuredAt: date,
            approximate: true,
            rootItem: item,
            details: []
        )
    }

    func testStoresAndReloadsRoot() async throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("storage-index.json")
        let date = Date(timeIntervalSince1970: 1_780_000_500)
        let root = makeRoot(category: .derivedData, path: directory.path, date: date)
        let cache = StorageIndexCache(fileURL: file)

        try await cache.store(root)
        let reloaded = StorageIndexCache(fileURL: file)
        let cached = await reloaded.cachedRoot(
            category: .derivedData,
            path: directory.path,
            modificationTime: date
        )

        XCTAssertEqual(cached?.rootItem.sizeBytes, 1_024)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testInvalidatesWhenModificationTimeChanges() async throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("storage-index.json")
        let oldDate = Date(timeIntervalSince1970: 1_780_000_500)
        let cache = StorageIndexCache(fileURL: file)
        try await cache.store(makeRoot(category: .archive, path: directory.path, date: oldDate))

        let cached = await cache.cachedRoot(
            category: .archive,
            path: directory.path,
            modificationTime: oldDate.addingTimeInterval(10)
        )
        XCTAssertNil(cached)
    }

    func testCorruptDocumentFallsBackToColdStart() async throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("storage-index.json")
        try Data("not-json".utf8).write(to: file)
        let cache = StorageIndexCache(fileURL: file)
        let cached = await cache.cachedRoot(category: .archive, path: directory.path, modificationTime: nil)
        XCTAssertNil(cached)
    }
}
```

- [ ] **Step 5: Viết cache implementation**

Create `Sources/OpenSimDaemon/Storage/StorageIndexCache.swift`:

```swift
import Foundation

public struct StorageIndexDocument: Codable, Sendable {
    public var schemaVersion: Int
    public var roots: [StorageIndexRoot]

    public init(schemaVersion: Int = 1, roots: [StorageIndexRoot] = []) {
        self.schemaVersion = schemaVersion
        self.roots = roots
    }
}

public struct StorageIndexRoot: Codable, Sendable {
    public var category: StorageCategory
    public var path: String
    public var modificationTime: Date?
    public var measuredAt: Date
    public var approximate: Bool
    public var rootItem: StorageItem
    public var details: [StorageItemDetail]

    public init(
        category: StorageCategory,
        path: String,
        modificationTime: Date?,
        measuredAt: Date,
        approximate: Bool,
        rootItem: StorageItem,
        details: [StorageItemDetail]
    ) {
        self.category = category
        self.path = path
        self.modificationTime = modificationTime
        self.measuredAt = measuredAt
        self.approximate = approximate
        self.rootItem = rootItem
        self.details = details
    }
}

public actor StorageIndexCache {
    private let fileURL: URL
    private let fileManager: FileManager
    private var document: StorageIndexDocument?

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func cachedRoot(
        category: StorageCategory,
        path: String,
        modificationTime: Date?
    ) -> StorageIndexRoot? {
        let document = loadIfNeeded()
        return document.roots.first { root in
            root.category == category
                && root.path == path
                && root.modificationTime == modificationTime
        }
    }

    public func store(_ root: StorageIndexRoot) throws {
        var document = loadIfNeeded()
        document.roots.removeAll { $0.category == root.category && $0.path == root.path }
        document.roots.append(root)
        self.document = document
        try persist(document)
    }

    public func removeAll() throws {
        document = StorageIndexDocument()
        try persist(document)
    }

    private func loadIfNeeded() -> StorageIndexDocument {
        if let document {
            return document
        }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.indexDecoder.decode(StorageIndexDocument.self, from: data),
              decoded.schemaVersion == 1
        else {
            let empty = StorageIndexDocument()
            document = empty
            return empty
        }
        document = decoded
        return decoded
    }

    private func persist(_ document: StorageIndexDocument) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder.indexEncoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

extension JSONEncoder {
    static var indexEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var indexDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 6: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimDaemonTests.StorageMetadataReaderTests
swift test --filter OpenSimDaemonTests.StorageIndexCacheTests
```

Expected: PASS 5 test.

- [ ] **Step 7: Commit**

```bash
git add Sources/OpenSimDaemon/Storage/StorageMetadataReader.swift Sources/OpenSimDaemon/Storage/StorageIndexCache.swift Tests/OpenSimDaemonTests/StorageMetadataReaderTests.swift Tests/OpenSimDaemonTests/StorageIndexCacheTests.swift
git commit -m "feat(storage): add metadata readers and root index cache"
```

---

### Task 5: Scanner cho simulator device, cache và log

**Files:**
- Create: `Sources/OpenSimProtocol/StorageEvents.swift`
- Create: `Sources/OpenSimDaemon/Storage/StorageCategorySource.swift`
- Create: `Sources/OpenSimDaemon/Storage/SimulatorStorageSource.swift`
- Create: `Sources/OpenSimDaemon/Storage/StorageScanner.swift`
- Test: `Tests/OpenSimDaemonTests/StorageScannerTests.swift`

**Interfaces:**
- Consumes: `StorageItemID`, `StorageItemDetail`, `StorageSafety`, `StorageScanOptions`, `StorageScanTotals` từ Task 1; `DirectorySizeWalker`, `StorageFileSystem` từ Task 2; `StorageRootResolver` từ Task 3; `StorageIndexCache` từ Task 4; `Device`, `AppInfo`, `Runtime` từ contract.
- Produces: `StorageScanProgress`, `StorageScanSummary`, `StorageScanStatus`; `StorageMetadataProviding`, `SimulatorStorageRecord`, `RuntimeStorageRecord`; `StorageCategorySource`, `StorageScanContext`, `StorageCategoryResult`; `SimulatorDeviceSource`, `SinglePathSource`; `StorageScanner.scan(scanID:options:progress:)`, `StorageScanResult`.

- [ ] **Step 1: Viết test scan fixture thất bại**

Create `Tests/OpenSimDaemonTests/StorageScannerTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol

final class StorageScannerTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-scan-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }

    func testScansDeviceAndClassifierBlocksBootedDevice() async throws {
        let devicesRoot = try makeDirectory("devices")
        let deviceID = DeviceID(rawValue: "11111111-2222-3333-4444-555555555555")
        let deviceDirectory = devicesRoot.appendingPathComponent(deviceID.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: deviceDirectory, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 2_097_152)
            .write(to: deviceDirectory.appendingPathComponent("data.bin"))

        let device = Device(
            id: deviceID,
            name: "iPhone Fixture",
            platform: .iOS,
            deviceType: "iPhone-17",
            runtime: RuntimeID(rawValue: "com.apple.CoreSimulator.SimRuntime.iOS-27-0"),
            state: .booted,
            isAvailable: true,
            dataPath: deviceDirectory.path,
            lastBootedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        let metadata = FakeStorageMetadata(
            records: [
                SimulatorStorageRecord(
                    device: device,
                    runtimeIdentifier: device.runtime.rawValue,
                    runtimeVersion: "27.0",
                    appCount: 0
                )
            ],
            booted: [deviceID]
        )
        let resolver = StorageRootResolver(
            homeDirectory: "/Users/tester",
            overrides: [.simulatorDevice: devicesRoot.path]
        )
        let cache = StorageIndexCache(
            fileURL: devicesRoot.deletingLastPathComponent().appendingPathComponent("index-\(UUID().uuidString).json")
        )
        let scanner = StorageScanner(
            resolver: resolver,
            fileSystem: FileManagerStorage(),
            metadata: metadata,
            cache: cache,
            sources: [
                SimulatorDeviceSource(
                    category: .simulatorDevice,
                    walker: DirectorySizeWalker(fileSystem: FileManagerStorage()),
                    maxTopApps: 3
                ),
                SinglePathSource(
                    category: .simulatorCache,
                    walker: DirectorySizeWalker(fileSystem: FileManagerStorage())
                ),
                SinglePathSource(
                    category: .simulatorLog,
                    walker: DirectorySizeWalker(fileSystem: FileManagerStorage())
                )
            ]
        )

        var events: [StorageScanProgress] = []
        let result = try await scanner.scan(
            scanID: "scan-1",
            options: StorageScanOptions(refresh: true),
            progress: { events.append($0) }
        )

        let deviceRoot = try XCTUnwrap(result.scan.items.first { $0.category == .simulatorDevice })
        let deviceItem = try XCTUnwrap(deviceRoot.children.first)
        XCTAssertEqual(deviceItem.id, StorageItemID.make(category: .simulatorDevice, relativePath: deviceID.rawValue).rawValue)
        XCTAssertGreaterThanOrEqual(deviceItem.sizeBytes, 2_097_152)
        XCTAssertFalse(deviceItem.safeToDelete)
        XCTAssertEqual(deviceItem.reason, "Device is booted")
        XCTAssertEqual(result.scan.reclaimableBytes, 0)
        XCTAssertTrue(result.scan.approximate)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events.last?.phase, .completed)
        let detail = try XCTUnwrap(result.detailsByID[deviceItem.id])
        guard case let .simulatorDevice(metadataValue) = detail.metadata else {
            return XCTFail("Expected simulatorDevice metadata")
        }
        XCTAssertEqual(metadataValue.appCount, 0)
        XCTAssertTrue(metadataValue.isBooted)
    }

    func testSkipsMissingRootWithoutFailingScan() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
        let resolver = StorageRootResolver(
            homeDirectory: "/Users/tester",
            overrides: [
                .derivedData: missing.path,
                .simulatorDevice: missing.path,
                .simulatorCache: missing.path,
                .simulatorLog: missing.path,
                .archive: missing.path
            ]
        )
        let scanner = StorageScanner(
            resolver: resolver,
            fileSystem: FileManagerStorage(),
            metadata: FakeStorageMetadata(records: [], booted: []),
            cache: StorageIndexCache(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("index-\(UUID().uuidString).json")
            ),
            sources: [SinglePathSource(category: .derivedData, walker: DirectorySizeWalker(fileSystem: FileManagerStorage()))]
        )

        let result = try await scanner.scan(scanID: "scan-2", options: StorageScanOptions(refresh: true), progress: { _ in })
        XCTAssertEqual(result.scan.items.count, 1)
        XCTAssertEqual(result.scan.items[0].sizeBytes, 0)
        XCTAssertFalse(result.scan.items[0].safeToDelete)
    }
}

private struct FakeStorageMetadata: StorageMetadataProviding {
    var records: [SimulatorStorageRecord]
    var booted: Set<DeviceID>

    func simulatorDevices() async throws -> [SimulatorStorageRecord] { records }
    func runtimes() async throws -> [RuntimeStorageRecord] { [] }
    func bootedDeviceIDs() async throws -> Set<DeviceID> { booted }
    func apps(on device: DeviceID) async throws -> [AppInfo] { [] }
    func appContainerPath(on device: DeviceID, bundleID: String, kind: ContainerKind) async throws -> String {
        throw OpenSimError(
            code: "device_not_found",
            message: "No app container in fixture",
            details: [:],
            recovery: nil,
            retryable: false
        )
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimDaemonTests.StorageScannerTests
```

Expected: FAIL vì `StorageScanner` và `StorageScanProgress` chưa tồn tại.

- [ ] **Step 3: Viết payload progress**

Create `Sources/OpenSimProtocol/StorageEvents.swift`:

```swift
import Foundation
import OpenSimCore

public struct StorageScanProgress: Codable, Sendable, Equatable {
    public enum Phase: String, Codable, Sendable {
        case preparing
        case scanning
        case finalizing
        case completed
        case failed
    }

    public var scanID: String
    public var phase: Phase
    public var completedRoots: Int
    public var totalRoots: Int
    public var bytesSeen: Int64
    public var currentPath: String?
    public var fraction: Double

    public init(
        scanID: String,
        phase: Phase,
        completedRoots: Int,
        totalRoots: Int,
        bytesSeen: Int64,
        currentPath: String?,
        fraction: Double
    ) {
        self.scanID = scanID
        self.phase = phase
        self.completedRoots = completedRoots
        self.totalRoots = totalRoots
        self.bytesSeen = bytesSeen
        self.currentPath = currentPath
        self.fraction = fraction
    }
}

public struct StorageScanSummary: Codable, Sendable, Equatable {
    public var scanID: String
    public var totalBytes: Int64
    public var reclaimableBytes: Int64
    public var approximate: Bool
    public var itemCount: Int
    public var completedAt: Date

    public init(
        scanID: String,
        totalBytes: Int64,
        reclaimableBytes: Int64,
        approximate: Bool,
        itemCount: Int,
        completedAt: Date
    ) {
        self.scanID = scanID
        self.totalBytes = totalBytes
        self.reclaimableBytes = reclaimableBytes
        self.approximate = approximate
        self.itemCount = itemCount
        self.completedAt = completedAt
    }
}

public enum StorageScanState: String, Codable, Sendable {
    case running
    case completed
    case failed
}

public struct StorageScanStatus: Codable, Sendable {
    public var scanID: String
    public var state: StorageScanState
    public var progress: StorageScanProgress
    public var scan: StorageScan?
    public var summary: StorageScanSummary?
    public var error: OpenSimError?

    public init(
        scanID: String,
        state: StorageScanState,
        progress: StorageScanProgress,
        scan: StorageScan?,
        summary: StorageScanSummary?,
        error: OpenSimError?
    ) {
        self.scanID = scanID
        self.state = state
        self.progress = progress
        self.scan = scan
        self.summary = summary
        self.error = error
    }
}
```

- [ ] **Step 4: Viết metadata protocol và source protocol**

Create `Sources/OpenSimDaemon/Storage/StorageCategorySource.swift`:

```swift
import Foundation
import OpenSimCore

public struct SimulatorStorageRecord: Sendable, Equatable {
    public var device: Device
    public var runtimeIdentifier: String
    public var runtimeVersion: String
    public var appCount: Int

    public init(device: Device, runtimeIdentifier: String, runtimeVersion: String, appCount: Int) {
        self.device = device
        self.runtimeIdentifier = runtimeIdentifier
        self.runtimeVersion = runtimeVersion
        self.appCount = appCount
    }
}

public struct RuntimeStorageRecord: Sendable, Equatable {
    public var runtime: Runtime
    public var path: String
    public var isSystemOwned: Bool
    public var usedByDeviceIDs: [DeviceID]

    public init(runtime: Runtime, path: String, isSystemOwned: Bool, usedByDeviceIDs: [DeviceID]) {
        self.runtime = runtime
        self.path = path
        self.isSystemOwned = isSystemOwned
        self.usedByDeviceIDs = usedByDeviceIDs
    }
}

public protocol StorageMetadataProviding: Sendable {
    func simulatorDevices() async throws -> [SimulatorStorageRecord]
    func runtimes() async throws -> [RuntimeStorageRecord]
    func bootedDeviceIDs() async throws -> Set<DeviceID>
    func apps(on device: DeviceID) async throws -> [AppInfo]
    func appContainerPath(on device: DeviceID, bundleID: String, kind: ContainerKind) async throws -> String
}

public struct StorageScanContext: Sendable {
    public var root: StorageRoot
    public var fileSystem: any StorageFileSystem
    public var metadata: any StorageMetadataProviding
    public var bootedDeviceIDs: Set<DeviceID>
    public var includeAppContainers: Bool

    public init(
        root: StorageRoot,
        fileSystem: any StorageFileSystem,
        metadata: any StorageMetadataProviding,
        bootedDeviceIDs: Set<DeviceID>,
        includeAppContainers: Bool
    ) {
        self.root = root
        self.fileSystem = fileSystem
        self.metadata = metadata
        self.bootedDeviceIDs = bootedDeviceIDs
        self.includeAppContainers = includeAppContainers
    }
}

public struct StorageCategoryResult: Codable, Sendable {
    public var rootItem: StorageItem
    public var details: [StorageItemDetail]
    public var approximate: Bool

    public init(rootItem: StorageItem, details: [StorageItemDetail], approximate: Bool) {
        self.rootItem = rootItem
        self.details = details
        self.approximate = approximate
    }
}

public protocol StorageCategorySource: Sendable {
    var category: StorageCategory { get }
    func scan(
        context: StorageScanContext,
        progress: @Sendable (Int64) -> Void
    ) async -> StorageCategoryResult
}
```

- [ ] **Step 5: Viết simulator sources**

Create `Sources/OpenSimDaemon/Storage/SimulatorStorageSource.swift`:

```swift
import Foundation
import OpenSimCore

public struct SimulatorDeviceSource: StorageCategorySource {
    public let category: StorageCategory = .simulatorDevice
    private let walker: DirectorySizeWalker
    private let maxTopApps: Int

    public init(category: StorageCategory, walker: DirectorySizeWalker, maxTopApps: Int) {
        self.walker = walker
        self.maxTopApps = maxTopApps
    }

    public func scan(
        context: StorageScanContext,
        progress: @Sendable (Int64) -> Void
    ) async -> StorageCategoryResult {
        let root = context.root
        let records = (try? await context.metadata.simulatorDevices()) ?? []
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.device.id.rawValue, $0) })
        let booted = context.bootedDeviceIDs
        let directories = (try? context.fileSystem.children(ofDirectory: root.path)) ?? []
        var total: Int64 = 0
        var approximate = false
        var details: [StorageItemDetail] = []
        var children: [StorageItem] = []

        for directory in directories where directory.isDirectory {
            let relative = URL(fileURLWithPath: directory.path).lastPathComponent
            let record = recordsByID[relative]
            let measurement = await Task.detached(priority: .utility) {
                walker.measure(path: directory.path, progress: progress)
            }.value
            total += measurement.allocatedBytes
            approximate = approximate || measurement.approximate
            let isBooted = record.map { booted.contains($0.device.id) } ?? false
            let safety = StorageSafety.evaluate(
                StorageSafetyFacts(
                    category: .simulatorDevice,
                    insideAllowedRoot: true,
                    isSymbolicLink: directory.isSymbolicLink,
                    isBootedDevice: isBooted
                )
            )
            var appChildren: [StorageItem] = []
            var topApps: [AppContainerSummary] = []
            if context.includeAppContainers, let record, record.appCount > 0, !isBooted {
                let apps = (try? await context.metadata.apps(on: record.device.id)) ?? []
                for app in apps.prefix(maxTopApps) {
                    guard let path = try? await context.metadata.appContainerPath(
                        on: record.device.id,
                        bundleID: app.id,
                        kind: .data
                    ) else { continue }
                    let appMeasurement = await Task.detached(priority: .utility) {
                        walker.measure(path: path, progress: nil)
                    }.value
                    let appItem = StorageItem(
                        id: StorageItemID.make(
                            category: .appData,
                            relativePath: "\(record.device.id.rawValue)/\(app.id)/data"
                        ).rawValue,
                        category: .appData,
                        path: path,
                        sizeBytes: appMeasurement.allocatedBytes,
                        lastUsedAt: record.device.lastBootedAt,
                        safeToDelete: true,
                        reason: nil,
                        children: []
                    )
                    let appSafety = StorageSafety.evaluate(
                        StorageSafetyFacts(category: .appData, isBootedDevice: isBooted)
                    )
                    let finalAppItem = StorageItem(
                        id: appItem.id,
                        category: appItem.category,
                        path: appItem.path,
                        sizeBytes: appItem.sizeBytes,
                        lastUsedAt: appItem.lastUsedAt,
                        safeToDelete: appSafety.safeToDelete,
                        reason: appSafety.reason,
                        children: []
                    )
                    appChildren.append(finalAppItem)
                    topApps.append(
                        AppContainerSummary(
                            bundleID: app.id,
                            displayName: app.displayName,
                            sizeBytes: appMeasurement.allocatedBytes
                        )
                    )
                    details.append(
                        StorageItemDetail(
                            item: finalAppItem,
                            metadata: .appData(AppDataMetadata(bundleID: app.id, containerKind: .data))
                        )
                    )
                }
            }
            let item = StorageItem(
                id: StorageItemID.make(category: .simulatorDevice, relativePath: relative).rawValue,
                category: .simulatorDevice,
                path: directory.path,
                sizeBytes: measurement.allocatedBytes,
                lastUsedAt: record?.device.lastBootedAt ?? directory.modificationDate,
                safeToDelete: safety.safeToDelete,
                reason: safety.reason,
                children: appChildren
            )
            children.append(item)
            if let record {
                details.append(
                    StorageItemDetail(
                        item: item,
                        metadata: .simulatorDevice(
                            SimulatorDeviceMetadata(
                                platform: record.device.platform,
                                runtimeIdentifier: record.runtimeIdentifier,
                                runtimeVersion: record.runtimeVersion,
                                lastBootedAt: record.device.lastBootedAt,
                                appCount: record.appCount,
                                isBooted: isBooted,
                                topApps: topApps
                            )
                        )
                    )
                )
            } else {
                details.append(
                    StorageItemDetail(
                        item: item,
                        metadata: .simulatorDevice(
                            SimulatorDeviceMetadata(
                                platform: .unknown,
                                runtimeIdentifier: "",
                                runtimeVersion: "",
                                lastBootedAt: nil,
                                appCount: 0,
                                isBooted: isBooted,
                                topApps: []
                            )
                        )
                    )
                )
            }
        }

        let rootItem = StorageItem(
            id: StorageItemID.make(category: .simulatorDevice, relativePath: ".").rawValue,
            category: .simulatorDevice,
            path: root.path,
            sizeBytes: total,
            lastUsedAt: nil,
            safeToDelete: false,
            reason: "Category root is not a clean target",
            children: children.sorted { $0.sizeBytes > $1.sizeBytes }
        )
        progress(total)
        return StorageCategoryResult(rootItem: rootItem, details: details, approximate: approximate)
    }
}

public struct SinglePathSource: StorageCategorySource {
    public let category: StorageCategory
    private let walker: DirectorySizeWalker

    public init(category: StorageCategory, walker: DirectorySizeWalker) {
        self.category = category
        self.walker = walker
    }

    public func scan(
        context: StorageScanContext,
        progress: @Sendable (Int64) -> Void
    ) async -> StorageCategoryResult {
        let root = context.root
        let exists = context.fileSystem.fileExists(atPath: root.path)
        let measurement: SizeMeasurement
        if exists {
            measurement = await Task.detached(priority: .utility) {
                walker.measure(path: root.path, progress: progress)
            }.value
        } else {
            measurement = SizeMeasurement()
        }
        let facts = StorageSafetyFacts(
            category: category,
            insideAllowedRoot: true,
            isSymbolicLink: false,
            hasBootedSimulator: !context.bootedDeviceIDs.isEmpty
        )
        let safety = exists
            ? StorageSafety.evaluate(facts)
            : StorageSafetyVerdict(safeToDelete: false, reason: "Path does not exist", action: .none)
        let item = StorageItem(
            id: StorageItemID.make(category: category, relativePath: ".").rawValue,
            category: category,
            path: root.path,
            sizeBytes: measurement.allocatedBytes,
            lastUsedAt: context.fileSystem.modificationDate(atPath: root.path),
            safeToDelete: safety.safeToDelete,
            reason: safety.reason,
            children: []
        )
        let rootItem = StorageItem(
            id: StorageItemID.make(category: category, relativePath: "-root").rawValue,
            category: category,
            path: root.path,
            sizeBytes: measurement.allocatedBytes,
            lastUsedAt: nil,
            safeToDelete: false,
            reason: "Category root is not a clean target",
            children: exists ? [item] : []
        )
        return StorageCategoryResult(
            rootItem: rootItem,
            details: [StorageItemDetail(item: item, metadata: .notApplicable)],
            approximate: measurement.approximate
        )
    }
}
```

- [ ] **Step 6: Viết scanner**

Create `Sources/OpenSimDaemon/Storage/StorageScanner.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

public struct StorageScanResult: Sendable {
    public var scan: StorageScan
    public var detailsByID: [String: StorageItemDetail]

    public init(scan: StorageScan, detailsByID: [String: StorageItemDetail]) {
        self.scan = scan
        self.detailsByID = detailsByID
    }
}

public actor StorageScanner {
    private let resolver: StorageRootResolver
    private let fileSystem: any StorageFileSystem
    private let metadata: any StorageMetadataProviding
    private let cache: StorageIndexCache
    private let sources: [any StorageCategorySource]
    private let now: @Sendable () -> Date

    public init(
        resolver: StorageRootResolver,
        fileSystem: any StorageFileSystem,
        metadata: any StorageMetadataProviding,
        cache: StorageIndexCache,
        sources: [any StorageCategorySource],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.resolver = resolver
        self.fileSystem = fileSystem
        self.metadata = metadata
        self.cache = cache
        self.sources = sources
        self.now = now
    }

    public func scan(
        scanID: String,
        options: StorageScanOptions,
        progress: @Sendable (StorageScanProgress) -> Void
    ) async throws -> StorageScanResult {
        let selected = options.categories.map(Set.init)
        let roots = resolver.roots().filter { root in
            selected?.contains(root.category) ?? true
        }
        let booted: Set<DeviceID>
        do {
            booted = try await metadata.bootedDeviceIDs()
        } catch {
            throw OpenSimError(
                code: "storage_scan_failed",
                message: "Could not verify booted devices; refusing to mark storage as safe",
                details: ["reason": String(describing: error)],
                recovery: "Retry after simulator inventory is available",
                retryable: true
            )
        }
        var progressValue = StorageScanProgress(
            scanID: scanID,
            phase: .preparing,
            completedRoots: 0,
            totalRoots: roots.count,
            bytesSeen: 0,
            currentPath: nil,
            fraction: roots.isEmpty ? 1 : 0
        )
        progress(progressValue)

        var rootItems: [StorageItem] = []
        var detailsByID: [String: StorageItemDetail] = [:]
        var approximate = false

        for (index, root) in roots.enumerated() {
            guard let source = sources.first(where: { $0.category == root.category }) else {
                continue
            }
            progressValue.phase = .scanning
            progressValue.currentPath = root.path
            progress(progressValue)

            let modificationTime = fileSystem.modificationDate(atPath: root.path)
            let cached = options.refresh
                ? nil
                : await cache.cachedRoot(
                    category: root.category,
                    path: root.path,
                    modificationTime: modificationTime
                )
            let result: StorageCategoryResult
            if let cached {
                result = StorageCategoryResult(
                    rootItem: cached.rootItem,
                    details: cached.details,
                    approximate: cached.approximate
                )
            } else {
                let context = StorageScanContext(
                    root: root,
                    fileSystem: fileSystem,
                    metadata: metadata,
                    bootedDeviceIDs: booted,
                    includeAppContainers: options.includeAppContainers
                )
                result = await source.scan(context: context, progress: { _ in })
                try? await cache.store(
                    StorageIndexRoot(
                        category: root.category,
                        path: root.path,
                        modificationTime: modificationTime,
                        measuredAt: now(),
                        approximate: result.approximate,
                        rootItem: result.rootItem,
                        details: result.details
                    )
                )
            }
            rootItems.append(result.rootItem)
            for detail in result.details {
                detailsByID[detail.id] = detail
            }
            approximate = approximate || result.approximate
            progressValue.completedRoots = index + 1
            progressValue.bytesSeen = rootItems.reduce(0) { $0 + $1.sizeBytes }
            progressValue.fraction = roots.isEmpty ? 1 : Double(index + 1) / Double(roots.count)
            progress(progressValue)
        }

        let totalBytes = rootItems.reduce(0) { $0 + $1.sizeBytes }
        let reclaimable = StorageScanTotals.reclaimableBytes(in: rootItems)
        let scan = StorageScan(
            id: scanID,
            createdAt: now(),
            approximate: approximate,
            items: rootItems,
            totalBytes: totalBytes,
            reclaimableBytes: reclaimable
        )
        progressValue.phase = .completed
        progressValue.currentPath = nil
        progressValue.fraction = 1
        progressValue.bytesSeen = totalBytes
        progress(progressValue)
        return StorageScanResult(scan: scan, detailsByID: detailsByID)
    }
}
```

- [ ] **Step 7: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimDaemonTests.StorageScannerTests
```

Expected: PASS 2 test. Nếu `OpenSimProtocol` chưa export `StorageScanProgress` cho test target, thêm `import OpenSimProtocol` ở đầu test như snippet.

- [ ] **Step 8: Commit**

```bash
git add Sources/OpenSimProtocol/StorageEvents.swift Sources/OpenSimDaemon/Storage/StorageCategorySource.swift Sources/OpenSimDaemon/Storage/SimulatorStorageSource.swift Sources/OpenSimDaemon/Storage/StorageScanner.swift Tests/OpenSimDaemonTests/StorageScannerTests.swift
git commit -m "feat(storage): add simulator scanner with progress events"
```

### Task 6: Xcode, runtime và metadata adapter

**Files:**
- Create: `Sources/OpenSimDaemon/Storage/XcodeStorageSource.swift`
- Create: `Sources/OpenSimDaemon/Storage/RuntimeStorageSource.swift`
- Create: `Sources/OpenSimDaemon/Storage/BridgeStorageMetadata.swift`
- Test: `Tests/OpenSimDaemonTests/StorageScannerTests.swift` (thêm test method)

**Interfaces:**
- Consumes: `StorageCategorySource`, `StorageScanContext`, `StorageCategoryResult`, `SimulatorStorageRecord`, `RuntimeStorageRecord`, `StorageMetadataProviding` từ Task 5; `StorageMetadataReader` từ Task 4; `Runtime`, `Device`, `AppInfo` từ contract.
- Produces: `DerivedDataSource`, `ArchiveSource`, `RuntimeStorageSource`, `BridgeStorageMetadata`.

- [ ] **Step 1: Viết test thất bại cho ba source**

Append vào `Tests/OpenSimDaemonTests/StorageScannerTests.swift`:

```swift
    func testDerivedDataSourceReadsProjectAndBuildsTrashableItem() async throws {
        let root = try makeDirectory("derived")
        let project = root.appendingPathComponent("MyApp-abcdef", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 409_600)
            .write(to: project.appendingPathComponent("build.bin"))
        let plist: [String: Any] = [
            "WorkspacePath": "/Users/tester/Code/MyApp/MyApp.xcodeproj",
            "LastAccessedDate": Date(timeIntervalSince1970: 1_780_000_700)
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try plistData.write(to: project.appendingPathComponent("info.plist"))

        let source = DerivedDataSource(walker: DirectorySizeWalker(fileSystem: FileManagerStorage()))
        let context = StorageScanContext(
            root: StorageRoot(category: .derivedData, path: root.path, displayName: "DerivedData"),
            fileSystem: FileManagerStorage(),
            metadata: FakeStorageMetadata(records: [], booted: []),
            bootedDeviceIDs: [],
            includeAppContainers: false
        )
        let result = await source.scan(context: context, progress: { _ in })

        let item = try XCTUnwrap(result.rootItem.children.first)
        XCTAssertEqual(item.category, .derivedData)
        XCTAssertTrue(item.safeToDelete)
        XCTAssertGreaterThanOrEqual(item.sizeBytes, 409_600)
        let detail = try XCTUnwrap(result.details.first)
        guard case let .derivedData(value) = detail.metadata else {
            return XCTFail("Expected derivedData metadata")
        }
        XCTAssertEqual(value.projectName, "MyApp")
        XCTAssertEqual(value.lastUsedAt, Date(timeIntervalSince1970: 1_780_000_700))
    }

    func testArchiveSourceFindsArchiveInsideDateFolder() async throws {
        let root = try makeDirectory("archives")
        let dateFolder = root.appendingPathComponent("2026-10-20", isDirectory: true)
        let archive = dateFolder.appendingPathComponent("MyApp.xcarchive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data(repeating: 0x43, count: 204_800)
            .write(to: archive.appendingPathComponent("payload.bin"))
        let plist: [String: Any] = [
            "Name": "MyApp",
            "CreationDate": Date(timeIntervalSince1970: 1_781_000_000),
            "ApplicationProperties": [
                "CFBundleIdentifier": "dev.opensim.fixture",
                "CFBundleShortVersionString": "2.3.0",
                "CFBundleVersion": "231"
            ]
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try plistData.write(to: archive.appendingPathComponent("Info.plist"))

        let source = ArchiveSource(walker: DirectorySizeWalker(fileSystem: FileManagerStorage()))
        let context = StorageScanContext(
            root: StorageRoot(category: .archive, path: root.path, displayName: "Archives"),
            fileSystem: FileManagerStorage(),
            metadata: FakeStorageMetadata(records: [], booted: []),
            bootedDeviceIDs: [],
            includeAppContainers: false
        )
        let result = await source.scan(context: context, progress: { _ in })

        let item = try XCTUnwrap(result.rootItem.children.first)
        XCTAssertTrue(item.safeToDelete)
        let detail = try XCTUnwrap(result.details.first)
        guard case let .archive(value) = detail.metadata else {
            return XCTFail("Expected archive metadata")
        }
        XCTAssertEqual(value.appName, "MyApp")
        XCTAssertEqual(value.version, "2.3.0")
        XCTAssertEqual(value.build, "231")
    }

    func testRuntimeSourceBlocksSystemAndInUseRuntime() async throws {
        let userRoot = try makeDirectory("runtime-user")
        let systemRoot = try makeDirectory("runtime-system")
        try Data(repeating: 0x44, count: 102_400).write(to: userRoot.appendingPathComponent("payload.bin"))
        try Data(repeating: 0x45, count: 51_200).write(to: systemRoot.appendingPathComponent("payload.bin"))
        let userRuntime = Runtime(
            id: RuntimeID(rawValue: "com.apple.CoreSimulator.SimRuntime.watchOS-27-0"),
            name: "watchOS 27.0",
            platform: .watchOS,
            version: "27.0",
            build: "24R100",
            isAvailable: true,
            path: userRoot.path
        )
        let systemRuntime = Runtime(
            id: RuntimeID(rawValue: "com.apple.CoreSimulator.SimRuntime.tvOS-27-0"),
            name: "tvOS 27.0",
            platform: .tvOS,
            version: "27.0",
            build: "24J100",
            isAvailable: true,
            path: systemRoot.path
        )
        let metadata = FakeStorageMetadata(
            records: [],
            booted: [],
            runtimeRecords: [
                RuntimeStorageRecord(runtime: userRuntime, path: userRoot.path, isSystemOwned: false, usedByDeviceIDs: []),
                RuntimeStorageRecord(runtime: systemRuntime, path: systemRoot.path, isSystemOwned: true, usedByDeviceIDs: [])
            ]
        )
        let source = RuntimeStorageSource(walker: DirectorySizeWalker(fileSystem: FileManagerStorage()))
        let context = StorageScanContext(
            root: StorageRoot(category: .runtime, path: userRoot.path, displayName: "Runtimes"),
            fileSystem: FileManagerStorage(),
            metadata: metadata,
            bootedDeviceIDs: [],
            includeAppContainers: false
        )
        let result = await source.scan(context: context, progress: { _ in })

        XCTAssertEqual(result.rootItem.children.count, 2)
        let userItem = try XCTUnwrap(result.rootItem.children.first { $0.path == userRoot.path })
        let systemItem = try XCTUnwrap(result.rootItem.children.first { $0.path == systemRoot.path })
        XCTAssertTrue(userItem.safeToDelete)
        XCTAssertFalse(systemItem.safeToDelete)
        XCTAssertEqual(systemItem.reason, "System runtime is managed by Xcode")
    }

    func testBridgeMetadataDerivesRuntimeVersionAndUsage() async throws {
        let deviceID = DeviceID(rawValue: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        let runtimeID = RuntimeID(rawValue: "com.apple.CoreSimulator.SimRuntime.watchOS-27-0")
        let device = Device(
            id: deviceID,
            name: "Watch Fixture",
            platform: .watchOS,
            deviceType: "Apple-Watch-Series-12-46mm",
            runtime: runtimeID,
            state: .shutdown,
            isAvailable: true,
            dataPath: nil,
            lastBootedAt: nil
        )
        let runtime = Runtime(
            id: runtimeID,
            name: "watchOS 27.0",
            platform: .watchOS,
            version: "27.0",
            build: "24R100",
            isAvailable: true,
            path: "/tmp/watch-runtime"
        )
        let metadata = BridgeStorageMetadata(
            devices: FakeDeviceControl(devices: [device]),
            runtimes: FakeRuntimeControl(runtimes: [runtime]),
            apps: FakeAppControl(apps: [])
        )
        let records = try await metadata.simulatorDevices()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].runtimeVersion, "27.0")
        XCTAssertEqual(records[0].appCount, 0)
        let runtimeRecords = try await metadata.runtimes()
        XCTAssertEqual(runtimeRecords.count, 1)
        XCTAssertEqual(runtimeRecords[0].usedByDeviceIDs, [deviceID])
    }

    private struct FakeDeviceControl: DeviceControlling {
        var devices: [Device]
        func listDevices() async throws -> [Device] { devices }
        func device(_ id: DeviceID) async throws -> Device { devices[0] }
        func createDevice(name: String, deviceType: String, runtime: RuntimeID?) async throws -> Device { devices[0] }
        func cloneDevice(_ id: DeviceID, name: String) async throws -> Device { devices[0] }
        func boot(_ id: DeviceID, wait: Bool) async throws -> Device { devices[0] }
        func shutdown(_ id: DeviceID, wait: Bool) async throws -> Device { devices[0] }
        func erase(_ id: DeviceID) async throws -> Device { devices[0] }
        func delete(_ id: DeviceID) async throws {}
        func rename(_ id: DeviceID, to name: String) async throws -> Device { devices[0] }
        func pair(watch: DeviceID, phone: DeviceID) async throws {}
    }

    private struct FakeRuntimeControl: RuntimeControlling {
        var runtimes: [Runtime]
        func listRuntimes() async throws -> [Runtime] { runtimes }
        func downloadRuntime(platform: Platform, version: String) async throws -> Runtime {
            runtimes.first { $0.platform == platform && $0.version == version } ?? runtimes[0]
        }
        func installRuntime(at path: String) async throws -> Runtime { runtimes[0] }
        func deleteRuntime(_ id: RuntimeID) async throws {}
        func verifyRuntime(_ id: RuntimeID) async throws {}
    }

    private struct FakeAppControl: AppControlling {
        var apps: [AppInfo]
        func listApps(on device: DeviceID, filter: String?) async throws -> [AppInfo] { apps }
        func installApp(on device: DeviceID, at path: String) async throws -> AppInfo { apps[0] }
        func uninstallApp(on device: DeviceID, bundleID: String) async throws {}
        func launchApp(on device: DeviceID, bundleID: String, args: [String], environment: [String: String]) async throws -> Int32 { 1 }
        func terminateApp(on device: DeviceID, bundleID: String) async throws {}
        func appInfo(on device: DeviceID, bundleID: String) async throws -> AppInfo { apps[0] }
        func containerPath(on device: DeviceID, bundleID: String, kind: ContainerKind) async throws -> String { "/tmp/container" }
    }
```

Sửa `FakeStorageMetadata` ở cuối file để nhận `runtimeRecords`:

```swift
private struct FakeStorageMetadata: StorageMetadataProviding {
    var records: [SimulatorStorageRecord]
    var booted: Set<DeviceID>
    var runtimeRecords: [RuntimeStorageRecord] = []

    func simulatorDevices() async throws -> [SimulatorStorageRecord] { records }
    func runtimes() async throws -> [RuntimeStorageRecord] { runtimeRecords }
    func bootedDeviceIDs() async throws -> Set<DeviceID> { booted }
    func apps(on device: DeviceID) async throws -> [AppInfo] { [] }
    func appContainerPath(on device: DeviceID, bundleID: String, kind: ContainerKind) async throws -> String {
        throw OpenSimError(
            code: "device_not_found",
            message: "No app container in fixture",
            details: [:],
            recovery: nil,
            retryable: false
        )
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimDaemonTests.StorageScannerTests
```

Expected: FAIL vì `DerivedDataSource`, `ArchiveSource`, `RuntimeStorageSource`, `BridgeStorageMetadata` chưa tồn tại.

- [ ] **Step 3: Viết Xcode sources**

Create `Sources/OpenSimDaemon/Storage/XcodeStorageSource.swift`:

```swift
import Foundation
import OpenSimCore

public struct DerivedDataSource: StorageCategorySource {
    public let category: StorageCategory = .derivedData
    private let walker: DirectorySizeWalker

    public init(walker: DirectorySizeWalker) {
        self.walker = walker
    }

    public func scan(
        context: StorageScanContext,
        progress: @Sendable (Int64) -> Void
    ) async -> StorageCategoryResult {
        let root = context.root
        let children = (try? context.fileSystem.children(ofDirectory: root.path)) ?? []
        var details: [StorageItemDetail] = []
        var items: [StorageItem] = []
        var total: Int64 = 0
        var approximate = false
        for child in children where child.isDirectory {
            let measurement = await Task.detached(priority: .utility) {
                walker.measure(path: child.path, progress: progress)
            }.value
            let metadata = StorageMetadataReader(fileSystem: context.fileSystem)
                .derivedDataMetadata(at: child.path)
            let relative = String(child.path.dropFirst(root.path.count + 1))
            let item = StorageItem(
                id: StorageItemID.make(category: .derivedData, relativePath: relative).rawValue,
                category: .derivedData,
                path: child.path,
                sizeBytes: measurement.allocatedBytes,
                lastUsedAt: metadata.lastUsedAt ?? child.modificationDate,
                safeToDelete: true,
                reason: nil,
                children: []
            )
            items.append(item)
            details.append(StorageItemDetail(item: item, metadata: .derivedData(metadata)))
            total += measurement.allocatedBytes
            approximate = approximate || measurement.approximate
        }
        let rootItem = StorageItem(
            id: StorageItemID.make(category: .derivedData, relativePath: ".").rawValue,
            category: .derivedData,
            path: root.path,
            sizeBytes: total,
            lastUsedAt: nil,
            safeToDelete: false,
            reason: "Category root is not a clean target",
            children: items.sorted { $0.sizeBytes > $1.sizeBytes }
        )
        return StorageCategoryResult(rootItem: rootItem, details: details, approximate: approximate)
    }
}

public struct ArchiveSource: StorageCategorySource {
    public let category: StorageCategory = .archive
    private let walker: DirectorySizeWalker

    public init(walker: DirectorySizeWalker) {
        self.walker = walker
    }

    public func scan(
        context: StorageScanContext,
        progress: @Sendable (Int64) -> Void
    ) async -> StorageCategoryResult {
        let root = context.root
        let topLevel = (try? context.fileSystem.children(ofDirectory: root.path)) ?? []
        var archiveDirectories: [StorageEntry] = []
        for entry in topLevel where entry.isDirectory {
            if entry.path.hasSuffix(".xcarchive") {
                archiveDirectories.append(entry)
                continue
            }
            let nested = (try? context.fileSystem.children(ofDirectory: entry.path)) ?? []
            archiveDirectories.append(contentsOf: nested.filter { $0.isDirectory && $0.path.hasSuffix(".xcarchive") })
        }
        var details: [StorageItemDetail] = []
        var items: [StorageItem] = []
        var total: Int64 = 0
        var approximate = false
        for archive in archiveDirectories {
            let measurement = await Task.detached(priority: .utility) {
                walker.measure(path: archive.path, progress: progress)
            }.value
            let metadata = StorageMetadataReader(fileSystem: context.fileSystem)
                .archiveMetadata(at: archive.path)
            let relative = String(archive.path.dropFirst(root.path.count + 1))
            let item = StorageItem(
                id: StorageItemID.make(category: .archive, relativePath: relative).rawValue,
                category: .archive,
                path: archive.path,
                sizeBytes: measurement.allocatedBytes,
                lastUsedAt: metadata.createdAt ?? archive.modificationDate,
                safeToDelete: true,
                reason: nil,
                children: []
            )
            items.append(item)
            details.append(StorageItemDetail(item: item, metadata: .archive(metadata)))
            total += measurement.allocatedBytes
            approximate = approximate || measurement.approximate
        }
        let rootItem = StorageItem(
            id: StorageItemID.make(category: .archive, relativePath: ".").rawValue,
            category: .archive,
            path: root.path,
            sizeBytes: total,
            lastUsedAt: nil,
            safeToDelete: false,
            reason: "Category root is not a clean target",
            children: items.sorted { $0.sizeBytes > $1.sizeBytes }
        )
        return StorageCategoryResult(rootItem: rootItem, details: details, approximate: approximate)
    }
}
```

- [ ] **Step 4: Viết runtime source và bridge metadata**

Create `Sources/OpenSimDaemon/Storage/RuntimeStorageSource.swift`:

```swift
import Foundation
import OpenSimCore

public struct RuntimeStorageSource: StorageCategorySource {
    public let category: StorageCategory = .runtime
    private let walker: DirectorySizeWalker

    public init(walker: DirectorySizeWalker) {
        self.walker = walker
    }

    public func scan(
        context: StorageScanContext,
        progress: @Sendable (Int64) -> Void
    ) async -> StorageCategoryResult {
        let records = (try? await context.metadata.runtimes()) ?? []
        var details: [StorageItemDetail] = []
        var items: [StorageItem] = []
        var total: Int64 = 0
        var approximate = false
        let booted = context.bootedDeviceIDs
        for record in records {
            guard context.fileSystem.fileExists(atPath: record.path) else { continue }
            let measurement = await Task.detached(priority: .utility) {
                walker.measure(path: record.path, progress: progress)
            }.value
            let isUsed = !record.usedByDeviceIDs.isEmpty || booted.contains { record.usedByDeviceIDs.contains($0) }
            let safety = StorageSafety.evaluate(
                StorageSafetyFacts(
                    category: .runtime,
                    isDeviceInUse: isUsed,
                    isSystemOwned: record.isSystemOwned
                )
            )
            let relative = record.runtime.id.rawValue
            let item = StorageItem(
                id: StorageItemID.make(category: .runtime, relativePath: relative).rawValue,
                category: .runtime,
                path: record.path,
                sizeBytes: measurement.allocatedBytes,
                lastUsedAt: nil,
                safeToDelete: safety.safeToDelete,
                reason: safety.reason,
                children: []
            )
            items.append(item)
            details.append(
                StorageItemDetail(
                    item: item,
                    metadata: .runtime(
                        RuntimeStorageMetadata(
                            platform: record.runtime.platform,
                            runtimeIdentifier: record.runtime.id.rawValue,
                            version: record.runtime.version,
                            build: record.runtime.build,
                            isSystemOwned: record.isSystemOwned,
                            isInUse: isUsed,
                            usedByDeviceIDs: record.usedByDeviceIDs
                        )
                    )
                )
            )
            total += measurement.allocatedBytes
            approximate = approximate || measurement.approximate
        }
        let rootItem = StorageItem(
            id: StorageItemID.make(category: .runtime, relativePath: ".").rawValue,
            category: .runtime,
            path: context.root.path,
            sizeBytes: total,
            lastUsedAt: nil,
            safeToDelete: false,
            reason: "Category root is not a clean target",
            children: items.sorted { $0.sizeBytes > $1.sizeBytes }
        )
        return StorageCategoryResult(rootItem: rootItem, details: details, approximate: approximate)
    }
}
```

Create `Sources/OpenSimDaemon/Storage/BridgeStorageMetadata.swift`:

```swift
import Foundation
import OpenSimCore

public struct BridgeStorageMetadata: StorageMetadataProviding {
    private let devices: any DeviceControlling
    private let runtimes: any RuntimeControlling
    private let apps: any AppControlling

    public init(
        devices: any DeviceControlling,
        runtimes: any RuntimeControlling,
        apps: any AppControlling
    ) {
        self.devices = devices
        self.runtimes = runtimes
        self.apps = apps
    }

    public func simulatorDevices() async throws -> [SimulatorStorageRecord] {
        let deviceList = try await devices.listDevices()
        let runtimeList = try await runtimes.listRuntimes()
        let runtimeByID = Dictionary(uniqueKeysWithValues: runtimeList.map { ($0.id.rawValue, $0) })
        var records: [SimulatorStorageRecord] = []
        for device in deviceList {
            let appList = (try? await apps.listApps(on: device.id, filter: nil)) ?? []
            let runtime = runtimeByID[device.runtime.rawValue]
            records.append(
                SimulatorStorageRecord(
                    device: device,
                    runtimeIdentifier: device.runtime.rawValue,
                    runtimeVersion: runtime?.version ?? "",
                    appCount: appList.count
                )
            )
        }
        return records
    }

    public func runtimes() async throws -> [RuntimeStorageRecord] {
        let runtimeList = try await runtimes.listRuntimes()
        let deviceList = try await devices.listDevices()
        let usage = Dictionary(grouping: deviceList, by: { $0.runtime })
        return runtimeList.compactMap { runtime in
            guard let path = runtime.path, !path.isEmpty else { return nil }
            let userOwned = FileManager.default.isWritableFile(atPath: path)
            return RuntimeStorageRecord(
                runtime: runtime,
                path: path,
                isSystemOwned: !userOwned,
                usedByDeviceIDs: usage[runtime.id]?.map(\.id) ?? []
            )
        }
    }

    public func bootedDeviceIDs() async throws -> Set<DeviceID> {
        let deviceList = try await devices.listDevices()
        return Set(deviceList.filter { $0.state == .booted }.map(\.id))
    }

    public func apps(on device: DeviceID) async throws -> [AppInfo] {
        try await apps.listApps(on: device, filter: nil)
    }

    public func appContainerPath(on device: DeviceID, bundleID: String, kind: ContainerKind) async throws -> String {
        try await apps.containerPath(on: device, bundleID: bundleID, kind: kind)
    }
}
```

`DerivedDataSource` khai báo `private let reader` nhưng không dùng; xóa dòng đó để tránh warning. Trong code trên đã có `private let reader = StorageMetadataReader(fileSystem: FileManagerStorage())`; bỏ đi khi implement.

- [ ] **Step 5: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimDaemonTests.StorageScannerTests
```

Expected: PASS 6 test trong suite (2 test cũ và 4 test mới).

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenSimDaemon/Storage/XcodeStorageSource.swift Sources/OpenSimDaemon/Storage/RuntimeStorageSource.swift Sources/OpenSimDaemon/Storage/BridgeStorageMetadata.swift Tests/OpenSimDaemonTests/StorageScannerTests.swift
git commit -m "feat(storage): add Xcode, runtime and bridge metadata sources"
```

---

### Task 7: Clean plan token, TTL và snapshot

**Files:**
- Create: `Sources/OpenSimDaemon/Storage/CleanPlanStore.swift`
- Test: `Tests/OpenSimDaemonTests/CleanPlanStoreTests.swift`

**Interfaces:**
- Consumes: `CleanPlan`, `StorageCleanAction`, `StorageCategory`, `OpenSimError` từ Core; `CleanPlanDetail` từ Task 1.
- Produces: `CleanPlanItemSnapshot`, `StoredCleanPlan`, `CleanPlanStore.create(scanID:items:approximate:)`, `CleanPlanStore.consume(token:itemIDs:)`, `CleanPlanStore.peek(token:)`, `CleanPlanStore.confirmationPhrase(for:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/CleanPlanStoreTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon

final class CleanPlanStoreTests: XCTestCase {
    private final class TestClock: @unchecked Sendable {
        var now: Date = Date(timeIntervalSince1970: 1_782_000_000)
    }

    private func snapshot(
        id: String,
        category: StorageCategory = .archive,
        size: Int64 = 1_024,
        action: StorageCleanAction = .trash
    ) -> CleanPlanItemSnapshot {
        CleanPlanItemSnapshot(
            itemID: id,
            category: category,
            path: "/tmp/\(id)",
            sizeBytes: size,
            modificationTime: Date(timeIntervalSince1970: 1_782_000_000),
            action: action,
            simulatorUDID: nil,
            bundleID: nil,
            runtimeIdentifier: nil
        )
    }

    func testCreatesPlanWithFiveMinuteTTLAndConsumesOnce() async throws {
        let clock = TestClock()
        let store = CleanPlanStore(now: { clock.now })
        let plan = try await store.create(scanID: "scan-1", items: [snapshot(id: "a")], approximate: true)

        XCTAssertEqual(plan.expiresAt, clock.now.addingTimeInterval(300))
        XCTAssertFalse(plan.requiresTypedConfirmation)
        XCTAssertEqual(plan.confirmationPhrase, "ARCHIVES")

        let consumed = try await store.consume(token: plan.token, itemIDs: ["a"])
        XCTAssertEqual(consumed.scanID, "scan-1")
        XCTAssertTrue(consumed.used)

        do {
            _ = try await store.consume(token: plan.token, itemIDs: ["a"])
            XCTFail("Second consume must fail")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "confirmation_required")
            XCTAssertFalse(error.retryable)
        }
    }

    func testExpiredTokenIsRejected() async throws {
        let clock = TestClock()
        let store = CleanPlanStore(now: { clock.now })
        let plan = try await store.create(scanID: "scan-2", items: [snapshot(id: "b")], approximate: false)
        clock.now = clock.now.addingTimeInterval(301)

        do {
            _ = try await store.consume(token: plan.token, itemIDs: ["b"])
            XCTFail("Expired token must fail")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "confirmation_required")
            XCTAssertEqual(error.message, "Clean plan token expired")
        }
    }

    func testItemSetMustMatchExactly() async throws {
        let store = CleanPlanStore()
        let plan = try await store.create(
            scanID: "scan-3",
            items: [snapshot(id: "c"), snapshot(id: "d")],
            approximate: false
        )

        do {
            _ = try await store.consume(token: plan.token, itemIDs: ["c"])
            XCTFail("Subset must fail")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "invalid_argument")
        }
    }

    func testLargePlanRequiresTypedConfirmation() async throws {
        let store = CleanPlanStore()
        let plan = try await store.create(
            scanID: "scan-4",
            items: [snapshot(id: "huge", size: 20_000_000_001)],
            approximate: true
        )
        XCTAssertTrue(plan.requiresTypedConfirmation)
        XCTAssertEqual(plan.confirmationPhrase, "ARCHIVES")
    }

    func testMultipleCategoriesUseMultiplePhrase() async throws {
        let store = CleanPlanStore()
        let plan = try await store.create(
            scanID: "scan-5",
            items: [snapshot(id: "e"), snapshot(id: "f", category: .derivedData)],
            approximate: false
        )
        XCTAssertEqual(plan.confirmationPhrase, "MULTIPLE")
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimDaemonTests.CleanPlanStoreTests
```

Expected: FAIL vì `CleanPlanStore` chưa tồn tại.

- [ ] **Step 3: Viết plan store**

Create `Sources/OpenSimDaemon/Storage/CleanPlanStore.swift`:

```swift
import Foundation
import OpenSimCore

public struct CleanPlanItemSnapshot: Sendable, Equatable {
    public var itemID: String
    public var category: StorageCategory
    public var path: String
    public var sizeBytes: Int64
    public var modificationTime: Date?
    public var action: StorageCleanAction
    public var simulatorUDID: String?
    public var bundleID: String?
    public var runtimeIdentifier: String?

    public init(
        itemID: String,
        category: StorageCategory,
        path: String,
        sizeBytes: Int64,
        modificationTime: Date?,
        action: StorageCleanAction,
        simulatorUDID: String?,
        bundleID: String?,
        runtimeIdentifier: String?
    ) {
        self.itemID = itemID
        self.category = category
        self.path = path
        self.sizeBytes = sizeBytes
        self.modificationTime = modificationTime
        self.action = action
        self.simulatorUDID = simulatorUDID
        self.bundleID = bundleID
        self.runtimeIdentifier = runtimeIdentifier
    }
}

public struct StoredCleanPlan: Sendable, Equatable {
    public var token: String
    public var scanID: String
    public var items: [CleanPlanItemSnapshot]
    public var reclaimableBytes: Int64
    public var approximate: Bool
    public var createdAt: Date
    public var expiresAt: Date
    public var requiresTypedConfirmation: Bool
    public var confirmationPhrase: String?
    public var used: Bool

    public init(
        token: String,
        scanID: String,
        items: [CleanPlanItemSnapshot],
        reclaimableBytes: Int64,
        approximate: Bool,
        createdAt: Date,
        expiresAt: Date,
        requiresTypedConfirmation: Bool,
        confirmationPhrase: String?,
        used: Bool
    ) {
        self.token = token
        self.scanID = scanID
        self.items = items
        self.reclaimableBytes = reclaimableBytes
        self.approximate = approximate
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.requiresTypedConfirmation = requiresTypedConfirmation
        self.confirmationPhrase = confirmationPhrase
        self.used = used
    }
}

public actor CleanPlanStore {
    public static let ttl: TimeInterval = 300
    public static let typedConfirmationThreshold: Int64 = 20_000_000_000

    private var plans: [String: StoredCleanPlan] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func create(
        scanID: String,
        items: [CleanPlanItemSnapshot],
        approximate: Bool
    ) throws -> StoredCleanPlan {
        guard !items.isEmpty else {
            throw OpenSimError(
                code: "invalid_argument",
                message: "Clean plan needs at least one item",
                details: [:],
                recovery: "Select at least one safe item",
                retryable: false
            )
        }
        let createdAt = now()
        let total = items.reduce(0) { $0 + $1.sizeBytes }
        let phrase = Self.confirmationPhrase(for: Set(items.map(\.category)))
        let plan = StoredCleanPlan(
            token: Self.makeToken(),
            scanID: scanID,
            items: items,
            reclaimableBytes: total,
            approximate: approximate,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(Self.ttl),
            requiresTypedConfirmation: total > Self.typedConfirmationThreshold,
            confirmationPhrase: phrase,
            used: false
        )
        plans[plan.token] = plan
        pruneExpired()
        return plan
    }

    public func peek(token: String) -> StoredCleanPlan? {
        plans[token]
    }

    public func consume(token: String, itemIDs: [String]) throws -> StoredCleanPlan {
        guard var plan = plans[token] else {
            throw OpenSimError(
                code: "confirmation_required",
                message: "Clean plan token is unknown",
                details: ["token": token],
                recovery: "Create a new clean plan",
                retryable: false
            )
        }
        if plan.used {
            throw OpenSimError(
                code: "confirmation_required",
                message: "Clean plan token was already used",
                details: ["token": token],
                recovery: "Create a new clean plan",
                retryable: false
            )
        }
        if now() >= plan.expiresAt {
            throw OpenSimError(
                code: "confirmation_required",
                message: "Clean plan token expired",
                details: ["token": token],
                recovery: "Create a new clean plan",
                retryable: false
            )
        }
        let planned = Set(plan.items.map(\.itemID))
        guard planned == Set(itemIDs) else {
            throw OpenSimError(
                code: "invalid_argument",
                message: "itemIDs must match the clean plan exactly",
                details: [
                    "planned": planned.sorted().joined(separator: ","),
                    "requested": itemIDs.sorted().joined(separator: ",")
                ],
                recovery: "Create a new clean plan for the requested items",
                retryable: false
            )
        }
        plan.used = true
        plans[token] = plan
        return plan
    }

    public static func confirmationPhrase(for categories: Set<StorageCategory>) -> String {
        guard categories.count == 1, let category = categories.first else {
            return "MULTIPLE"
        }
        switch category {
        case .simulatorDevice:
            return "SIMULATORS"
        case .simulatorCache:
            return "CACHES"
        case .simulatorLog:
            return "LOGS"
        case .runtime:
            return "RUNTIMES"
        case .derivedData:
            return "DERIVEDDATA"
        case .archive:
            return "ARCHIVES"
        case .appData:
            return "APPDATA"
        }
    }

    private func pruneExpired() {
        let current = now()
        plans = plans.filter { $0.value.expiresAt > current }
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        arc4random_buf(&bytes, bytes.count)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimDaemonTests.CleanPlanStoreTests
```

Expected: PASS 5 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimDaemon/Storage/CleanPlanStore.swift Tests/OpenSimDaemonTests/CleanPlanStoreTests.swift
git commit -m "feat(storage): add one-time clean plan tokens with TTL"
```

---

### Task 8: Clean executor với Trash, simctl và audit

**Files:**
- Create: `Sources/OpenSimDaemon/Storage/CleanExecutor.swift`
- Test: `Tests/OpenSimDaemonTests/CleanExecutorTests.swift`

**Interfaces:**
- Consumes: `CleanPlanItemSnapshot`, `StoredCleanPlan` từ Task 7; `AuditEvent`, `SessionID`, `LeaseID`, `CleanResultItem`, `OpenSimError` từ Core.
- Produces: `TrashExecuting`, `FileManagerTrashExecutor`, `SimctlRunning`, `ProcessSimctlRunner`, `CleanExecutor.apply(plan:actor:sessionID:leaseID:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/CleanExecutorTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon

final class CleanExecutorTests: XCTestCase {
    private actor RecordingTrash: TrashExecuting {
        var paths: [String] = []
        var failingPaths: Set<String> = []

        func setFailing(_ path: String) {
            failingPaths.insert(path)
        }

        func trash(path: String) async throws {
            if failingPaths.contains(path) {
                throw OpenSimError(
                    code: "permission_denied",
                    message: "Fixture denial",
                    details: [:],
                    recovery: nil,
                    retryable: false
                )
            }
            paths.append(path)
        }
    }

    private actor RecordingSimctl: SimctlRunning {
        var calls: [[String]] = []
        var failingCommands: Set<String> = []

        func setFailing(_ command: String) {
            failingCommands.insert(command)
        }

        func run(_ arguments: [String]) async throws {
            if let first = arguments.first, failingCommands.contains(first) {
                throw OpenSimError(
                    code: "simctl_failed",
                    message: "Fixture simctl failure",
                    details: [:],
                    recovery: nil,
                    retryable: false
                )
            }
            calls.append(arguments)
        }
    }

    private func snapshot(
        id: String,
        category: StorageCategory,
        action: StorageCleanAction,
        simulatorUDID: String? = nil,
        bundleID: String? = nil,
        runtimeIdentifier: String? = nil
    ) -> CleanPlanItemSnapshot {
        CleanPlanItemSnapshot(
            itemID: id,
            category: category,
            path: "/tmp/\(id)",
            sizeBytes: 1_024,
            modificationTime: nil,
            action: action,
            simulatorUDID: simulatorUDID,
            bundleID: bundleID,
            runtimeIdentifier: runtimeIdentifier
        )
    }

    private func plan(_ items: [CleanPlanItemSnapshot]) -> StoredCleanPlan {
        StoredCleanPlan(
            token: "token",
            scanID: "scan",
            items: items,
            reclaimableBytes: items.reduce(0) { $0 + $1.sizeBytes },
            approximate: true,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(300),
            requiresTypedConfirmation: false,
            confirmationPhrase: nil,
            used: true
        )
    }

    func testExecutesEachActionWithArgumentArray() async throws {
        let trash = RecordingTrash()
        let simctl = RecordingSimctl()
        var audits: [AuditEvent] = []
        let executor = CleanExecutor(
            trash: trash,
            simctl: simctl,
            audit: { event in audits.append(event) }
        )
        let items = [
            snapshot(id: "archive", category: .archive, action: .trash),
            snapshot(id: "device", category: .simulatorDevice, action: .simulatorDelete, simulatorUDID: "UDID-1"),
            snapshot(id: "runtime", category: .runtime, action: .runtimeDelete, runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.watchOS-27-0"),
            snapshot(id: "app", category: .appData, action: .appUninstall, simulatorUDID: "UDID-1", bundleID: "dev.opensim.fixture")
        ]

        let results = await executor.apply(plan: plan(items), actor: "tester", sessionID: nil, leaseID: nil)

        XCTAssertEqual(results.filter(\.success).count, 4)
        let trashPaths = await trash.paths
        XCTAssertEqual(trashPaths, ["/tmp/archive"])
        let calls = await simctl.calls
        XCTAssertEqual(calls, [
            ["delete", "UDID-1"],
            ["runtime", "delete", "com.apple.CoreSimulator.SimRuntime.watchOS-27-0"],
            ["uninstall", "UDID-1", "dev.opensim.fixture"]
        ])
        XCTAssertEqual(audits.count, 5)
        XCTAssertEqual(audits.last?.action, "storage.clean.completed")
    }

    func testContinuesAfterOneItemFails() async throws {
        let trash = RecordingTrash()
        await trash.setFailing("/tmp/fail")
        let simctl = RecordingSimctl()
        var audits: [AuditEvent] = []
        let executor = CleanExecutor(
            trash: trash,
            simctl: simctl,
            audit: { event in audits.append(event) }
        )
        let items = [
            snapshot(id: "fail", category: .archive, action: .trash),
            snapshot(id: "ok", category: .derivedData, action: .trash)
        ]

        let results = await executor.apply(plan: plan(items), actor: "tester", sessionID: nil, leaseID: nil)

        XCTAssertEqual(results.count, 2)
        XCTAssertFalse(results[0].success)
        XCTAssertEqual(results[0].error?.code, "permission_denied")
        XCTAssertTrue(results[1].success)
        let trashPaths = await trash.paths
        XCTAssertEqual(trashPaths, ["/tmp/ok"])
    }

    func testMissingSimulatorIdentifierFailsItem() async throws {
        let executor = CleanExecutor(trash: RecordingTrash(), simctl: RecordingSimctl(), audit: { _ in })
        let item = snapshot(id: "device", category: .simulatorDevice, action: .simulatorDelete)
        let results = await executor.apply(plan: plan([item]), actor: "tester", sessionID: nil, leaseID: nil)
        XCTAssertFalse(results[0].success)
        XCTAssertEqual(results[0].error?.code, "invalid_argument")
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimDaemonTests.CleanExecutorTests
```

Expected: FAIL vì `CleanExecutor` chưa tồn tại.

- [ ] **Step 3: Viết executor**

Create `Sources/OpenSimDaemon/Storage/CleanExecutor.swift`:

```swift
import Foundation
import OpenSimCore

public protocol TrashExecuting: Sendable {
    func trash(path: String) async throws
}

public struct FileManagerTrashExecutor: TrashExecuting {
    public init() {}

    public func trash(path: String) async throws {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(
            at: URL(fileURLWithPath: path),
            resultingItemURL: &resultingURL
        )
    }
}

public protocol SimctlRunning: Sendable {
    func run(_ arguments: [String]) async throws
}

public struct ProcessSimctlRunner: SimctlRunning {
    public init() {}

    public func run(_ arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl"] + arguments
            let errorPipe = Pipe()
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw OpenSimError(
                    code: "simctl_failed",
                    message: message.isEmpty ? "simctl exited with \(process.terminationStatus)" : message,
                    details: ["arguments": arguments.joined(separator: " ")],
                    recovery: "Run `xcrun simctl \(arguments.joined(separator: " "))` manually and inspect the error",
                    retryable: false
                )
            }
        }.value
    }
}

public struct CleanExecutor: Sendable {
    public typealias AuditHandler = @Sendable (AuditEvent) async -> Void

    private let trash: any TrashExecuting
    private let simctl: any SimctlRunning
    private let audit: AuditHandler

    public init(
        trash: any TrashExecuting,
        simctl: any SimctlRunning,
        audit: @escaping AuditHandler
    ) {
        self.trash = trash
        self.simctl = simctl
        self.audit = audit
    }

    public func apply(
        plan: StoredCleanPlan,
        actor: String,
        sessionID: SessionID?,
        leaseID: LeaseID?
    ) async -> [CleanResultItem] {
        var results: [CleanResultItem] = []
        for snapshot in plan.items {
            let started = DispatchTime.now().uptimeNanoseconds
            do {
                try await execute(snapshot)
                results.append(CleanResultItem(itemID: snapshot.itemID, success: true, error: nil))
                await record(
                    action: "storage.clean.item",
                    target: snapshot.path,
                    result: "success",
                    actor: actor,
                    sessionID: sessionID,
                    leaseID: leaseID,
                    started: started
                )
            } catch {
                let mapped = Self.map(error)
                results.append(CleanResultItem(itemID: snapshot.itemID, success: false, error: mapped))
                await record(
                    action: "storage.clean.item",
                    target: snapshot.path,
                    result: "failure:\(mapped.code)",
                    actor: actor,
                    sessionID: sessionID,
                    leaseID: leaseID,
                    started: started
                )
            }
        }
        await audit(
            AuditEvent(
                id: UUID().uuidString,
                timestamp: Date(),
                actor: actor,
                sessionID: sessionID,
                leaseID: leaseID,
                action: "storage.clean.completed",
                target: plan.token,
                result: results.allSatisfy(\.success) ? "success" : "partial",
                durationMs: 0
            )
        )
        return results
    }

    private func execute(_ snapshot: CleanPlanItemSnapshot) async throws {
        switch snapshot.action {
        case .trash:
            try await trash.trash(path: snapshot.path)
        case .simulatorDelete:
            guard let udid = snapshot.simulatorUDID, !udid.isEmpty else {
                throw OpenSimError(
                    code: "invalid_argument",
                    message: "Simulator item has no UDID",
                    details: ["item": snapshot.itemID],
                    recovery: "Rescan storage and create a new plan",
                    retryable: false
                )
            }
            try await simctl.run(["delete", udid])
        case .runtimeDelete:
            guard let identifier = snapshot.runtimeIdentifier, !identifier.isEmpty else {
                throw OpenSimError(
                    code: "invalid_argument",
                    message: "Runtime item has no identifier",
                    details: ["item": snapshot.itemID],
                    recovery: "Rescan storage and create a new plan",
                    retryable: false
                )
            }
            try await simctl.run(["runtime", "delete", identifier])
        case .appUninstall:
            guard let udid = snapshot.simulatorUDID, let bundleID = snapshot.bundleID else {
                throw OpenSimError(
                    code: "invalid_argument",
                    message: "App item has no device or bundle identifier",
                    details: ["item": snapshot.itemID],
                    recovery: "Rescan storage and create a new plan",
                    retryable: false
                )
            }
            try await simctl.run(["uninstall", udid, bundleID])
        case .none:
            throw OpenSimError(
                code: "storage_in_use",
                message: "Item is not cleanable",
                details: ["item": snapshot.itemID],
                recovery: "Rescan storage and choose a different item",
                retryable: false
            )
        }
    }

    private func record(
        action: String,
        target: String,
        result: String,
        actor: String,
        sessionID: SessionID?,
        leaseID: LeaseID?,
        started: UInt64
    ) async {
        let durationMs = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        await audit(
            AuditEvent(
                id: UUID().uuidString,
                timestamp: Date(),
                actor: actor,
                sessionID: sessionID,
                leaseID: leaseID,
                action: action,
                target: target,
                result: result,
                durationMs: durationMs
            )
        )
    }

    private static func map(_ error: Error) -> OpenSimError {
        if let openSimError = error as? OpenSimError {
            return openSimError
        }
        return OpenSimError(
            code: "internal",
            message: error.localizedDescription,
            details: [:],
            recovery: nil,
            retryable: false
        )
    }
}
```

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimDaemonTests.CleanExecutorTests
```

Expected: PASS 3 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimDaemon/Storage/CleanExecutor.swift Tests/OpenSimDaemonTests/CleanExecutorTests.swift
git commit -m "feat(storage): add trash and simctl clean executor with audit"
```

### Task 9: Storage service, HTTP controller và SSE

**Files:**
- Create: `Sources/OpenSimProtocol/StorageMessages.swift`
- Create: `Sources/OpenSimDaemon/Storage/StorageService.swift`
- Create: `Sources/OpenSimDaemon/Storage/StorageHTTP.swift`
- Create: `Sources/OpenSimDaemon/Storage/StorageHTTPAdapter.swift`
- Create: `Sources/OpenSimDaemon/Storage/StorageOperationHandler.swift`
- Test: `Tests/OpenSimDaemonTests/StorageHTTPTests.swift`

**Interfaces:**
- Consumes: `StorageScanner` từ Task 5, `CleanPlanStore` từ Task 7, `CleanExecutor` từ Task 8, `StorageSafety`, `StorageScanStatus`, `StorageScanSummary`.
- Produces: `StorageScanRequest`, `CleanPlanRequest`, `CleanApplyRequest`, `CleanApplyResult`, `EmptyPayload`; `StorageServing`, `StorageEventEmitter`; `StorageService.beginScan(options:)`, `waitForScan(id:)`, `scanStatus(id:)`, `planDetail(scanID:itemIDs:)`, `applyClean(planToken:itemIDs:confirmationPhrase:actor:sessionID:leaseID:)`; `StorageHTTPRequest`, `StorageHTTPResponse`, `StorageHTTPController.handle(_:)`, `StorageHTTPAdapter.handle(method:path:query:body:)`.

- [ ] **Step 1: Viết test HTTP thất bại**

Create `Tests/OpenSimDaemonTests/StorageHTTPTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol

final class StorageHTTPTests: XCTestCase {
    private actor FakeStorageService: StorageServing {
        var lastConfirmationPhrase: String?
        var lastApplyToken: String?
        var status = StorageScanStatus(
            scanID: "scan-1",
            state: .running,
            progress: StorageScanProgress(
                scanID: "scan-1",
                phase: .scanning,
                completedRoots: 0,
                totalRoots: 5,
                bytesSeen: 0,
                currentPath: nil,
                fraction: 0
            ),
            scan: nil,
            summary: nil,
            error: nil
        )

        func beginScan(options: StorageScanOptions) async throws -> StorageScanStatus {
            status
        }

        func scanStatus(id: String) async throws -> StorageScanStatus {
            if id == "missing" {
                throw OpenSimError(
                    code: "invalid_argument",
                    message: "Unknown scan",
                    details: ["scanId": id],
                    recovery: nil,
                    retryable: false
                )
            }
            return status
        }

        func storageItems(scanID: String, parentID: String?) async throws -> [StorageItem] {
            []
        }

        func planDetail(scanID: String, itemIDs: [String]) async throws -> CleanPlanDetail {
            let item = StorageItem(
                id: "archive-1",
                category: .archive,
                path: "/tmp/archive",
                sizeBytes: 1_024,
                lastUsedAt: nil,
                safeToDelete: true,
                reason: nil,
                children: []
            )
            let plan = CleanPlan(
                token: "token-1",
                expiresAt: Date(timeIntervalSince1970: 1_790_000_000),
                itemIDs: ["archive-1"],
                reclaimableBytes: 1_024
            )
            return CleanPlanDetail(
                plan: plan,
                items: [StorageItemDetail(item: item, metadata: .notApplicable)],
                blocked: [],
                totalBytes: 1_024,
                approximate: true,
                requiresTypedConfirmation: false,
                confirmationPhrase: "ARCHIVES"
            )
        }

        func applyClean(
            planToken: String,
            itemIDs: [String],
            confirmationPhrase: String?,
            actor: String,
            sessionID: SessionID?,
            leaseID: LeaseID?
        ) async throws -> CleanApplyResult {
            lastConfirmationPhrase = confirmationPhrase
            lastApplyToken = planToken
            return CleanApplyResult(
                token: planToken,
                results: [CleanResultItem(itemID: itemIDs[0], success: true, error: nil)],
                reclaimedBytes: 1_024,
                auditID: "audit-1"
            )
        }
    }

    private func body<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    func testStartsScanAndReturns202() async throws {
        let service = FakeStorageService()
        let controller = StorageHTTPController(service: service)
        let request = StorageHTTPRequest(
            method: "POST",
            path: "/v1/storage/scans",
            query: [:],
            body: try body(StorageScanRequest(categories: nil, refresh: true, includeAppContainers: false))
        )
        let response = try XCTUnwrap(await controller.handle(request))
        XCTAssertEqual(response.status, 202)
        let envelope = try JSONDecoder().decode(Envelope<StorageScanStatus>.self, from: response.body)
        XCTAssertEqual(envelope.data?.scanID, "scan-1")
        XCTAssertEqual(envelope.data?.state, .running)
    }

    func testUnknownScanReturnsStructuredError() async throws {
        let controller = StorageHTTPController(service: FakeStorageService())
        let response = try XCTUnwrap(
            await controller.handle(
                StorageHTTPRequest(method: "GET", path: "/v1/storage/scans/missing", query: [:], body: Data())
            )
        )
        XCTAssertEqual(response.status, 400)
        let envelope = try JSONDecoder().decode(Envelope<EmptyPayload>.self, from: response.body)
        XCTAssertEqual(envelope.error?.code, "invalid_argument")
        XCTAssertTrue(envelope.error?.details["scanId"] == "missing")
    }

    func testCreatesPlanAndForwardsConfirmationPhrase() async throws {
        let service = FakeStorageService()
        let controller = StorageHTTPController(service: service)
        let planResponse = try XCTUnwrap(
            await controller.handle(
                StorageHTTPRequest(
                    method: "POST",
                    path: "/v1/storage/clean-plans",
                    query: [:],
                    body: try body(CleanPlanRequest(scanID: "scan-1", itemIDs: ["archive-1"]))
                )
            )
        )
        XCTAssertEqual(planResponse.status, 201)
        let planEnvelope = try JSONDecoder().decode(Envelope<CleanPlanDetail>.self, from: planResponse.body)
        XCTAssertEqual(planEnvelope.data?.plan.token, "token-1")
        XCTAssertEqual(planEnvelope.data?.confirmationPhrase, "ARCHIVES")

        let applyResponse = try XCTUnwrap(
            await controller.handle(
                StorageHTTPRequest(
                    method: "POST",
                    path: "/v1/storage/clean-plans/token-1/apply",
                    query: [:],
                    body: try body(CleanApplyRequest(itemIDs: ["archive-1"], confirmationPhrase: "ARCHIVES"))
                )
            )
        )
        XCTAssertEqual(applyResponse.status, 200)
        let phrase = await service.lastConfirmationPhrase
        XCTAssertEqual(phrase, "ARCHIVES")
    }

    func testUnknownRouteReturnsNil() async {
        let controller = StorageHTTPController(service: FakeStorageService())
        let response = await controller.handle(
            StorageHTTPRequest(method: "GET", path: "/v1/devices", query: [:], body: Data())
        )
        XCTAssertNil(response)
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimDaemonTests.StorageHTTPTests
```

Expected: FAIL vì `StorageHTTPController` và `StorageServing` chưa tồn tại.

- [ ] **Step 3: Viết message types**

Create `Sources/OpenSimProtocol/StorageMessages.swift`:

```swift
import Foundation
import OpenSimCore

public struct StorageScanRequest: Codable, Sendable {
    public var categories: [StorageCategory]?
    public var refresh: Bool
    public var includeAppContainers: Bool

    public init(categories: [StorageCategory]?, refresh: Bool, includeAppContainers: Bool) {
        self.categories = categories
        self.refresh = refresh
        self.includeAppContainers = includeAppContainers
    }
}

public struct CleanPlanRequest: Codable, Sendable {
    public var scanID: String
    public var itemIDs: [String]

    public init(scanID: String, itemIDs: [String]) {
        self.scanID = scanID
        self.itemIDs = itemIDs
    }
}

public struct CleanApplyRequest: Codable, Sendable {
    public var itemIDs: [String]
    public var confirmationPhrase: String?

    public init(itemIDs: [String], confirmationPhrase: String?) {
        self.itemIDs = itemIDs
        self.confirmationPhrase = confirmationPhrase
    }
}

public struct CleanApplyResult: Codable, Sendable {
    public var token: String
    public var results: [CleanResultItem]
    public var reclaimedBytes: Int64
    public var auditID: String?

    public init(token: String, results: [CleanResultItem], reclaimedBytes: Int64, auditID: String?) {
        self.token = token
        self.results = results
        self.reclaimedBytes = reclaimedBytes
        self.auditID = auditID
    }
}

public struct EmptyPayload: Codable, Sendable {
    public init() {}
}
```

- [ ] **Step 4: Viết service**

Create `Sources/OpenSimDaemon/Storage/StorageService.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

public typealias StorageEventEmitter = @Sendable (String, Data) async -> Void

public protocol StorageScanning: Sendable {
    func scan(
        scanID: String,
        options: StorageScanOptions,
        progress: @Sendable (StorageScanProgress) -> Void
    ) async throws -> StorageScanResult
}

extension StorageScanner: StorageScanning {}

public protocol StorageServing: Sendable {
    func beginScan(options: StorageScanOptions) async throws -> StorageScanStatus
    func scanStatus(id: String) async throws -> StorageScanStatus
    func storageItems(scanID: String, parentID: String?) async throws -> [StorageItem]
    func planDetail(scanID: String, itemIDs: [String]) async throws -> CleanPlanDetail
    func applyClean(
        planToken: String,
        itemIDs: [String],
        confirmationPhrase: String?,
        actor: String,
        sessionID: SessionID?,
        leaseID: LeaseID?
    ) async throws -> CleanApplyResult
}

public actor StorageService: StorageServing, StorageManaging {
    private let scanner: any StorageScanning
    private let plans: CleanPlanStore
    private let executor: CleanExecutor
    private let metadata: any StorageMetadataProviding
    private let fileSystem: any StorageFileSystem
    private let emit: StorageEventEmitter
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String
    private var scans: [String: StorageScanResult] = [:]
    private var statuses: [String: StorageScanStatus] = [:]
    private var activeScanID: String?
    private var scanTask: Task<Void, Never>?

    public init(
        scanner: any StorageScanning,
        plans: CleanPlanStore,
        executor: CleanExecutor,
        metadata: any StorageMetadataProviding,
        fileSystem: any StorageFileSystem,
        emit: @escaping StorageEventEmitter,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.scanner = scanner
        self.plans = plans
        self.executor = executor
        self.metadata = metadata
        self.fileSystem = fileSystem
        self.emit = emit
        self.now = now
        self.makeID = makeID
    }

    public func beginScan(options: StorageScanOptions) async throws -> StorageScanStatus {
        if let activeScanID,
           let active = statuses[activeScanID],
           active.state == .running {
            throw OpenSimError(
                code: "storage_scan_failed",
                message: "A storage scan is already running",
                details: ["scanId": activeScanID],
                recovery: "Wait for the running scan to complete",
                retryable: true
            )
        }
        let scanID = makeID()
        let progress = StorageScanProgress(
            scanID: scanID,
            phase: .preparing,
            completedRoots: 0,
            totalRoots: 0,
            bytesSeen: 0,
            currentPath: nil,
            fraction: 0
        )
        let status = StorageScanStatus(
            scanID: scanID,
            state: .running,
            progress: progress,
            scan: nil,
            summary: nil,
            error: nil
        )
        statuses[scanID] = status
        activeScanID = scanID
        scanTask = Task { await self.performScan(scanID: scanID, options: options) }
        return status
    }

    public func scanStatus(id: String) async throws -> StorageScanStatus {
        guard let status = statuses[id] else {
            throw OpenSimError(
                code: "invalid_argument",
                message: "Unknown scan identifier",
                details: ["scanId": id],
                recovery: "Start a new scan with storage_scan",
                retryable: false
            )
        }
        return status
    }

    public func waitForScan(id: String, timeout: TimeInterval = 120) async throws -> StorageScan {
        let deadline = now().addingTimeInterval(timeout)
        while now() < deadline {
            let status = try await scanStatus(id: id)
            if status.state == .completed, let scan = status.scan {
                return scan
            }
            if status.state == .failed, let error = status.error {
                throw error
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        throw OpenSimError(
            code: "storage_scan_failed",
            message: "Storage scan timed out",
            details: ["scanId": id],
            recovery: "Retry the scan with refresh=true",
            retryable: true
        )
    }

    public func scanStorage(refresh: Bool) async throws -> StorageScan {
        let status = try await beginScan(options: StorageScanOptions(refresh: refresh))
        return try await waitForScan(id: status.scanID)
    }

    public func storageItems(scanID: String, parentID: String?) async throws -> [StorageItem] {
        guard let result = scans[scanID] else {
            throw OpenSimError(
                code: "invalid_argument",
                message: "Unknown scan identifier",
                details: ["scanId": scanID],
                recovery: "Start a new scan with storage_scan",
                retryable: false
            )
        }
        guard let parentID else {
            return result.scan.items
        }
        guard let parent = Self.findItem(id: parentID, in: result.scan.items) else {
            throw OpenSimError(
                code: "invalid_argument",
                message: "Unknown storage item",
                details: ["itemId": parentID],
                recovery: "Reload the scan",
                retryable: false
            )
        }
        return parent.children
    }

    public func planClean(scanID: String, itemIDs: [String]) async throws -> CleanPlan {
        try await planDetail(scanID: scanID, itemIDs: itemIDs).plan
    }

    public func planDetail(scanID: String, itemIDs: [String]) async throws -> CleanPlanDetail {
        guard let result = scans[scanID] else {
            throw OpenSimError(
                code: "invalid_argument",
                message: "Unknown scan identifier",
                details: ["scanId": scanID],
                recovery: "Start a new scan with storage_scan",
                retryable: false
            )
        }
        let booted: Set<DeviceID>
        do {
            booted = try await metadata.bootedDeviceIDs()
        } catch {
            throw OpenSimError(
                code: "storage_scan_failed",
                message: "Could not verify booted devices; refusing to create a clean plan",
                details: ["reason": String(describing: error)],
                recovery: "Retry after simulator inventory is available",
                retryable: true
            )
        }
        let flattened = Self.flatten(result.scan.items)
        var snapshots: [CleanPlanItemSnapshot] = []
        var blocked: [BlockedStorageItem] = []
        var total: Int64 = 0
        for id in itemIDs {
            guard let item = flattened[id] else {
                blocked.append(
                    BlockedStorageItem(
                        item: StorageItem(
                            id: id,
                            category: .archive,
                            path: "",
                            sizeBytes: 0,
                            lastUsedAt: nil,
                            safeToDelete: false,
                            reason: "Item is not in this scan",
                            children: []
                        ),
                        reason: "Item is not in this scan"
                    )
                )
                continue
            }
            let verdict = try await verdict(for: item, detail: result.detailsByID[id], booted: booted)
            guard item.safeToDelete, verdict.safeToDelete else {
                blocked.append(BlockedStorageItem(item: item, reason: verdict.reason ?? item.reason ?? "Item is not safe"))
                continue
            }
            let detail = result.detailsByID[id]
            snapshots.append(
                CleanPlanItemSnapshot(
                    itemID: item.id,
                    category: item.category,
                    path: item.path,
                    sizeBytes: item.sizeBytes,
                    modificationTime: fileSystem.modificationDate(atPath: item.path),
                    action: verdict.action,
                    simulatorUDID: Self.simulatorUDID(from: item.path),
                    bundleID: Self.bundleID(from: detail),
                    runtimeIdentifier: Self.runtimeIdentifier(from: detail)
                )
            )
            total += item.sizeBytes
        }
        guard !snapshots.isEmpty else {
            throw OpenSimError(
                code: "storage_in_use",
                message: "All selected items are blocked",
                details: ["blocked": String(blocked.count)],
                recovery: "Choose safe items or shut down the simulator",
                retryable: false
            )
        }
        let stored = try await plans.create(
            scanID: scanID,
            items: snapshots,
            approximate: result.scan.approximate
        )
        let plan = CleanPlan(
            token: stored.token,
            expiresAt: stored.expiresAt,
            itemIDs: stored.items.map(\.itemID),
            reclaimableBytes: stored.reclaimableBytes
        )
        let detailItems = snapshots.compactMap { snapshot in
            result.detailsByID[snapshot.itemID]
        }
        return CleanPlanDetail(
            plan: plan,
            items: detailItems,
            blocked: blocked,
            totalBytes: total,
            approximate: result.scan.approximate,
            requiresTypedConfirmation: stored.requiresTypedConfirmation,
            confirmationPhrase: stored.confirmationPhrase
        )
    }

    public func applyClean(planToken: String, itemIDs: [String]) async throws -> [CleanResultItem] {
        try await applyClean(
            planToken: planToken,
            itemIDs: itemIDs,
            confirmationPhrase: nil,
            actor: "storage-service",
            sessionID: nil,
            leaseID: nil
        ).results
    }

    public func applyClean(
        planToken: String,
        itemIDs: [String],
        confirmationPhrase: String?,
        actor: String,
        sessionID: SessionID?,
        leaseID: LeaseID?
    ) async throws -> CleanApplyResult {
        let plan = try await plans.consume(token: planToken, itemIDs: itemIDs)
        if plan.requiresTypedConfirmation {
            let expected = plan.confirmationPhrase ?? "MULTIPLE"
            guard confirmationPhrase == expected else {
                throw OpenSimError(
                    code: "confirmation_required",
                    message: "Typed confirmation is required for plans above 20 GB",
                    details: [
                        "requiredPhrase": expected,
                        "reclaimableBytes": String(plan.reclaimableBytes)
                    ],
                    recovery: "Ask the owner to type \(expected) and retry apply",
                    retryable: false
                )
            }
        }
        let booted: Set<DeviceID>
        do {
            booted = try await metadata.bootedDeviceIDs()
        } catch {
            throw OpenSimError(
                code: "storage_scan_failed",
                message: "Could not verify booted devices; refusing to apply the clean plan",
                details: ["reason": String(describing: error)],
                recovery: "Retry after simulator inventory is available",
                retryable: true
            )
        }
        for snapshot in plan.items {
            guard fileSystem.fileExists(atPath: snapshot.path) else {
                throw OpenSimError(
                    code: "invalid_argument",
                    message: "Item no longer exists; create a new plan",
                    details: ["itemId": snapshot.itemID, "path": snapshot.path],
                    recovery: "Run storage scan again",
                    retryable: false
                )
            }
            if let expected = snapshot.modificationTime,
               let current = fileSystem.modificationDate(atPath: snapshot.path),
               abs(current.timeIntervalSince(expected)) > 1 {
                throw OpenSimError(
                    code: "storage_in_use",
                    message: "Item changed since the plan was created",
                    details: ["itemId": snapshot.itemID, "path": snapshot.path],
                    recovery: "Create a new clean plan",
                    retryable: false
                )
            }
            let verdict = try await verdict(forSnapshot: snapshot, booted: booted)
            guard verdict.safeToDelete else {
                throw OpenSimError(
                    code: "storage_in_use",
                    message: verdict.reason ?? "Item is in use",
                    details: ["itemId": snapshot.itemID, "path": snapshot.path],
                    recovery: "Shut down the simulator or choose another item",
                    retryable: false
                )
            }
        }
        let results = await executor.apply(plan: plan, actor: actor, sessionID: sessionID, leaseID: leaseID)
        let successfulIDs = Set(results.filter(\.success).map(\.itemID))
        let reclaimed = plan.items
            .filter { successfulIDs.contains($0.itemID) }
            .reduce(Int64(0)) { $0 + $1.sizeBytes }
        return CleanApplyResult(token: planToken, results: results, reclaimedBytes: reclaimed, auditID: nil)
    }

    private func performScan(scanID: String, options: StorageScanOptions) async {
        do {
            let result = try await scanner.scan(
                scanID: scanID,
                options: options,
                progress: { progress in
                    Task { await self.record(progress) }
                }
            )
            scans[scanID] = result
            let summary = StorageScanSummary(
                scanID: scanID,
                totalBytes: result.scan.totalBytes,
                reclaimableBytes: result.scan.reclaimableBytes,
                approximate: result.scan.approximate,
                itemCount: result.scan.items.count,
                completedAt: now()
            )
            var status = statuses[scanID] ?? StorageScanStatus(
                scanID: scanID,
                state: .completed,
                progress: result.scan.items.isEmpty
                    ? StorageScanProgress(scanID: scanID, phase: .completed, completedRoots: 0, totalRoots: 0, bytesSeen: 0, currentPath: nil, fraction: 1)
                    : StorageScanProgress(scanID: scanID, phase: .completed, completedRoots: 1, totalRoots: 1, bytesSeen: result.scan.totalBytes, currentPath: nil, fraction: 1),
                scan: result.scan,
                summary: summary,
                error: nil
            )
            status.state = .completed
            status.scan = result.scan
            status.summary = summary
            status.error = nil
            status.progress.phase = .completed
            status.progress.fraction = 1
            statuses[scanID] = status
            activeScanID = nil
            scanTask = nil
            if let data = try? Self.encoder.encode(summary) {
                await emit("storage.scan.completed", data)
            }
        } catch {
            let mapped = Self.map(error)
            var status = statuses[scanID] ?? StorageScanStatus(
                scanID: scanID,
                state: .failed,
                progress: StorageScanProgress(scanID: scanID, phase: .failed, completedRoots: 0, totalRoots: 0, bytesSeen: 0, currentPath: nil, fraction: 0),
                scan: nil,
                summary: nil,
                error: mapped
            )
            status.state = .failed
            status.error = mapped
            status.progress.phase = .failed
            statuses[scanID] = status
            activeScanID = nil
            scanTask = nil
        }
    }

    private func record(_ progress: StorageScanProgress) async {
        guard var status = statuses[progress.scanID], status.state == .running else {
            return
        }
        status.progress = progress
        statuses[progress.scanID] = status
        if let data = try? Self.encoder.encode(progress) {
            await emit("storage.scan.progress", data)
        }
    }

    private func verdict(
        for item: StorageItem,
        detail: StorageItemDetail?,
        booted: Set<DeviceID>
    ) async throws -> StorageSafetyVerdict {
        switch item.category {
        case .simulatorDevice:
            let udid = Self.simulatorUDID(from: item.path)
            let isBooted = udid.map { value in booted.contains(DeviceID(rawValue: value)) } ?? false
            return StorageSafety.evaluate(
                StorageSafetyFacts(category: .simulatorDevice, isBootedDevice: isBooted)
            )
        case .simulatorCache:
            return StorageSafety.evaluate(
                StorageSafetyFacts(category: .simulatorCache, hasBootedSimulator: !booted.isEmpty)
            )
        case .simulatorLog, .derivedData, .archive:
            return StorageSafety.evaluate(StorageSafetyFacts(category: item.category))
        case .runtime:
            let runtimeID = Self.runtimeIdentifier(from: detail)
            let records = (try? await metadata.runtimes()) ?? []
            let record = records.first { $0.runtime.id.rawValue == runtimeID }
            return StorageSafety.evaluate(
                StorageSafetyFacts(
                    category: .runtime,
                    isDeviceInUse: record.map { !$0.usedByDeviceIDs.isEmpty } ?? false,
                    isSystemOwned: record?.isSystemOwned ?? true
                )
            )
        case .appData:
            let udid = Self.simulatorUDID(from: item.path)
            let isBooted = udid.map { value in booted.contains(DeviceID(rawValue: value)) } ?? false
            return StorageSafety.evaluate(
                StorageSafetyFacts(category: .appData, isBootedDevice: isBooted)
            )
        }
    }

    private func verdict(
        forSnapshot snapshot: CleanPlanItemSnapshot,
        booted: Set<DeviceID>
    ) async throws -> StorageSafetyVerdict {
        switch snapshot.category {
        case .simulatorDevice:
            let isBooted = snapshot.simulatorUDID.map { booted.contains(DeviceID(rawValue: $0)) } ?? false
            return StorageSafety.evaluate(
                StorageSafetyFacts(category: .simulatorDevice, isBootedDevice: isBooted)
            )
        case .simulatorCache:
            return StorageSafety.evaluate(
                StorageSafetyFacts(category: .simulatorCache, hasBootedSimulator: !booted.isEmpty)
            )
        case .simulatorLog, .derivedData, .archive:
            return StorageSafety.evaluate(StorageSafetyFacts(category: snapshot.category))
        case .runtime:
            let records = (try? await metadata.runtimes()) ?? []
            let record = records.first { $0.runtime.id.rawValue == snapshot.runtimeIdentifier }
            return StorageSafety.evaluate(
                StorageSafetyFacts(
                    category: .runtime,
                    isDeviceInUse: record.map { !$0.usedByDeviceIDs.isEmpty } ?? false,
                    isSystemOwned: record?.isSystemOwned ?? true
                )
            )
        case .appData:
            let isBooted = snapshot.simulatorUDID.map { booted.contains(DeviceID(rawValue: $0)) } ?? false
            return StorageSafety.evaluate(
                StorageSafetyFacts(category: .appData, isBootedDevice: isBooted)
            )
        }
    }

    private static func flatten(_ items: [StorageItem]) -> [String: StorageItem] {
        var result: [String: StorageItem] = [:]
        var stack = items
        while let item = stack.popLast() {
            result[item.id] = item
            stack.append(contentsOf: item.children)
        }
        return result
    }

    private static func findItem(id: String, in items: [StorageItem]) -> StorageItem? {
        var stack = items
        while let item = stack.popLast() {
            if item.id == id { return item }
            stack.append(contentsOf: item.children)
        }
        return nil
    }

    private static func simulatorUDID(from path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        guard let index = components.firstIndex(of: "Devices"), index + 1 < components.count else {
            return nil
        }
        return components[index + 1]
    }

    private static func bundleID(from detail: StorageItemDetail?) -> String? {
        guard let detail, case let .appData(metadata) = detail.metadata else { return nil }
        return metadata.bundleID
    }

    private static func runtimeIdentifier(from detail: StorageItemDetail?) -> String? {
        guard let detail, case let .runtime(metadata) = detail.metadata else { return nil }
        return metadata.runtimeIdentifier
    }

    private static func map(_ error: Error) -> OpenSimError {
        if let openSimError = error as? OpenSimError {
            return openSimError
        }
        return OpenSimError(
            code: "storage_scan_failed",
            message: error.localizedDescription,
            details: [:],
            recovery: "Retry the scan",
            retryable: true
        )
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
```

- [ ] **Step 5: Viết HTTP controller và adapter**

Create `Sources/OpenSimDaemon/Storage/StorageHTTP.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

public struct StorageHTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var body: Data

    public init(method: String, path: String, query: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }
}

public struct StorageHTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public struct StorageHTTPController: Sendable {
    private let service: any StorageServing
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(service: any StorageServing) {
        self.service = service
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func handle(_ request: StorageHTTPRequest) async -> StorageHTTPResponse? {
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[0] == "v1", parts[1] == "storage" else {
            return nil
        }
        do {
            if request.method == "POST", parts == ["v1", "storage", "scans"] {
                let body = try decoder.decode(StorageScanRequest.self, from: request.body)
                let options = StorageScanOptions(
                    categories: body.categories,
                    refresh: body.refresh,
                    includeAppContainers: body.includeAppContainers
                )
                let status = try await service.beginScan(options: options)
                return try reply(status, statusCode: 202)
            }
            if request.method == "GET", parts.count == 4, parts[2] == "scans" {
                let status = try await service.scanStatus(id: parts[3])
                return try reply(status, statusCode: 200)
            }
            if request.method == "GET", parts.count == 5, parts[2] == "scans", parts[4] == "items" {
                let items = try await service.storageItems(
                    scanID: parts[3],
                    parentID: request.query["parent"]
                )
                return try reply(items, statusCode: 200)
            }
            if request.method == "POST", parts == ["v1", "storage", "clean-plans"] {
                let body = try decoder.decode(CleanPlanRequest.self, from: request.body)
                let detail = try await service.planDetail(scanID: body.scanID, itemIDs: body.itemIDs)
                return try reply(detail, statusCode: 201)
            }
            if request.method == "POST", parts.count == 5, parts[2] == "clean-plans", parts[4] == "apply" {
                let body = try decoder.decode(CleanApplyRequest.self, from: request.body)
                let result = try await service.applyClean(
                    planToken: parts[3],
                    itemIDs: body.itemIDs,
                    confirmationPhrase: body.confirmationPhrase,
                    actor: "http",
                    sessionID: nil,
                    leaseID: nil
                )
                return try reply(result, statusCode: 200)
            }
            return nil
        } catch let error as OpenSimError {
            return errorReply(error)
        } catch {
            return errorReply(
                OpenSimError(
                    code: "internal",
                    message: error.localizedDescription,
                    details: [:],
                    recovery: nil,
                    retryable: false
                )
            )
        }
    }

    private func reply<T: Codable & Sendable>(_ data: T, statusCode: Int) throws -> StorageHTTPResponse {
        let envelope = Envelope(
            schemaVersion: 1,
            ok: true,
            data: data,
            error: nil,
            meta: ResponseMeta(requestId: UUID().uuidString, durationMs: 0)
        )
        let body = try encoder.encode(envelope)
        return StorageHTTPResponse(
            status: statusCode,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body
        )
    }

    private func errorReply(_ error: OpenSimError) -> StorageHTTPResponse {
        let statusCode: Int
        switch error.code {
        case "invalid_argument":
            statusCode = 400
        case "storage_in_use", "storage_scan_failed":
            statusCode = 409
        case "confirmation_required":
            statusCode = 428
        default:
            statusCode = 500
        }
        let envelope = Envelope<EmptyPayload>(
            schemaVersion: 1,
            ok: false,
            data: nil,
            error: error,
            meta: ResponseMeta(requestId: UUID().uuidString, durationMs: 0)
        )
        let body = (try? encoder.encode(envelope)) ?? Data()
        return StorageHTTPResponse(
            status: statusCode,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body
        )
    }
}
```

Create `Sources/OpenSimDaemon/Storage/StorageHTTPAdapter.swift`:

```swift
import Foundation

public struct StorageHTTPAdapter: Sendable {
    private let controller: StorageHTTPController

    public init(controller: StorageHTTPController) {
        self.controller = controller
    }

    public func handle(
        method: String,
        path: String,
        query: [String: String],
        body: Data
    ) async -> StorageHTTPResponse? {
        await controller.handle(
            StorageHTTPRequest(method: method, path: path, query: query, body: body)
        )
    }
}
```

Create `Sources/OpenSimDaemon/Storage/StorageOperationHandler.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

public struct StorageOperationHandler: Sendable {
    private let service: StorageService
    private let encoder: JSONEncoder

    public init(service: StorageService) {
        self.service = service
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func handle(_ request: OperationRequest) async throws -> Data {
        switch request.operation {
        case "storage_scan":
            let categories = request.parameters["categories"]?
                .split(separator: ",")
                .compactMap { StorageCategory(rawValue: String($0)) }
            let options = StorageScanOptions(
                categories: categories?.isEmpty == false ? categories : nil,
                refresh: request.parameters["refresh"] == "true",
                includeAppContainers: request.parameters["includeAppContainers"] != "false"
            )
            let status = try await service.beginScan(options: options)
            let scan = try await service.waitForScan(id: status.scanID)
            return try encoder.encode(scan)
        case "storage_list":
            guard let scanID = request.parameters["scanId"] else {
                throw OpenSimError(
                    code: "invalid_argument",
                    message: "scanId is required",
                    details: [:],
                    recovery: "Run storage_scan first",
                    retryable: false
                )
            }
            let items = try await service.storageItems(
                scanID: scanID,
                parentID: request.parameters["parent"]
            )
            return try encoder.encode(items)
        case "storage_clean":
            guard let rawIDs = request.parameters["itemIds"], !rawIDs.isEmpty else {
                throw OpenSimError(
                    code: "invalid_argument",
                    message: "itemIds is required",
                    details: [:],
                    recovery: "Select at least one item",
                    retryable: false
                )
            }
            let itemIDs = rawIDs.split(separator: ",").map(String.init)
            if let token = request.parameters["planToken"], !token.isEmpty {
                let result = try await service.applyClean(
                    planToken: token,
                    itemIDs: itemIDs,
                    confirmationPhrase: request.parameters["confirmationPhrase"],
                    actor: request.sessionID?.rawValue ?? "cli",
                    sessionID: request.sessionID,
                    leaseID: request.leaseID
                )
                return try encoder.encode(result)
            }
            guard let scanID = request.parameters["scanId"] else {
                throw OpenSimError(
                    code: "invalid_argument",
                    message: "scanId is required to create a clean plan",
                    details: [:],
                    recovery: "Run storage_scan first",
                    retryable: false
                )
            }
            let detail = try await service.planDetail(scanID: scanID, itemIDs: itemIDs)
            let dryRun = request.dryRun == true || request.parameters["dryRun"] == "true"
                || request.parameters["confirm"] != "true"
            if dryRun {
                return try encoder.encode(detail)
            }
            let applied = try await service.applyClean(
                planToken: detail.plan.token,
                itemIDs: detail.plan.itemIDs,
                confirmationPhrase: request.parameters["confirmationPhrase"],
                actor: request.sessionID?.rawValue ?? "cli",
                sessionID: request.sessionID,
                leaseID: request.leaseID
            )
            return try encoder.encode(applied)
        default:
            throw OpenSimError(
                code: "invalid_argument",
                message: "Unknown storage operation \(request.operation)",
                details: [:],
                recovery: nil,
                retryable: false
            )
        }
    }
}
```

Nối handler vào `Sources/OpenSimDaemon/Operations/OperationDispatcher.swift` của Plan 3: thêm `serviceHandlers: [String: @Sendable (OperationRequest) async throws -> Data]` vào init với default `[:]`, và trong `dispatch` thay lời gọi executor bằng:

```swift
let data: Data
if let handler = serviceHandlers[operation.mcpName] {
    data = try await handler(request)
} else {
    data = try await executor.execute(operation: operation.mcpName, parameters: request.parameters)
}
```

Composition của daemon tạo `StorageOperationHandler(service: storageService)` và truyền dictionary `["storage_scan": handler, "storage_list": handler, "storage_clean": handler]`.

Nối vào Plan 3: trong `Sources/OpenSimDaemon/Server/DaemonServer.swift`, tại cuối chuỗi xử lý request trước nhánh 404, thêm lời gọi adapter với method, path, query và body của Plan 3; nếu adapter trả response thì map status/headers/body sang response của Plan 3. Không đổi route, auth hoặc lease của Plan 3. Operation dispatcher của Plan 3 ánh xạ `storage_scan` → `StorageService.scanStorage(refresh:)`, `storage_list` → `storageItems(scanID:parentID:)`, `storage_clean` dry run → `planDetail`, `storage_clean` confirm/apply → `applyClean`, và phát SSE `storage.scan.progress`/`storage.scan.completed` qua `emit` được inject.

- [ ] **Step 6: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimDaemonTests.StorageHTTPTests
```

Expected: PASS 4 test. Test apply kiểm tra `confirmationPhrase` được chuyển nguyên vẹn.

- [ ] **Step 7: Commit**

```bash
git add Sources/OpenSimProtocol/StorageMessages.swift Sources/OpenSimDaemon/Storage/StorageService.swift Sources/OpenSimDaemon/Storage/StorageHTTP.swift Sources/OpenSimDaemon/Storage/StorageHTTPAdapter.swift Sources/OpenSimDaemon/Storage/StorageOperationHandler.swift Sources/OpenSimDaemon/Server/DaemonServer.swift Sources/OpenSimDaemon/Operations/OperationDispatcher.swift Tests/OpenSimDaemonTests/StorageHTTPTests.swift
git commit -m "feat(storage): add storage service, HTTP controller and SSE"
```

### Task 9A: DaemonRunner wiring storage/perf

**Files:**
- Modify: `Sources/OpenSimDaemon/Runtime/DaemonRunner.swift`, `Sources/OpenSimDaemon/Storage/StorageHTTPAdapter.swift`, `Sources/OpenSimDaemon/Metrics/MetricsHTTP.swift`
- Test: `Tests/IntegrationTests/StorageIntegrationTests.swift`, `Tests/IntegrationTests/MetricsIntegrationTests.swift`

**Interfaces:**
- Consumes: `DaemonRunConfiguration.routeProviders`, `StorageService`, `MetricsSampler`, `EventHub`.
- Produces: `StorageRouteProvider`, `MetricsRouteProvider`; sampler lifecycle; real HTTP endpoints.

- [ ] **Step 1: Viết HTTP test thất bại**

```swift
func testDaemonMountsStorageAndPerfRoutes() async throws {
    let baseURL = try await startTestDaemon()
    let storage = try await HTTP.get("\(baseURL)/v1/storage/scans/00000000-0000-0000-0000-000000000000")
    XCTAssertNotEqual(storage.status, 404)
    let perf = try await HTTP.get("\(baseURL)/v1/perf/devices")
    XCTAssertEqual(perf.status, 200)
}
```

- [ ] **Step 2: Implement**

- Trong `DaemonRunner`, tạo `StorageService` và `MetricsSampler` từ bridge/metadata/fileSystem đã có; append `StorageRouteProvider`/`MetricsRouteProvider` vào `configuration.routeProviders` trước `DaemonServer.start`.
- Gọi `metrics.start()` khi `AppFeature.performance` bật; `defer { metrics.stop() }`/shutdown hook. Không để sampler chỉ tồn tại trong test.
- `StorageHTTPAdapter`/`MetricsHTTP` là route provider của Plan 3; không thêm nhánh 404 thủ công, không tạo server thứ hai.
- Test chạy daemon thật (không mock) với home tạm; assert route không 404 và perf trả envelope.

- [ ] **Step 3: Chạy + commit**

```bash
swift test --filter IntegrationTests.StorageIntegrationTests
swift test --filter IntegrationTests.MetricsIntegrationTests
git add Sources/OpenSimDaemon/Runtime/DaemonRunner.swift Sources/OpenSimDaemon/Storage/StorageHTTPAdapter.swift Sources/OpenSimDaemon/Metrics/MetricsHTTP.swift Tests/IntegrationTests
git commit -m "feat(daemon): mount storage and metrics routes"
```
---

### Task 10: Command catalog và CLI storage

**Files:**
- Create: `Sources/OpenSimCore/Catalog/StoragePerformanceOperations.swift`
- Create: `Sources/OpenSimCore/Catalog/OpenSimCatalog.swift` (`openSim()` factory)
- Create: `Sources/OpenSimCLI/Output/StorageTable.swift`
- Create: `Sources/OpenSimCLI/Commands/StorageCommand.swift`
- Create: `Tests/OpenSimCLITests/Support/GoldenDocument.swift`
- Create: `Tests/OpenSimCLITests/Goldens/storage-scan.json`
- Test: `Tests/OpenSimCLITests/StorageCommandTests.swift`

**Interfaces:**
- Consumes: `Operation`, `OperationCatalog`, `OperationParameter`, `StorageScan`, `StorageItem`, `CleanPlanDetail`, `CleanApplyResult`.
- Produces: `OperationCatalog.registerStoragePerformanceOperations()`, `OperationCatalog.openSim()`, `OperationExecuting`, `StorageCommandRunner`, `StorageJSON.envelope(data:requestID:durationMs:)`, `StorageTable.render(scan:)`, `GoldenDocument.load(_:)`, `GoldenDocument.canonicalize(_:)`.

- [ ] **Step 1: Viết test golden thất bại**

Create `Tests/OpenSimCLITests/Support/GoldenDocument.swift`:

```swift
import Foundation

public enum GoldenDocument {
    public static func load(_ name: String, file: StaticString = #filePath) throws -> Data {
        let directory = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens")
        return try Data(contentsOf: directory.appendingPathComponent(name))
    }

    public static func canonicalize(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    }
}
```

Create `Tests/OpenSimCLITests/Goldens/storage-scan.json`:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "data": {
    "id": "scan-fixture",
    "createdAt": "2026-10-20T10:00:00Z",
    "approximate": true,
    "items": [
      {
        "id": "archive-root",
        "category": "archive",
        "path": "/tmp/opensim-fixtures/Archives",
        "sizeBytes": 3145728,
        "safeToDelete": false,
        "reason": "Category root is not a clean target",
        "children": [
          {
            "id": "archive-item",
            "category": "archive",
            "path": "/tmp/opensim-fixtures/Archives/2026-10-20/MyApp.xcarchive",
            "sizeBytes": 3145728,
            "lastUsedAt": "2026-10-20T09:00:00Z",
            "safeToDelete": true,
            "children": []
          }
        ]
      }
    ],
    "totalBytes": 3145728,
    "reclaimableBytes": 3145728
  },
  "error": null,
  "meta": {
    "requestId": "req-fixed",
    "durationMs": 0
  }
}
```

Create `Tests/OpenSimCLITests/StorageCommandTests.swift`:

```swift
import XCTest
@testable import OpenSimCLI
@testable import OpenSimCore

final class StorageCommandTests: XCTestCase {
    private struct FakeOperationClient: OperationExecuting {
        var payload: Data
        var calls: CallRecorder
        func execute(operation: String, parameters: [String: String]) async throws -> Data {
            await calls.record(operation: operation, parameters: parameters)
            return payload
        }
    }

    private actor CallRecorder {
        var operations: [String] = []
        var parameters: [[String: String]] = []
        func record(operation: String, parameters: [String: String]) {
            operations.append(operation)
            self.parameters.append(parameters)
        }
    }

    private func fixtureScan() -> StorageScan {
        let child = StorageItem(
            id: "archive-item",
            category: .archive,
            path: "/tmp/opensim-fixtures/Archives/2026-10-20/MyApp.xcarchive",
            sizeBytes: 3_145_728,
            lastUsedAt: ISO8601DateFormatter().date(from: "2026-10-20T09:00:00Z"),
            safeToDelete: true,
            reason: nil,
            children: []
        )
        let root = StorageItem(
            id: "archive-root",
            category: .archive,
            path: "/tmp/opensim-fixtures/Archives",
            sizeBytes: 3_145_728,
            lastUsedAt: nil,
            safeToDelete: false,
            reason: "Category root is not a clean target",
            children: [child]
        )
        return StorageScan(
            id: "scan-fixture",
            createdAt: ISO8601DateFormatter().date(from: "2026-10-20T10:00:00Z") ?? Date(),
            approximate: true,
            items: [root],
            totalBytes: 3_145_728,
            reclaimableBytes: 3_145_728
        )
    }

    func testScanJSONMatchesGolden() async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let client = FakeOperationClient(
            payload: try encoder.encode(fixtureScan()),
            calls: CallRecorder()
        )
        let runner = StorageCommandRunner(
            client: client,
            requestID: { "req-fixed" },
            durationMs: { 0 }
        )

        let output = try await runner.scan(refresh: true, categories: nil, json: true)
        let expected = try GoldenDocument.load("storage-scan.json")

        XCTAssertEqual(
            try GoldenDocument.canonicalize(Data(output.utf8)),
            try GoldenDocument.canonicalize(expected)
        )
        let operations = await client.calls.operations
        XCTAssertEqual(operations, ["storage_scan"])
        let parameters = await client.calls.parameters
        XCTAssertEqual(parameters.first?["refresh"], "true")
    }

    func testCleanWithoutPlanTokenIsDestructiveOperation() async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let result = CleanApplyResult(
            token: "token-1",
            results: [CleanResultItem(itemID: "archive-item", success: true, error: nil)],
            reclaimedBytes: 3_145_728,
            auditID: "audit-1"
        )
        let client = FakeOperationClient(payload: try encoder.encode(result), calls: CallRecorder())
        let runner = StorageCommandRunner(client: client, requestID: { "req-fixed" }, durationMs: { 0 })

        _ = try await runner.cleanApply(
            token: "token-1",
            itemIDs: ["archive-item"],
            confirmationPhrase: "ARCHIVES",
            json: true
        )
        let parameters = await client.calls.parameters
        XCTAssertEqual(parameters.first?["planToken"], "token-1")
        XCTAssertEqual(parameters.first?["confirmationPhrase"], "ARCHIVES")
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimCLITests.StorageCommandTests
```

Expected: FAIL vì `StorageCommandRunner` chưa tồn tại.

- [ ] **Step 3: Đăng ký catalog**

Create `Sources/OpenSimCore/Catalog/StoragePerformanceOperations.swift`:

```swift
import Foundation

public protocol OperationExecuting: Sendable {
    func execute(operation: String, parameters: [String: String]) async throws -> Data
}

extension OperationCatalog {
    public mutating func registerStoragePerformanceOperations() {
        register(
            Operation(
                cliPath: ["storage", "scan"],
                mcpName: "storage_scan",
                summary: "Scan simulator, Xcode and runtime storage",
                requiresControlLease: false,
                destructive: false,
                readOnly: true,
                parameters: [
                    OperationParameter(name: "refresh", type: "bool", required: false, defaultValue: "false"),
                    OperationParameter(name: "categories", type: "string", required: false, defaultValue: nil),
                    OperationParameter(name: "includeAppContainers", type: "bool", required: false, defaultValue: "true")
                ]
            )
        )
        register(
            Operation(
                cliPath: ["storage", "list"],
                mcpName: "storage_list",
                summary: "List storage items from a completed scan",
                requiresControlLease: false,
                destructive: false,
                readOnly: true,
                parameters: [
                    OperationParameter(name: "scanId", type: "string", required: true, defaultValue: nil),
                    OperationParameter(name: "parent", type: "string", required: false, defaultValue: nil)
                ]
            )
        )
        register(
            Operation(
                cliPath: ["storage", "clean"],
                mcpName: "storage_clean",
                summary: "Plan or apply a storage clean plan",
                requiresControlLease: true,
                destructive: true,
                readOnly: false,
                parameters: [
                    OperationParameter(name: "scanId", type: "string", required: false, defaultValue: nil),
                    OperationParameter(name: "itemIds", type: "string", required: true, defaultValue: nil),
                    OperationParameter(name: "planToken", type: "string", required: false, defaultValue: nil),
                    OperationParameter(name: "confirmationPhrase", type: "string", required: false, defaultValue: nil),
                    OperationParameter(name: "dryRun", type: "bool", required: false, defaultValue: "false"),
                    OperationParameter(name: "confirm", type: "bool", required: false, defaultValue: "false")
                ]
            )
        )
        register(
            Operation(
                cliPath: ["perf", "top"],
                mcpName: "perf_devices",
                summary: "Read recent device metrics or the latest snapshot",
                requiresControlLease: false,
                destructive: false,
                readOnly: true,
                parameters: [
                    OperationParameter(name: "since", type: "string", required: false, defaultValue: nil),
                    OperationParameter(name: "device", type: "string", required: false, defaultValue: nil)
                ]
            )
        )
        register(
            Operation(
                cliPath: ["perf", "stats"],
                mcpName: "perf_processes",
                summary: "List processes mapped to a simulator device",
                requiresControlLease: false,
                destructive: false,
                readOnly: true,
                parameters: [
                    OperationParameter(name: "device", type: "string", required: true, defaultValue: nil)
                ]
            )
        )
    }
}
```

- [ ] **Step 4: Viết output và runner**

Create `Sources/OpenSimCLI/Output/StorageTable.swift`:

```swift
import Foundation
import OpenSimCore

public enum StorageTable {
    public static func render(scan: StorageScan) -> String {
        var lines: [String] = []
        lines.append("CATEGORY            SIZE        RECLAIMABLE  ITEMS")
        for item in scan.items {
            let size = ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file)
            let reclaimable = item.children.filter(\.safeToDelete).reduce(Int64(0)) { $0 + $1.sizeBytes }
            let reclaimText = ByteCountFormatter.string(fromByteCount: reclaimable, countStyle: .file)
            lines.append(
                "\(item.category.rawValue.padding(toLength: 18, withPad: " ", startingAt: 0)) \(size.padding(toLength: 11, withPad: " ", startingAt: 0)) \(reclaimText.padding(toLength: 12, withPad: " ", startingAt: 0)) \(item.children.count)"
            )
        }
        lines.append("TOTAL               \(ByteCountFormatter.string(fromByteCount: scan.totalBytes, countStyle: .file))")
        lines.append("APPROXIMATE         \(scan.approximate ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }
}

public enum StorageJSON {
    public static func envelope(
        data payload: Data,
        requestID: String,
        durationMs: Int
    ) throws -> String {
        let object = try JSONSerialization.jsonObject(with: payload)
        let envelope: [String: Any] = [
            "schemaVersion": 1,
            "ok": true,
            "data": object,
            "error": NSNull(),
            "meta": [
                "requestId": requestID,
                "durationMs": durationMs
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys, .prettyPrinted])
        return String(decoding: data, as: UTF8.self)
    }
}
```

Create `Sources/OpenSimCLI/Commands/StorageCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimCore
import OpenSimDaemon

public struct StorageCommandRunner: Sendable {
    private let client: any OperationExecuting
    private let requestID: @Sendable () -> String
    private let durationMs: @Sendable () -> Int

    public init(
        client: any OperationExecuting,
        requestID: @escaping @Sendable () -> String = { UUID().uuidString },
        durationMs: @escaping @Sendable () -> Int = { 0 }
    ) {
        self.client = client
        self.requestID = requestID
        self.durationMs = durationMs
    }

    public func scan(refresh: Bool, categories: [StorageCategory]?, json: Bool) async throws -> String {
        var parameters = ["refresh": refresh ? "true" : "false"]
        if let categories, !categories.isEmpty {
            parameters["categories"] = categories.map(\.rawValue).joined(separator: ",")
        }
        let data = try await client.execute(operation: "storage_scan", parameters: parameters)
        if json {
            return try StorageJSON.envelope(data: data, requestID: requestID(), durationMs: durationMs())
        }
        let scan = try JSONDecoder.iso.decode(StorageScan.self, from: data)
        return StorageTable.render(scan: scan)
    }

    public func list(scanID: String, parentID: String?, json: Bool) async throws -> String {
        var parameters = ["scanId": scanID]
        if let parentID {
            parameters["parent"] = parentID
        }
        let data = try await client.execute(operation: "storage_list", parameters: parameters)
        if json {
            return try StorageJSON.envelope(data: data, requestID: requestID(), durationMs: durationMs())
        }
        let items = try JSONDecoder.iso.decode([StorageItem].self, from: data)
        return items.map { item in
            "\(item.id)  \(item.category.rawValue)  \(item.sizeBytes)  safe=\(item.safeToDelete)"
        }.joined(separator: "\n")
    }

    public func cleanPlan(scanID: String, itemIDs: [String], json: Bool) async throws -> String {
        let parameters = [
            "scanId": scanID,
            "itemIds": itemIDs.joined(separator: ","),
            "dryRun": "true",
            "confirm": "false"
        ]
        let data = try await client.execute(operation: "storage_clean", parameters: parameters)
        if json {
            return try StorageJSON.envelope(data: data, requestID: requestID(), durationMs: durationMs())
        }
        let detail = try JSONDecoder.iso.decode(CleanPlanDetail.self, from: data)
        var lines = [
            "TOKEN \(detail.plan.token)",
            "EXPIRES \(ISO8601DateFormatter().string(from: detail.plan.expiresAt))",
            "RECLAIMABLE \(detail.plan.reclaimableBytes)",
            "PHRASE \(detail.confirmationPhrase ?? "none")"
        ]
        lines.append(contentsOf: detail.blocked.map { "BLOCKED \($0.item.path): \($0.reason)" })
        return lines.joined(separator: "\n")
    }

    public func cleanApply(
        token: String,
        itemIDs: [String],
        confirmationPhrase: String?,
        json: Bool
    ) async throws -> String {
        var parameters = [
            "itemIds": itemIDs.joined(separator: ","),
            "planToken": token,
            "confirm": "true"
        ]
        if let confirmationPhrase {
            parameters["confirmationPhrase"] = confirmationPhrase
        }
        let data = try await client.execute(operation: "storage_clean", parameters: parameters)
        if json {
            return try StorageJSON.envelope(data: data, requestID: requestID(), durationMs: durationMs())
        }
        let result = try JSONDecoder.iso.decode(CleanApplyResult.self, from: data)
        return result.results.map { item in
            "\(item.itemID) success=\(item.success) error=\(item.error?.code ?? "none")"
        }.joined(separator: "\n")
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct StorageCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "storage",
        abstract: "Scan and clean simulator, Xcode and runtime storage",
        subcommands: [Scan.self, List.self, Clean.self, Reveal.self]
    )

    public init() {}

    public struct Scan: AsyncParsableCommand {
        @Flag(name: .long) var json = false
        @Flag(name: .long) var refresh = false
        @Option(name: .long, parsing: .upToNextOption) var category: [String] = []

        public init() {}

        public func run() async throws {
            let client = try await DaemonLauncher.ensureRunning()
            let runner = StorageCommandRunner(client: client)
            let categories = category.compactMap(StorageCategory.init(rawValue:))
            print(try await runner.scan(refresh: refresh, categories: categories, json: json))
        }
    }

    public struct List: AsyncParsableCommand {
        @Option(name: .long) var scan: String
        @Option(name: .long) var parent: String?
        @Flag(name: .long) var json = false

        public init() {}

        public func run() async throws {
            let client = try await DaemonLauncher.ensureRunning()
            let runner = StorageCommandRunner(client: client)
            print(try await runner.list(scanID: scan, parentID: parent, json: json))
        }
    }

    public struct Clean: AsyncParsableCommand {
        @Option(name: .long) var scan: String?
        @Option(name: .long, parsing: .upToNextOption) var item: [String] = []
        @Option(name: .long) var apply: String?
        @Option(name: .long) var confirmPhrase: String?
        @Flag(name: .long) var json = false

        public init() {}

        public func run() async throws {
            let client = try await DaemonLauncher.ensureRunning()
            let runner = StorageCommandRunner(client: client)
            if let apply {
                print(try await runner.cleanApply(
                    token: apply,
                    itemIDs: item,
                    confirmationPhrase: confirmPhrase,
                    json: json
                ))
                return
            }
            guard let scan else {
                throw ValidationError("--scan is required when --apply is not provided")
            }
            print(try await runner.cleanPlan(scanID: scan, itemIDs: item, json: json))
        }
    }

    public struct Reveal: AsyncParsableCommand {
        @Option(name: .long) var path: String

        public init() {}

        public func run() async throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-R", path]
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw ExitCode(10)
            }
        }
    }
}
```

`DaemonClient` và `DaemonLauncher` do Plan 3 cung cấp trong `Sources/OpenSimDaemon/Client/`. Thêm extension sau vào cuối `StorageCommand.swift` để CLI dùng operation qua daemon:

```swift
import OpenSimDaemon

extension DaemonClient: OperationExecuting {
    public func execute(operation: String, parameters: [String: String]) async throws -> Data {
        try await operation(OperationRequest(operation: operation, parameters: parameters)).data
    }
}
```

`StorageCommandRunner` và test không phụ thuộc client cụ thể.

`StoragePerformanceOperations.swift` chỉ chứa `registerStoragePerformanceOperations()` (metadata storage/perf). Factory nằm trong `OpenSimCatalog.swift`:

```swift
public extension OperationCatalog {
    static func plan5() -> OperationCatalog {
        var catalog = OperationCatalog.plan3()
        catalog.registerStoragePerformanceOperations()
        return catalog
    }

    static func openSim() -> OperationCatalog {
        plan5()
    }
}
```

`openSim()` là factory duy nhất từ Plan 5 trở đi. Plan 7/9/10 không tạo factory mới: Plan 9 thêm physical vào `openSim()`, Plan 10 thêm Android vào cùng function. `plan5()` chỉ là base nội bộ; daemon/CLI/MCP và release gate dùng `openSim()`. Test catalog phải assert có đồng thời `ui_tap`, `storage_scan`, `perf_devices`.

- [ ] **Step 5: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimCLITests.StorageCommandTests
```

Expected: PASS 2 test. Golden so sánh canonical JSON; nếu khác, đọc diff và sửa renderer, không sửa golden để che lỗi.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenSimCore/Catalog/StoragePerformanceOperations.swift Sources/OpenSimCore/Catalog/OpenSimCatalog.swift Sources/OpenSimCLI/Output/StorageTable.swift Sources/OpenSimCLI/Commands/StorageCommand.swift Tests/OpenSimCLITests/Support/GoldenDocument.swift Tests/OpenSimCLITests/Goldens/storage-scan.json Tests/OpenSimCLITests/StorageCommandTests.swift
git commit -m "feat(cli): add storage command with JSON golden"
```

---

### Task 11: MCP storage tools qua operation catalog

**Files:**
- Modify: `Sources/OpenSimMCP/MCPHandler.swift`, `Sources/OpenSimMCP/ToolCatalogAdapter.swift`
- Test: `Tests/OpenSimMCPTests/StorageToolsTests.swift`

**Interfaces:**
- Consumes: `OperationCatalog.openSim()`, `ToolCatalogAdapter`, `MCPHandler`, `OperationDispatcher`.
- Produces: `tools/list` và `tools/call` cho `storage_scan`, `storage_list`, `storage_clean`; không có `StorageToolSpec` song song.

- [ ] **Step 1: Viết test catalog-first**

```swift
import XCTest
@testable import OpenSimMCP
@testable import OpenSimCore

final class StorageToolsTests: XCTestCase {
    func testStorageToolsComeFromCatalog() {
        let tools = ToolCatalogAdapter.tools(from: OperationCatalog.openSim())
        let names = Set(tools.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["storage_scan", "storage_list", "storage_clean"]))
        XCTAssertTrue(tools.first { $0.name == "storage_clean" }?.destructive ?? false)
    }
}
```

- [ ] **Step 2: Implement**

- Không tạo `StorageTools.specs`/`StorageTools.call`; `ToolCatalogAdapter` sinh schema từ `Operation` metadata.
- `MCPHandler` route `storage_*` qua `OperationDispatcher` và daemon client; không hardcode danh sách tool.
- `storage_scan`/`storage_list` read; `storage_clean` destructive cần `confirm` hoặc `planToken`; dry-run được phép trước confirm.
- MCP tool names phải khớp `OpenSimCatalog.openSim()`; test `tools/list` từ daemon thật, không chỉ unit catalog.

- [ ] **Step 3: Chạy test + commit**

```bash
swift test --filter OpenSimMCPTests.StorageToolsTests
git add Sources/OpenSimMCP Tests/OpenSimMCPTests/StorageToolsTests.swift
git commit -m "feat(mcp): expose storage tools from operation catalog"
```
---

### Task 12: Process sampling và mapping theo UDID

**Files:**
- Create: `Sources/OpenSimDaemon/Metrics/ProcessRecord.swift`
- Create: `Sources/OpenSimDaemon/Metrics/LibProcProcessSampler.swift`
- Create: `Sources/OpenSimDaemon/Metrics/ProcessMapper.swift`
- Test: `Tests/OpenSimDaemonTests/ProcessMapperTests.swift`

**Interfaces:**
- Consumes: `DeviceID`, `ProcessSample` từ contract.
- Produces: `ProcessRecord`, `ProcessSampling`, `LibProcProcessSampler`, `ProcessMapping`, `ProcessMapper.map(_:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimDaemonTests/ProcessMapperTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon

final class ProcessMapperTests: XCTestCase {
    private let deviceID = DeviceID(rawValue: "11111111-2222-3333-4444-555555555555")

    private func record(
        pid: Int32,
        parent: Int32,
        name: String,
        path: String = "/usr/libexec/launchd_sim",
        arguments: [String] = [],
        environmentUDID: String? = nil,
        userTime: UInt64 = 0
    ) -> ProcessRecord {
        ProcessRecord(
            pid: pid,
            parentPID: parent,
            name: name,
            executablePath: path,
            userTimeNanoseconds: userTime,
            systemTimeNanoseconds: 0,
            memoryFootprintBytes: 1_024,
            diskReadBytes: 0,
            diskWriteBytes: 0,
            arguments: arguments,
            environmentUDID: environmentUDID
        )
    }

    func testMapsLaunchdAndDescendantsByArguments() {
        let launchdArguments = [
            "/Applications/Xcode.app/Contents/Developer/usr/bin/launchd_sim",
            "/Users/tester/Library/Developer/CoreSimulator/Devices/\(deviceID.rawValue)/data"
        ]
        let records = [
            record(pid: 100, parent: 1, name: "launchd_sim", arguments: launchdArguments),
            record(pid: 101, parent: 100, name: "SpringBoard"),
            record(pid: 102, parent: 101, name: "MyApp")
        ]

        let mapping = ProcessMapper().map(records)

        XCTAssertEqual(mapping.groups[deviceID]?.map(\.pid) ?? [], [100, 101, 102] as [Int32])
        XCTAssertTrue(mapping.unknown.isEmpty)
    }

    func testMapsOrphanByEnvironmentUDID() {
        let records = [
            record(pid: 200, parent: 1, name: "SimulatorTrampoline", environmentUDID: deviceID.rawValue)
        ]

        let mapping = ProcessMapper().map(records)

        XCTAssertEqual(mapping.groups[deviceID]?.map(\.pid), [200])
    }

    func testUnmappedLaunchdGoesToUnknown() {
        let records = [
            record(pid: 300, parent: 1, name: "launchd_sim", arguments: ["/usr/libexec/launchd_sim"]),
            record(pid: 301, parent: 300, name: "SpringBoard")
        ]

        let mapping = ProcessMapper().map(records)

        XCTAssertTrue(mapping.groups.isEmpty)
        XCTAssertEqual(mapping.unknown.map(\.pid), [300])
    }

    func testInvalidUDIDIsNotMapped() {
        let records = [
            record(
                pid: 400,
                parent: 1,
                name: "launchd_sim",
                arguments: ["/Users/tester/Library/Developer/CoreSimulator/Devices/not-a-uuid/data"]
            )
        ]
        XCTAssertTrue(ProcessMapper().map(records).unknown.map(\.pid).contains(400))
    }

    func testArgumentsReaderReadsCurrentProcess() throws {
        let arguments = try LibProcProcessSampler().readArguments(pid: getpid())
        XCTAssertFalse(arguments.isEmpty)
        XCTAssertTrue(arguments.contains { $0.contains("OpenSimDaemonTests") } || arguments.count > 1)
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimDaemonTests.ProcessMapperTests
```

Expected: FAIL vì `ProcessRecord` và `ProcessMapper` chưa tồn tại.

- [ ] **Step 3: Viết record và mapper**

Create `Sources/OpenSimDaemon/Metrics/ProcessRecord.swift`:

```swift
import Foundation
import OpenSimCore

public struct ProcessRecord: Sendable, Equatable {
    public var pid: Int32
    public var parentPID: Int32
    public var name: String
    public var executablePath: String
    public var userTimeNanoseconds: UInt64
    public var systemTimeNanoseconds: UInt64
    public var memoryFootprintBytes: UInt64
    public var diskReadBytes: UInt64
    public var diskWriteBytes: UInt64
    public var arguments: [String]
    public var environmentUDID: String?

    public init(
        pid: Int32,
        parentPID: Int32,
        name: String,
        executablePath: String,
        userTimeNanoseconds: UInt64,
        systemTimeNanoseconds: UInt64,
        memoryFootprintBytes: UInt64,
        diskReadBytes: UInt64,
        diskWriteBytes: UInt64,
        arguments: [String],
        environmentUDID: String?
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.executablePath = executablePath
        self.userTimeNanoseconds = userTimeNanoseconds
        self.systemTimeNanoseconds = systemTimeNanoseconds
        self.memoryFootprintBytes = memoryFootprintBytes
        self.diskReadBytes = diskReadBytes
        self.diskWriteBytes = diskWriteBytes
        self.arguments = arguments
        self.environmentUDID = environmentUDID
    }

    public var totalCPUNanoseconds: UInt64 {
        userTimeNanoseconds + systemTimeNanoseconds
    }
}

public protocol ProcessSampling: Sendable {
    func snapshot() async throws -> [ProcessRecord]
}

public struct ProcessMapping: Sendable {
    public var groups: [DeviceID: [ProcessRecord]]
    public var unknown: [ProcessRecord]

    public init(groups: [DeviceID: [ProcessRecord]], unknown: [ProcessRecord]) {
        self.groups = groups
        self.unknown = unknown
    }
}
```

Create `Sources/OpenSimDaemon/Metrics/ProcessMapper.swift`:

```swift
import Foundation
import OpenSimCore

public struct ProcessMapper: Sendable {
    public init() {}

    public func map(_ records: [ProcessRecord]) -> ProcessMapping {
        var deviceByPID: [Int32: DeviceID] = [:]
        var launchdPIDs: Set<Int32> = []

        for record in records {
            if record.name == "launchd_sim" {
                launchdPIDs.insert(record.pid)
                if let udid = Self.deviceUDID(arguments: record.arguments, path: record.executablePath) {
                    deviceByPID[record.pid] = DeviceID(rawValue: udid)
                }
            } else if let udid = record.environmentUDID, Self.isUUID(udid) {
                deviceByPID[record.pid] = DeviceID(rawValue: udid)
            }
        }

        var changed = true
        while changed {
            changed = false
            for record in records where deviceByPID[record.pid] == nil {
                if let parentDevice = deviceByPID[record.parentPID] {
                    deviceByPID[record.pid] = parentDevice
                    changed = true
                }
            }
        }

        var groups: [DeviceID: [ProcessRecord]] = [:]
        var unknown: [ProcessRecord] = []
        for record in records {
            if let deviceID = deviceByPID[record.pid] {
                groups[deviceID, default: []].append(record)
            } else if launchdPIDs.contains(record.pid)
                || record.executablePath.contains("/CoreSimulator/Devices/") {
                unknown.append(record)
            }
        }
        for key in groups.keys {
            groups[key]?.sort { $0.pid < $1.pid }
        }
        unknown.sort { $0.pid < $1.pid }
        return ProcessMapping(groups: groups, unknown: unknown)
    }

    public static func deviceUDID(arguments: [String], path: String) -> String? {
        for value in arguments + [path] {
            let components = value.split(separator: "/").map(String.init)
            if let index = components.firstIndex(of: "Devices"),
               index + 1 < components.count,
               isUUID(components[index + 1]) {
                return components[index + 1]
            }
        }
        return nil
    }

    public static func isUUID(_ value: String) -> Bool {
        let pattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
```

- [ ] **Step 4: Viết libproc sampler**

Create `Sources/OpenSimDaemon/Metrics/LibProcProcessSampler.swift`:

```swift
import Darwin
import Foundation
import OpenSimCore

public struct LibProcProcessSampler: ProcessSampling {
    public init() {}

    public func snapshot() async throws -> [ProcessRecord] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else {
            throw OpenSimError(
                code: "internal",
                message: "proc_listallpids returned no capacity",
                details: [:],
                recovery: nil,
                retryable: true
            )
        }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 32)
        let filled = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard filled > 0 else {
            throw OpenSimError(
                code: "internal",
                message: "proc_listallpids returned no processes",
                details: [:],
                recovery: nil,
                retryable: true
            )
        }
        var records: [ProcessRecord] = []
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            if let record = record(for: pid) {
                records.append(record)
            }
        }
        return records
    }

    public func readArguments(pid: pid_t) throws -> [String] {
        try readArgumentsAndEnvironment(pid: pid).arguments
    }

    public func readEnvironment(pid: pid_t) throws -> [String] {
        try readArgumentsAndEnvironment(pid: pid).environment
    }

    private func record(for pid: pid_t) -> ProcessRecord? {
        var info = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize else {
            return nil
        }
        var usage = rusage_info_v4()
        let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        guard usageResult == 0 else {
            return nil
        }
        var nameBuffer = [CChar](repeating: 0, count: 256)
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        let name = nameLength > 0
            ? nameBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            : ""
        var pathBuffer = [CChar](repeating: 0, count: Int(PROC_PIDPATHINFO_MAXSIZE))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(PROC_PIDPATHINFO_MAXSIZE))
        let path = pathLength > 0
            ? pathBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            : ""
        var arguments: [String] = []
        if name == "launchd_sim" {
            arguments = (try? readArguments(pid: pid)) ?? []
        }
        var environmentUDID: String?
        if name != "launchd_sim", path.contains("/CoreSimulator/") {
            if let environment = try? readEnvironment(pid: pid),
               let value = environment.first(where: { $0.hasPrefix("SIMULATOR_UDID=") }) {
                environmentUDID = String(value.dropFirst("SIMULATOR_UDID=".count))
            }
        }
        return ProcessRecord(
            pid: pid,
            parentPID: Int32(bitPattern: info.pbi_ppid),
            name: name,
            executablePath: path,
            userTimeNanoseconds: Self.nanoseconds(fromMachTicks: usage.ri_user_time),
            systemTimeNanoseconds: Self.nanoseconds(fromMachTicks: usage.ri_system_time),
            memoryFootprintBytes: usage.ri_phys_footprint,
            diskReadBytes: usage.ri_diskio_bytesread,
            diskWriteBytes: usage.ri_diskio_byteswritten,
            arguments: arguments,
            environmentUDID: environmentUDID
        )
    }

    private func readArgumentsAndEnvironment(pid: pid_t) throws -> (arguments: [String], environment: [String]) {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            throw OpenSimError(
                code: "permission_denied",
                message: "Cannot read process arguments",
                details: ["pid": String(pid)],
                recovery: "Run as the same user that owns the simulator",
                retryable: false
            )
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else {
            throw OpenSimError(
                code: "permission_denied",
                message: "sysctl KERN_PROCARGS2 failed",
                details: ["pid": String(pid)],
                recovery: "Check process ownership",
                retryable: false
            )
        }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var offset = MemoryLayout<Int32>.size
        while offset < buffer.count, buffer[offset] != 0 {
            offset += 1
        }
        offset += 1
        var arguments: [String] = []
        for _ in 0 ..< Int(argc) {
            let start = offset
            while offset < buffer.count, buffer[offset] != 0 {
                offset += 1
            }
            if offset > start {
                arguments.append(String(decoding: buffer[start ..< offset], as: UTF8.self))
            }
            offset += 1
        }
        var environment: [String] = []
        while offset < buffer.count {
            let start = offset
            while offset < buffer.count, buffer[offset] != 0 {
                offset += 1
            }
            if offset > start {
                environment.append(String(decoding: buffer[start ..< offset], as: UTF8.self))
            }
            offset += 1
        }
        return (arguments, environment)
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func nanoseconds(fromMachTicks ticks: UInt64) -> UInt64 {
        ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
    }
}
```

- [ ] **Step 5: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimDaemonTests.ProcessMapperTests
```

Expected: PASS 5 test. Nếu `readArguments` trên test process trả rỗng do sandbox, test `testArgumentsReaderReadsCurrentProcess` được phép fail; ghi lại trong báo cáo task và giữ test mapping.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenSimDaemon/Metrics/ProcessRecord.swift Sources/OpenSimDaemon/Metrics/ProcessMapper.swift Sources/OpenSimDaemon/Metrics/LibProcProcessSampler.swift Tests/OpenSimDaemonTests/ProcessMapperTests.swift
git commit -m "feat(metrics): map simulator processes by argv, tree and env"
```

---

### Task 13: Metrics sampler, ring buffer, thresholds và HTTP

**Files:**
- Create: `Sources/OpenSimCore/Metrics/MetricsThresholds.swift`
- Create: `Sources/OpenSimDaemon/Metrics/MetricsRingBuffer.swift`
- Create: `Sources/OpenSimDaemon/Metrics/MetricsThresholdEvaluator.swift`
- Create: `Sources/OpenSimDaemon/Metrics/MetricsConfigurationStore.swift`
- Create: `Sources/OpenSimDaemon/Metrics/MetricsSampler.swift`
- Create: `Sources/OpenSimDaemon/Metrics/MetricsHTTP.swift`
- Test: `Tests/OpenSimCoreTests/MetricsThresholdsTests.swift`
- Test: `Tests/OpenSimDaemonTests/MetricsSamplerTests.swift`
- Test: `Tests/OpenSimDaemonTests/PerformanceHTTPTests.swift`

**Interfaces:**
- Consumes: `ProcessSampling`, `ProcessMapper`, `ProcessRecord` từ Task 12; `MetricSample`, `ProcessSample`, `DeviceID`; `AppControlling`, `DeviceControlling`.
- Produces: `MetricsThresholds`, `MetricsWarning`, `DeviceMetricsSnapshot`; `MetricsRingBuffer`; `MetricsThresholdEvaluator`; `MetricsConfigurationStore`; `MetricsSampler`; `MetricsServing`, `MetricsHTTPController` (read-only).

- [ ] **Step 1: Viết test ring và threshold thất bại**

Create `Tests/OpenSimCoreTests/MetricsThresholdsTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class MetricsThresholdsTests: XCTestCase {
    private let deviceID = DeviceID(rawValue: "11111111-2222-3333-4444-555555555555")

    private func sample(cpu: Double, memory: UInt64, seconds: TimeInterval) -> MetricSample {
        MetricSample(
            deviceID: deviceID,
            timestamp: Date(timeIntervalSince1970: 1_790_000_000 + seconds),
            cpuPercent: cpu,
            memoryBytes: memory,
            processCount: 1,
            diskReadBytes: 0,
            diskWriteBytes: 0
        )
    }

    func testCPUWarningRequiresThirtySeconds() {
        var evaluator = MetricsThresholdEvaluator()
        let thresholds = MetricsThresholds()
        var warnings: [MetricsWarning] = []
        for index in 0 ..< 29 {
            warnings = evaluator.evaluate(
                samples: [sample(cpu: 200, memory: 100, seconds: TimeInterval(index))],
                diskFreeBytes: 100_000_000_000,
                thresholds: thresholds
            )
        }
        XCTAssertTrue(warnings.isEmpty)
        warnings = evaluator.evaluate(
            samples: [sample(cpu: 200, memory: 100, seconds: 29)],
            diskFreeBytes: 100_000_000_000,
            thresholds: thresholds
        )
        XCTAssertEqual(warnings.first?.kind, .cpuSustained)
    }

    func testMemoryAndDiskWarningsUseHysteresis() {
        var evaluator = MetricsThresholdEvaluator()
        let thresholds = MetricsThresholds()
        let highMemory = UInt64(3_000_000_000)
        let lowMemory = UInt64(1_000_000_000)

        let first = evaluator.evaluate(
            samples: [sample(cpu: 10, memory: highMemory, seconds: 1)],
            diskFreeBytes: 5_000_000_000,
            thresholds: thresholds
        )
        XCTAssertEqual(Set(first.map(\.kind)), [.memoryHigh, .diskFreeLow])

        let second = evaluator.evaluate(
            samples: [sample(cpu: 10, memory: highMemory, seconds: 2)],
            diskFreeBytes: 5_000_000_000,
            thresholds: thresholds
        )
        XCTAssertTrue(second.isEmpty)

        let cleared = evaluator.evaluate(
            samples: [sample(cpu: 10, memory: lowMemory, seconds: 3)],
            diskFreeBytes: 50_000_000_000,
            thresholds: thresholds
        )
        XCTAssertTrue(cleared.isEmpty)
    }
}
```

Create `Tests/OpenSimDaemonTests/MetricsSamplerTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon

final class MetricsSamplerTests: XCTestCase {
    private actor SequenceSampler: ProcessSampling {
        var snapshots: [[ProcessRecord]]

        init(snapshots: [[ProcessRecord]]) {
            self.snapshots = snapshots
        }

        func snapshot() async throws -> [ProcessRecord] {
            snapshots.removeFirst()
        }
    }

    private struct FixedInventory: DeviceInventoryProviding {
        var ids: Set<DeviceID>
        func bootedDeviceIDs() async throws -> Set<DeviceID> { ids }
    }

    private func record(
        pid: Int32,
        cpuNanoseconds: UInt64,
        memory: UInt64,
        read: UInt64,
        write: UInt64
    ) -> ProcessRecord {
        ProcessRecord(
            pid: pid,
            parentPID: 100,
            name: "SpringBoard",
            executablePath: "/runtime/SpringBoard",
            userTimeNanoseconds: cpuNanoseconds,
            systemTimeNanoseconds: 0,
            memoryFootprintBytes: memory,
            diskReadBytes: read,
            diskWriteBytes: write,
            arguments: [],
            environmentUDID: nil
        )
    }

    func testSecondSampleComputesDeltaCPUAndDisk() async throws {
        let deviceID = DeviceID(rawValue: "11111111-2222-3333-4444-555555555555")
        let launchd = ProcessRecord(
            pid: 100,
            parentPID: 1,
            name: "launchd_sim",
            executablePath: "/usr/libexec/launchd_sim",
            userTimeNanoseconds: 0,
            systemTimeNanoseconds: 0,
            memoryFootprintBytes: 0,
            diskReadBytes: 0,
            diskWriteBytes: 0,
            arguments: [
                "/usr/libexec/launchd_sim",
                "/Users/tester/Library/Developer/CoreSimulator/Devices/\(deviceID.rawValue)/data"
            ],
            environmentUDID: nil
        )
        let sampler = SequenceSampler(snapshots: [
            [launchd, record(pid: 101, cpuNanoseconds: 1_000_000_000, memory: 1_000, read: 0, write: 0)],
            [launchd, record(pid: 101, cpuNanoseconds: 2_000_000_000, memory: 2_000, read: 4_096, write: 2_048)]
        ])
        let metrics = MetricsSampler(
            processSampler: sampler,
            inventory: FixedInventory(ids: [deviceID]),
            diskFreeProvider: { 100_000_000_000 },
            emit: { _ in }
        )

        _ = try await metrics.sampleOnce(at: Date(timeIntervalSince1970: 1_790_000_000))
        let second = try await metrics.sampleOnce(at: Date(timeIntervalSince1970: 1_790_000_001))

        let snapshot = try XCTUnwrap(second.first)
        XCTAssertEqual(snapshot.sample.cpuPercent, 100, accuracy: 0.5)
        XCTAssertEqual(snapshot.sample.memoryBytes, 2_000)
        XCTAssertEqual(snapshot.sample.processCount, 2)
        XCTAssertEqual(snapshot.sample.diskReadBytes, 4_096)
        XCTAssertEqual(snapshot.sample.diskWriteBytes, 2_048)
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimCoreTests.MetricsThresholdsTests
swift test --filter OpenSimDaemonTests.MetricsSamplerTests
```

Expected: FAIL vì các type metrics chưa tồn tại.

- [ ] **Step 3: Viết core threshold types**

Create `Sources/OpenSimCore/Metrics/MetricsThresholds.swift`:

```swift
import Foundation

public struct MetricsThresholds: Codable, Sendable, Equatable {
    public var cpuPercent: Double
    public var cpuSustainedSeconds: Int
    public var memoryBytes: UInt64
    public var diskFreeBytes: Int64

    public init(
        cpuPercent: Double = 150,
        cpuSustainedSeconds: Int = 30,
        memoryBytes: UInt64 = 2_000_000_000,
        diskFreeBytes: Int64 = 10_000_000_000
    ) {
        self.cpuPercent = cpuPercent
        self.cpuSustainedSeconds = cpuSustainedSeconds
        self.memoryBytes = memoryBytes
        self.diskFreeBytes = diskFreeBytes
    }
}

public struct MetricsWarning: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case cpuSustained
        case memoryHigh
        case diskFreeLow
    }

    public var kind: Kind
    public var deviceID: DeviceID?
    public var message: String
    public var observedValue: Double
    public var thresholdValue: Double

    public init(
        kind: Kind,
        deviceID: DeviceID?,
        message: String,
        observedValue: Double,
        thresholdValue: Double
    ) {
        self.kind = kind
        self.deviceID = deviceID
        self.message = message
        self.observedValue = observedValue
        self.thresholdValue = thresholdValue
    }
}

public struct DeviceMetricsSnapshot: Codable, Sendable {
    public var sample: MetricSample
    public var processes: [ProcessSample]
    public var warnings: [MetricsWarning]
    public var coreCount: Int

    public init(
        sample: MetricSample,
        processes: [ProcessSample],
        warnings: [MetricsWarning],
        coreCount: Int
    ) {
        self.sample = sample
        self.processes = processes
        self.warnings = warnings
        self.coreCount = coreCount
    }
}
```

- [ ] **Step 4: Viết ring, threshold evaluator, config**

Create `Sources/OpenSimDaemon/Metrics/MetricsRingBuffer.swift`:

```swift
import Foundation
import OpenSimCore

public struct MetricsRingBuffer: Sendable {
    private var samplesByDevice: [DeviceID: [MetricSample]] = [:]
    private let capacity: Int
    private let retention: TimeInterval

    public init(capacity: Int = 600, retention: TimeInterval = 600) {
        self.capacity = capacity
        self.retention = retention
    }

    public mutating func append(_ sample: MetricSample) {
        var samples = samplesByDevice[sample.deviceID, default: []]
        samples.append(sample)
        let minimum = sample.timestamp.addingTimeInterval(-retention)
        samples.removeAll { $0.timestamp < minimum }
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
        samplesByDevice[sample.deviceID] = samples
    }

    public func samples(deviceID: DeviceID?, since: Date?) -> [MetricSample] {
        let values: [MetricSample]
        if let deviceID {
            values = samplesByDevice[deviceID] ?? []
        } else {
            values = samplesByDevice.values.flatMap { $0 }.sorted { $0.timestamp < $1.timestamp }
        }
        guard let since else { return values }
        return values.filter { $0.timestamp >= since }
    }
}
```

Create `Sources/OpenSimDaemon/Metrics/MetricsThresholdEvaluator.swift`:

```swift
import Foundation
import OpenSimCore

public struct MetricsThresholdEvaluator: Sendable {
    private var cpuSeconds: [DeviceID: Int] = [:]
    private var memoryAbove: Set<DeviceID> = []
    private var diskBelow = false

    public init() {}

    public mutating func evaluate(
        samples: [MetricSample],
        diskFreeBytes: Int64,
        thresholds: MetricsThresholds
    ) -> [MetricsWarning] {
        var warnings: [MetricsWarning] = []
        for sample in samples {
            if sample.cpuPercent > thresholds.cpuPercent {
                let seconds = (cpuSeconds[sample.deviceID] ?? 0) + 1
                cpuSeconds[sample.deviceID] = seconds
                if seconds == thresholds.cpuSustainedSeconds {
                    warnings.append(
                        MetricsWarning(
                            kind: .cpuSustained,
                            deviceID: sample.deviceID,
                            message: "CPU above \(Int(thresholds.cpuPercent))% for \(thresholds.cpuSustainedSeconds) seconds",
                            observedValue: sample.cpuPercent,
                            thresholdValue: thresholds.cpuPercent
                        )
                    )
                }
            } else {
                cpuSeconds[sample.deviceID] = 0
            }
            if sample.memoryBytes > thresholds.memoryBytes {
                if !memoryAbove.contains(sample.deviceID) {
                    memoryAbove.insert(sample.deviceID)
                    warnings.append(
                        MetricsWarning(
                            kind: .memoryHigh,
                            deviceID: sample.deviceID,
                            message: "Memory above 2 GB",
                            observedValue: Double(sample.memoryBytes),
                            thresholdValue: Double(thresholds.memoryBytes)
                        )
                    )
                }
            } else {
                memoryAbove.remove(sample.deviceID)
            }
        }
        if diskFreeBytes < thresholds.diskFreeBytes {
            if !diskBelow {
                diskBelow = true
                warnings.append(
                    MetricsWarning(
                        kind: .diskFreeLow,
                        deviceID: nil,
                        message: "Disk free below 10 GB",
                        observedValue: Double(diskFreeBytes),
                        thresholdValue: Double(thresholds.diskFreeBytes)
                    )
                )
            }
        } else {
            diskBelow = false
        }
        return warnings
    }
}
```

Create `Sources/OpenSimDaemon/Metrics/MetricsConfigurationStore.swift`:

```swift
import Foundation
import OpenSimCore

public struct MetricsConfigurationFile: Codable, Sendable {
    public struct Metrics: Codable, Sendable {
        public var thresholds: MetricsThresholds
    }

    public var metrics: Metrics
}

public struct MetricsConfigurationStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> MetricsThresholds {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(MetricsConfigurationFile.self, from: data)
        else {
            return MetricsThresholds()
        }
        return decoded.metrics.thresholds
    }
}
```

- [ ] **Step 5: Viết sampler**

Create `Sources/OpenSimDaemon/Metrics/MetricsSampler.swift`:

```swift
import Foundation
import OpenSimCore

public protocol DeviceInventoryProviding: Sendable {
    func bootedDeviceIDs() async throws -> Set<DeviceID>
}

public struct BridgeDeviceInventory: DeviceInventoryProviding {
    private let devices: any DeviceControlling

    public init(devices: any DeviceControlling) {
        self.devices = devices
    }

    public func bootedDeviceIDs() async throws -> Set<DeviceID> {
        Set(try await devices.listDevices().filter { $0.state == .booted }.map(\.id))
    }
}

public actor MetricsSampler: MetricsServing {
    private let processSampler: any ProcessSampling
    private let inventory: any DeviceInventoryProviding
    private let diskFreeProvider: @Sendable () async -> Int64
    private let configuration: MetricsConfigurationStore
    private let emit: @Sendable ([DeviceMetricsSnapshot]) async -> Void
    private let mapper = ProcessMapper()
    private var ring = MetricsRingBuffer()
    private var evaluator = MetricsThresholdEvaluator()
    private var previousRecords: [Int32: ProcessRecord] = [:]
    private var previousDate: Date?
    private var latestProcesses: [DeviceID: [ProcessSample]] = [:]
    private var latestWarnings: [DeviceID: [MetricsWarning]] = [:]
    private var runTask: Task<Void, Never>?

    public init(
        processSampler: any ProcessSampling,
        inventory: any DeviceInventoryProviding,
        configuration: MetricsConfigurationStore = MetricsConfigurationStore(
            fileURL: URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/OpenSim/config.json")
        ),
        diskFreeProvider: @escaping @Sendable () async -> Int64 = {
            let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        },
        emit: @escaping @Sendable ([DeviceMetricsSnapshot]) async -> Void
    ) {
        self.processSampler = processSampler
        self.inventory = inventory
        self.configuration = configuration
        self.diskFreeProvider = diskFreeProvider
        self.emit = emit
    }

    public func start(interval: Duration = .seconds(1)) {
        guard runTask == nil else { return }
        runTask = Task {
            while !Task.isCancelled {
                _ = try? await self.sampleOnce(at: Date())
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        runTask?.cancel()
        runTask = nil
    }

    public func sampleOnce(at date: Date = Date()) async throws -> [DeviceMetricsSnapshot] {
        let records = try await processSampler.snapshot()
        let mapping = mapper.map(records)
        let booted = (try? await inventory.bootedDeviceIDs()) ?? []
        let wallNanoseconds = max(
            UInt64((date.timeIntervalSince(previousDate ?? date.addingTimeInterval(-1))) * 1_000_000_000),
            1
        )
        let thresholds = configuration.load()
        let diskFree = await diskFreeProvider()
        var snapshots: [DeviceMetricsSnapshot] = []
        var newPrevious: [Int32: ProcessRecord] = [:]
        var warningsByDevice: [DeviceID: [MetricsWarning]] = [:]

        for (deviceID, processes) in mapping.groups where booted.contains(deviceID) {
            var cpuDelta: UInt64 = 0
            var readDelta: UInt64 = 0
            var writeDelta: UInt64 = 0
            var memory: UInt64 = 0
            var cpuByPID: [Int32: Double] = [:]
            for record in processes {
                memory += record.memoryFootprintBytes
                if let previous = previousRecords[record.pid] {
                    let cpu = record.totalCPUNanoseconds > previous.totalCPUNanoseconds
                        ? record.totalCPUNanoseconds - previous.totalCPUNanoseconds
                        : 0
                    let read = record.diskReadBytes > previous.diskReadBytes
                        ? record.diskReadBytes - previous.diskReadBytes
                        : 0
                    let write = record.diskWriteBytes > previous.diskWriteBytes
                        ? record.diskWriteBytes - previous.diskWriteBytes
                        : 0
                    cpuDelta += cpu
                    readDelta += read
                    writeDelta += write
                    cpuByPID[record.pid] = Double(cpu) / Double(wallNanoseconds) * 100
                }
                newPrevious[record.pid] = record
            }
            let cpuPercent = Double(cpuDelta) / Double(wallNanoseconds) * 100
            let sample = MetricSample(
                deviceID: deviceID,
                timestamp: date,
                cpuPercent: cpuPercent,
                memoryBytes: memory,
                processCount: processes.count,
                diskReadBytes: readDelta,
                diskWriteBytes: writeDelta
            )
            let samples = [sample]
            let warnings = evaluator.evaluate(samples: samples, diskFreeBytes: diskFree, thresholds: thresholds)
            let processSamples = processes.map {
                ProcessSample(
                    pid: $0.pid,
                    parentPID: $0.parentPID,
                    name: $0.name,
                    cpuPercent: cpuByPID[$0.pid] ?? 0,
                    memoryBytes: $0.memoryFootprintBytes
                )
            }
            ring.append(sample)
            latestProcesses[deviceID] = processSamples
            latestWarnings[deviceID] = warnings
            warningsByDevice[deviceID] = warnings
            snapshots.append(
                DeviceMetricsSnapshot(
                    sample: sample,
                    processes: processSamples,
                    warnings: warnings,
                    coreCount: ProcessInfo.processInfo.activeProcessorCount
                )
            )
        }

        if !booted.isEmpty {
            let globalWarnings = evaluator.evaluate(samples: [], diskFreeBytes: diskFree, thresholds: thresholds)
            if let diskWarning = globalWarnings.first(where: { $0.kind == .diskFreeLow }) {
                for index in snapshots.indices {
                    snapshots[index].warnings.append(diskWarning)
                }
                for deviceID in snapshots.map(\.sample.deviceID) {
                    latestWarnings[deviceID, default: []].append(diskWarning)
                }
            }
        }

        previousRecords = newPrevious
        previousDate = date
        await emit(snapshots)
        return snapshots
    }

    public func snapshots(since: Date?) -> [DeviceMetricsSnapshot] {
        let samples = ring.samples(deviceID: nil, since: since)
        return samples.map { sample in
            DeviceMetricsSnapshot(
                sample: sample,
                processes: latestProcesses[sample.deviceID] ?? [],
                warnings: latestWarnings[sample.deviceID] ?? [],
                coreCount: ProcessInfo.processInfo.activeProcessorCount
            )
        }
    }

    public func processes(deviceID: DeviceID) -> [ProcessSample] {
        latestProcesses[deviceID] ?? []
    }
}
```

`MetricsServing` chưa định nghĩa; thêm trong `MetricsHTTP.swift` nhưng compiler thấy trong module; file order không quan trọng. Test `MetricsSampler` init labels khớp.

- [ ] **Step 6: Viết HTTP controller**

Create `Sources/OpenSimDaemon/Metrics/MetricsHTTP.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

public protocol MetricsServing: Sendable {
    func snapshots(since: Date?) async -> [DeviceMetricsSnapshot]
    func processes(deviceID: DeviceID) async -> [ProcessSample]
}

extension MetricsSampler: MetricsServing {}

public struct PerfHTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var body: Data

    public init(method: String, path: String, query: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }
}

public struct PerfHTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public struct MetricsHTTPController: Sendable {
    private let metrics: any MetricsServing
    private let encoder: JSONEncoder

    public init(metrics: any MetricsServing) {
        self.metrics = metrics
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func handle(_ request: PerfHTTPRequest) async -> PerfHTTPResponse? {
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[0] == "v1", parts[1] == "perf" else {
            return nil
        }
        do {
            if request.method == "GET", parts == ["v1", "perf", "devices"] {
                let since = request.query["since"].flatMap { ISO8601DateFormatter().date(from: $0) }
                let snapshots = await metrics.snapshots(since: since)
                return try reply(snapshots, status: 200)
            }
            if request.method == "GET", parts.count == 5, parts[2] == "devices", parts[4] == "processes" {
                let samples = await metrics.processes(deviceID: DeviceID(rawValue: parts[3]))
                return try reply(samples, status: 200)
            }
            return nil
        } catch let error as OpenSimError {
            return errorReply(error)
        } catch {
            return errorReply(
                OpenSimError(
                    code: "internal",
                    message: error.localizedDescription,
                    details: [:],
                    recovery: nil,
                    retryable: false
                )
            )
        }
    }

    private func reply<T: Codable & Sendable>(_ data: T, status: Int) throws -> PerfHTTPResponse {
        let envelope = Envelope(
            schemaVersion: 1,
            ok: true,
            data: data,
            error: nil,
            meta: ResponseMeta(requestId: UUID().uuidString, durationMs: 0)
        )
        return PerfHTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: try encoder.encode(envelope)
        )
    }

    private func errorReply(_ error: OpenSimError) -> PerfHTTPResponse {
        let envelope = Envelope<EmptyPayload>(
            schemaVersion: 1,
            ok: false,
            data: nil,
            error: error,
            meta: ResponseMeta(requestId: UUID().uuidString, durationMs: 0)
        )
        return PerfHTTPResponse(
            status: error.code == "invalid_argument" ? 400 : 500,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: (try? encoder.encode(envelope)) ?? Data()
        )
    }
}

public struct MetricsHTTPAdapter: Sendable {
    private let controller: MetricsHTTPController

    public init(controller: MetricsHTTPController) {
        self.controller = controller
    }

    public func handle(method: String, path: String, query: [String: String], body: Data) async -> PerfHTTPResponse? {
        await controller.handle(PerfHTTPRequest(method: method, path: path, query: query, body: body))
    }
}
```

`Envelope<EmptyPayload>` with `data: nil` compiles.

- [ ] **Step 7: Viết test HTTP perf**

Create `Tests/OpenSimDaemonTests/PerformanceHTTPTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol

final class PerformanceHTTPTests: XCTestCase {
    private struct FakeMetrics: MetricsServing {
        var snapshotsValue: [DeviceMetricsSnapshot]
        func snapshots(since: Date?) async -> [DeviceMetricsSnapshot] { snapshotsValue }
        func processes(deviceID: DeviceID) async -> [ProcessSample] { [] }
    }

    func testActionRoutesAreNotExposed() async {
        let controller = MetricsHTTPController(metrics: FakeMetrics(snapshotsValue: []))
        let request = PerfHTTPRequest(
            method: "POST",
            path: "/v1/perf/devices/11111111-2222-3333-4444-555555555555/actions",
            query: [:],
            body: Data()
        )
        XCTAssertNil(await controller.handle(request))
    }

    func testUnknownPerfRouteReturnsNil() async {
        let controller = MetricsHTTPController(metrics: FakeMetrics(snapshotsValue: []))
        let response = await controller.handle(
            PerfHTTPRequest(method: "GET", path: "/v1/storage/scans", query: [:], body: Data())
        )
        XCTAssertNil(response)
    }
}
```

- [ ] **Step 8: Chạy test để thấy pass**

Run:

```bash
swift test --filter OpenSimCoreTests.MetricsThresholdsTests
swift test --filter OpenSimDaemonTests.MetricsSamplerTests
swift test --filter OpenSimDaemonTests.PerformanceHTTPTests
```

Expected: PASS 5 test.

- [ ] **Step 9: Commit**

```bash
git add Sources/OpenSimCore/Metrics/MetricsThresholds.swift Sources/OpenSimDaemon/Metrics/MetricsRingBuffer.swift Sources/OpenSimDaemon/Metrics/MetricsThresholdEvaluator.swift Sources/OpenSimDaemon/Metrics/MetricsConfigurationStore.swift Sources/OpenSimDaemon/Metrics/MetricsSampler.swift Sources/OpenSimDaemon/Metrics/MetricsHTTP.swift Tests/OpenSimCoreTests/MetricsThresholdsTests.swift Tests/OpenSimDaemonTests/MetricsSamplerTests.swift Tests/OpenSimDaemonTests/PerformanceHTTPTests.swift
git commit -m "feat(metrics): add sampler, ring buffer, thresholds and perf HTTP"
```

### Task 14: CLI perf và MCP perf tools qua catalog

**Files:**
- Create: `Sources/OpenSimCLI/Output/PerformanceTable.swift`
- Create: `Sources/OpenSimCLI/Commands/PerformanceCommand.swift`
- Create: `Sources/OpenSimDaemon/Metrics/MetricsOperationHandler.swift`
- Create: `Tests/OpenSimCLITests/Goldens/perf-top.json`
- Test: `Tests/OpenSimCLITests/PerformanceCommandTests.swift`
- Test: `Tests/OpenSimMCPTests/PerformanceToolsTests.swift`

**Interfaces:**
- Consumes: `OperationCatalog.openSim()`, `ToolCatalogAdapter`, `OperationExecuting`; `DeviceMetricsSnapshot`, `ProcessSample`.
- Produces: `PerformanceCommandRunner`, `PerformanceTable.render(snapshots:)`; MCP perf tools do catalog sinh ra, không `PerformanceTools` riêng.

- [ ] **Step 1: Viết golden + catalog test**

```swift
func testPerfToolsComeFromCatalog() {
    let tools = ToolCatalogAdapter.tools(from: OperationCatalog.openSim())
    let names = Set(tools.map(\.name))
    XCTAssertTrue(names.isSuperset(of: ["perf_devices", "perf_processes"]))
}
```

- [ ] **Step 2: Implement CLI và operation handler**

- `PerformanceCommandRunner` dùng `StorageJSON`/envelope sẵn có; `perf top/watch/stats` gọi `perf_devices`/`perf_processes`.
- `MetricsOperationHandler` map operation catalog sang `MetricsSampler`; route qua `OperationDispatcher`.
- Không tạo `PerformanceTools.specs`; `ToolCatalogAdapter` đọc metadata `perf_*`.
- Test `tools/list` qua MCP thật và CLI golden; `perf_devices` không trả mock data.

- [ ] **Step 3: Chạy test + commit**

```bash
swift test --filter OpenSimCLITests.PerformanceCommandTests
swift test --filter OpenSimMCPTests.PerformanceToolsTests
git add Sources/OpenSimCLI/Output/PerformanceTable.swift Sources/OpenSimCLI/Commands/PerformanceCommand.swift Sources/OpenSimDaemon/Metrics/MetricsOperationHandler.swift Tests/OpenSimCLITests/Goldens/perf-top.json Tests/OpenSimCLITests/PerformanceCommandTests.swift Tests/OpenSimMCPTests/PerformanceToolsTests.swift
git commit -m "feat(perf): expose perf command and catalog-backed mcp tools"
```
---

### Task 15: App Storage tab

**Files:**
- Create: `App/Sources/OpenSimApp/Storage/StorageTabModel.swift`
- Create: `App/Sources/OpenSimApp/Storage/StorageTabView.swift`
- Create: `App/Sources/OpenSimApp/Storage/StorageItemTable.swift`
- Create: `App/Sources/OpenSimApp/Storage/StorageCleanSheet.swift`
- Modify: `App/Sources/OpenSimApp/App/AppShell.swift` (Plan 4)
- Modify: `App/Sources/OpenSimApp/App/DaemonClient.swift` (Plan 4)
- Test: `Tests/OpenSimAppUITests/StorageTabUITests.swift`

**Interfaces:**
- Consumes: `StorageScanStatus`, `StorageScan`, `StorageItemDetail`, `CleanPlanDetail`, `CleanApplyResult`; app daemon client của Plan 4.
- Produces: `StorageAPIClient` protocol, `StorageTabModel`, `StorageTabView`, `StorageItemTable`, `StorageCleanSheet`.

- [ ] **Step 1: Viết UI test thất bại**

Create `Tests/OpenSimAppUITests/StorageTabUITests.swift`:

```swift
import XCTest

final class StorageTabUITests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-ui-storage-\(UUID().uuidString)", isDirectory: true)
        let archives = fixtureRoot.appendingPathComponent("Archives/2026-10-20/MyApp.xcarchive", isDirectory: true)
        try FileManager.default.createDirectory(at: archives, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 3_145_728)
            .write(to: archives.appendingPathComponent("payload.bin"))
        let emptyRoots = [
            "Devices", "Caches", "Logs", "DerivedData", "Archives"
        ].map { fixtureRoot.appendingPathComponent($0, isDirectory: true) }
        for root in emptyRoots {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        let roots = [
            "simulatorDevice": fixtureRoot.appendingPathComponent("Devices").path,
            "simulatorCache": fixtureRoot.appendingPathComponent("Caches").path,
            "simulatorLog": fixtureRoot.appendingPathComponent("Logs").path,
            "derivedData": fixtureRoot.appendingPathComponent("DerivedData").path,
            "archive": fixtureRoot.appendingPathComponent("Archives").path
        ]
        let data = try JSONSerialization.data(withJSONObject: roots)
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["OPENSIM_TESTING"] = "1"
        app.launchEnvironment["OPENSIM_STORAGE_ROOTS"] = String(decoding: data, as: UTF8.self)
        app.launch()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
    }

    func testStorageTabShowsRealScanAndCleanSheet() throws {
        let app = XCUIApplication()
        app.cells["sidebar-storage"].click()
        let scanButton = app.buttons["storage-scan-button"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 10))
        scanButton.click()

        let total = app.otherElements["storage-summary"]
        XCTAssertTrue(total.waitForExistence(timeout: 20))
        XCTAssertTrue(total.label.contains("MB") || total.label.contains("GB"))

        let row = app.staticTexts["storage-row-archive"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        let cleanButton = app.buttons["storage-clean-button"]
        XCTAssertTrue(cleanButton.isEnabled)
        cleanButton.click()

        let sheet = app.sheets["storage-clean-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.staticTexts["storage-plan-token"].exists)
        XCTAssertTrue(sheet.buttons["storage-apply-button"].exists)
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
xcodegen generate --spec App/project.yml
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -only-testing:OpenSimAppUITests/StorageTabUITests
```

Expected: FAIL vì tab Storage còn placeholder hoặc thiếu accessibility identifier.

- [ ] **Step 3: Viết model**

Create `App/Sources/OpenSimApp/Storage/StorageTabModel.swift`:

```swift
import Foundation
import Observation
import OpenSimCore
import OpenSimProtocol

public protocol StorageAPIClient: Sendable {
    func startStorageScan(refresh: Bool) async throws -> StorageScanStatus
    func storageStatus(id: String) async throws -> StorageScanStatus
    func storageItems(scanID: String, parentID: String?) async throws -> [StorageItem]
    func cleanPlan(scanID: String, itemIDs: [String]) async throws -> CleanPlanDetail
    func cleanApply(token: String, itemIDs: [String], phrase: String?) async throws -> CleanApplyResult
}

@MainActor
@Observable
public final class StorageTabModel {
    public enum State: Equatable {
        case idle
        case scanning
        case ready
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var scan: StorageScan?
    public private(set) var selectedItemIDs: Set<String> = []
    public private(set) var plan: CleanPlanDetail?
    public var confirmationPhrase: String = ""
    public private(set) var applyError: String?
    public private(set) var isApplying = false

    private let client: any StorageAPIClient
    private var scanTask: Task<Void, Never>?

    public init(client: any StorageAPIClient) {
        self.client = client
    }

    public var selectedItems: [StorageItem] {
        guard let scan else { return [] }
        var flattened: [StorageItem] = []
        var stack = scan.items
        while let item = stack.popLast() {
            if selectedItemIDs.contains(item.id) { flattened.append(item) }
            stack.append(contentsOf: item.children)
        }
        return flattened
    }

    public var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    public var canApply: Bool {
        guard let plan else { return false }
        if plan.requiresTypedConfirmation {
            return confirmationPhrase == (plan.confirmationPhrase ?? "MULTIPLE")
        }
        return !isApplying
    }

    public func scanStorage(refresh: Bool = true) {
        guard state != .scanning else { return }
        state = .scanning
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let status = try await client.startStorageScan(refresh: refresh)
                var current = status
                while current.state == .running {
                    try await Task.sleep(for: .milliseconds(400))
                    current = try await client.storageStatus(id: status.scanID)
                }
                if let value = current.scan {
                    scan = value
                    state = .ready
                } else if let error = current.error {
                    state = .failed(error.message)
                } else {
                    state = .failed("Scan finished without a result")
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    public func toggleSelection(_ item: StorageItem) {
        guard item.safeToDelete else { return }
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
        plan = nil
    }

    public func preparePlan() async {
        guard let scan, !selectedItemIDs.isEmpty else { return }
        applyError = nil
        do {
            plan = try await client.cleanPlan(scanID: scan.id, itemIDs: Array(selectedItemIDs))
            confirmationPhrase = ""
        } catch {
            applyError = error.localizedDescription
        }
    }

    public func applyPlan() async {
        guard let plan else { return }
        isApplying = true
        applyError = nil
        defer { isApplying = false }
        do {
            _ = try await client.cleanApply(
                token: plan.plan.token,
                itemIDs: plan.plan.itemIDs,
                phrase: plan.requiresTypedConfirmation ? confirmationPhrase : nil
            )
            self.plan = nil
            selectedItemIDs.removeAll()
            scanStorage(refresh: true)
        } catch {
            applyError = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Viết views

Thêm method vào `StorageTabModel`:

```swift
public func setSelection(_ ids: Set<String>) {
    selectedItemIDs = ids
    plan = nil
}
```

Create `App/Sources/OpenSimApp/Storage/StorageItemTable.swift`:

```swift
import SwiftUI
import OpenSimCore

public struct StorageItemTable: View {
    @Bindable private var model: StorageTabModel
    private let rows: [StorageItem]

    public init(model: StorageTabModel, rows: [StorageItem]) {
        self.model = model
        self.rows = rows
    }

    public var body: some View {
        Table(rows, selection: Binding(
            get: { model.selectedItemIDs },
            set: { model.setSelection($0) }
        )) {
            TableColumn("Item") { item in
                Text(item.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("storage-row-\(item.id)")
            }
            TableColumn("Size") { item in
                Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                    .monospacedDigit()
            }
            .width(90)
            TableColumn("Last used") { item in
                Text(item.lastUsedAt.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) } ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(130)
            TableColumn("Safety") { item in
                Text(item.safeToDelete ? "Safe" : "In use")
                    .foregroundStyle(item.safeToDelete ? .secondary : .orange)
            }
            .width(80)
        }
        .selectionDisabled { item in !item.safeToDelete }
        .accessibilityIdentifier("storage-table")
    }
}
```

Create `App/Sources/OpenSimApp/Storage/StorageTabView.swift`:

```swift
import SwiftUI
import OpenSimCore

public struct StorageTabView: View {
    @State private var model: StorageTabModel
    @State private var category: StorageCategory?
    @State private var showsCleanSheet = false

    public init(model: StorageTabModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("Category", selection: $category) {
                    Text("All").tag(StorageCategory?.none)
                    ForEach(StorageCategory.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(StorageCategory?.some(value))
                    }
                }
                .accessibilityIdentifier("storage-filter")
                Spacer()
                Button("Scan") { model.scanStorage() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .accessibilityIdentifier("storage-scan-button")
            }
            if let scan = model.scan {
                summary(scan)
                StorageItemTable(model: model, rows: filtered(scan.items))
                    .frame(maxHeight: .infinity)
                Divider()
                HStack {
                    Text(selectionSummary)
                        .accessibilityIdentifier("storage-selection")
                    Spacer()
                    Button("Review clean plan") {
                        Task {
                            await model.preparePlan()
                            showsCleanSheet = model.plan != nil
                        }
                    }
                    .disabled(model.selectedItemIDs.isEmpty || model.state == .scanning)
                    .accessibilityIdentifier("storage-clean-button")
                }
            } else {
                ContentUnavailableView(
                    "No storage scan",
                    systemImage: "internaldrive",
                    description: Text("Scan simulator, Xcode and runtime storage.")
                )
                .accessibilityIdentifier("storage-empty")
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 520)
        .sheet(isPresented: $showsCleanSheet) {
            if let plan = model.plan {
                StorageCleanSheet(model: model, plan: plan)
            }
        }
        .task { model.scanStorage() }
        .accessibilityIdentifier("storage-tab")
    }

    private var selectionSummary: String {
        let count = model.selectedItemIDs.count
        return count == 0 ? "No items selected" : "\(count) selected"
    }

    private func filtered(_ items: [StorageItem]) -> [StorageItem] {
        guard let category else { return items }
        return items.filter { $0.category == category }
    }

    private func summary(_ scan: StorageScan) -> some View {
        HStack(spacing: 8) {
            Text(ByteCountFormatter.string(fromByteCount: scan.reclaimableBytes, countStyle: .file))
                .fontWeight(.semibold)
            Text("reclaimable")
            Text("·")
            Text(ByteCountFormatter.string(fromByteCount: scan.totalBytes, countStyle: .file))
            Text("scanned")
            if scan.approximate { Text("· approximate") }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("storage-summary")
    }
}
```

Create `App/Sources/OpenSimApp/Storage/StorageCleanSheet.swift`:

```swift
import SwiftUI
import OpenSimCore

public struct StorageCleanSheet: View {
    @Bindable private var model: StorageTabModel
    private let plan: CleanPlanDetail
    @Environment(\.dismiss) private var dismiss

    public init(model: StorageTabModel, plan: CleanPlanDetail) {
        self.model = model
        self.plan = plan
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review clean plan").font(.title3.bold())
            List(plan.plan.items, id: \.itemID) { item in
                HStack {
                    Text(item.path).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                        .monospacedDigit()
                }
            }
            .frame(minHeight: 180)
            Text("Frees \(ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file)) · plan expires in 5 minutes")
                .font(.callout)
                .foregroundStyle(.secondary)
            if plan.requiresTypedConfirmation {
                TextField("Type the confirmation phrase", text: $model.confirmationPhrase)
                    .accessibilityIdentifier("storage-confirm-phrase")
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply clean") {
                    Task { await model.applyPlan() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canApply)
                .accessibilityIdentifier("storage-apply-button")
            }
        }
        .padding(20)
        .frame(width: 520)
        .accessibilityIdentifier("storage-clean-sheet")
    }
}
```

Hiển thị kết quả từng item sau apply, giữ item fail trong selection.

- [ ] **Step 5: Nối `DaemonClient` của app**

Thêm extension vào `App/Sources/OpenSimApp/App/DaemonClient.swift` (Plan 4):

```swift
extension DaemonClient: StorageAPIClient {
    func startStorageScan(refresh: Bool) async throws -> StorageScanStatus {
        try await post(
            path: "/v1/storage/scans",
            body: StorageScanRequest(categories: nil, refresh: refresh, includeAppContainers: true),
            as: StorageScanStatus.self
        )
    }

    func storageStatus(id: String) async throws -> StorageScanStatus {
        try await get(path: "/v1/storage/scans/\(id)", as: StorageScanStatus.self)
    }

    func storageItems(scanID: String, parentID: String?) async throws -> [StorageItem] {
        var path = "/v1/storage/scans/\(scanID)/items"
        if let parentID {
            path += "?parent=\(parentID)"
        }
        return try await get(path: path, as: [StorageItem].self)
    }

    func cleanPlan(scanID: String, itemIDs: [String]) async throws -> CleanPlanDetail {
        try await post(
            path: "/v1/storage/clean-plans",
            body: CleanPlanRequest(scanID: scanID, itemIDs: itemIDs),
            as: CleanPlanDetail.self
        )
    }

    func cleanApply(token: String, itemIDs: [String], phrase: String?) async throws -> CleanApplyResult {
        try await post(
            path: "/v1/storage/clean-plans/\(token)/apply",
            body: CleanApplyRequest(itemIDs: itemIDs, confirmationPhrase: phrase),
            as: CleanApplyResult.self
        )
    }
}
```

Nếu `DaemonClient` của Plan 4 dùng tên method khác (`send`, `request`), chỉ đổi phần thân extension; protocol `StorageAPIClient` và model không đổi.

- [ ] **Step 6: Chạy UI test để thấy pass**

Run:

```bash
xcodegen generate --spec App/project.yml
opensim daemon stop --json || true
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -only-testing:OpenSimAppUITests/StorageTabUITests
```

Expected: PASS 1 test; app auto-start daemon với `OPENSIM_TESTING=1` và root fixture trong thư mục tạm, không mock và không quét home.

- [ ] **Step 7: Commit**

```bash
git add App/Sources/OpenSimApp/Storage App/Sources/OpenSimApp/App/AppShell.swift App/Sources/OpenSimApp/App/DaemonClient.swift Tests/OpenSimAppUITests/StorageTabUITests.swift
git commit -m "feat(app): add storage tab with real scan and clean sheet"
```

---

### Task 16: App Performance tab

**Files:**
- Create: `App/Sources/OpenSimApp/Performance/PerformanceTabModel.swift`
- Create: `App/Sources/OpenSimApp/Performance/PerformanceTabView.swift`
- Create: `App/Sources/OpenSimApp/Performance/PerformanceDeviceTable.swift`
- Create: `App/Sources/OpenSimApp/Performance/PerformanceHistoryView.swift`
- Create: `App/Sources/OpenSimApp/Performance/ProcessTableView.swift`
- Create: `App/Sources/OpenSimApp/Performance/PerformanceThresholdBanner.swift`
- Modify: `App/Sources/OpenSimApp/App/AppShell.swift` (Plan 4)
- Modify: `App/Sources/OpenSimApp/App/AppFeature.swift` (Plan 4, bật flag)
- Modify: `App/Sources/OpenSimApp/App/DaemonClient.swift` (Plan 4)
- Test: `Tests/OpenSimAppUITests/PerformanceTabUITests.swift`

**Interfaces:**
- Consumes: `DeviceMetricsSnapshot`, `MetricSample`, `ProcessSample`, `MetricsWarning`; `DaemonClient`.
- Produces: `PerformanceAPIClient`, `PerformanceTabModel`, `PerformanceTabView`, `PerformanceDeviceTable`, `PerformanceHistoryView`, `ProcessTableView`, `PerformanceThresholdBanner`.

- [ ] **Step 1: Viết UI test thất bại**

Create `Tests/OpenSimAppUITests/PerformanceTabUITests.swift`:

```swift
import XCTest

final class PerformanceTabUITests: XCTestCase {
    func testPerformanceTabShowsBootedDeviceMetrics() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["OPENSIM_TESTING"] = "1"
        app.launch()

        app.cells["sidebar-performance"].click()
        let table = app.otherElements["performance-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["performance-cpu"].exists)
        XCTAssertTrue(app.staticTexts["performance-memory"].exists)
        XCTAssertTrue(app.tables["performance-process-table"].exists)
        XCTAssertFalse(app.buttons["performance-terminate-app"].exists)
        XCTAssertFalse(app.buttons["performance-shutdown-device"].exists)
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
xcodegen generate --spec App/project.yml
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -only-testing:OpenSimAppUITests/PerformanceTabUITests
```

Expected: FAIL vì tab Performance còn placeholder.

- [ ] **Step 3: Viết model**

Create `App/Sources/OpenSimApp/Performance/PerformanceTabModel.swift`:

```swift
import Foundation
import Observation
import OpenSimCore
import OpenSimProtocol

public protocol PerformanceAPIClient: Sendable {
    func metricsSince(_ since: Date?) async throws -> [DeviceMetricsSnapshot]
    func processes(deviceID: DeviceID) async throws -> [ProcessSample]
    func metricsStream() -> AsyncStream<[DeviceMetricsSnapshot]>
}

@MainActor
@Observable
public final class PerformanceTabModel {
    public private(set) var snapshots: [DeviceMetricsSnapshot] = []
    public private(set) var history: [DeviceID: [MetricSample]] = [:]
    public private(set) var selectedDeviceID: DeviceID?
    public private(set) var processes: [ProcessSample] = []
    public private(set) var errorMessage: String?
    public private(set) var isConnected = false

    private let client: any PerformanceAPIClient
    private var streamTask: Task<Void, Never>?

    public init(client: any PerformanceAPIClient) {
        self.client = client
    }

    public var selectedSnapshot: DeviceMetricsSnapshot? {
        guard let selectedDeviceID else { return snapshots.first }
        return snapshots.first { $0.sample.deviceID == selectedDeviceID }
    }

    public var warnings: [MetricsWarning] {
        snapshots.flatMap(\.warnings)
    }

    public func samples(for deviceID: DeviceID) -> [MetricSample] {
        history[deviceID] ?? []
    }

    public func start() {
        guard streamTask == nil else { return }
        isConnected = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            let initial = (try? await client.metricsSince(nil)) ?? []
            appendHistory(initial)
            snapshots = merged(initial)
            if selectedDeviceID == nil {
                selectedDeviceID = snapshots.first?.sample.deviceID
            }
            for await batch in client.metricsStream() {
                if Task.isCancelled { return }
                appendHistory(batch)
                snapshots = merged(batch)
                if let deviceID = selectedDeviceID {
                    processes = (try? await client.processes(deviceID: deviceID)) ?? []
                }
            }
            isConnected = false
        }
    }

    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        isConnected = false
    }

    public func select(_ deviceID: DeviceID) {
        selectedDeviceID = deviceID
        Task {
            processes = (try? await client.processes(deviceID: deviceID)) ?? []
        }
    }

    private func appendHistory(_ batch: [DeviceMetricsSnapshot]) {
        for snapshot in batch {
            var samples = history[snapshot.sample.deviceID, default: []]
            samples.append(snapshot.sample)
            if samples.count > 600 {
                samples.removeFirst(samples.count - 600)
            }
            history[snapshot.sample.deviceID] = samples
        }
    }

    private func merged(_ batch: [DeviceMetricsSnapshot]) -> [DeviceMetricsSnapshot] {
        var byDevice = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.sample.deviceID, $0) })
        for snapshot in batch {
            byDevice[snapshot.sample.deviceID] = snapshot
        }
        return byDevice.values.sorted { $0.sample.deviceID.rawValue < $1.sample.deviceID.rawValue }
    }
}
```

- [ ] **Step 4: Viết views**

Create `App/Sources/OpenSimApp/Performance/PerformanceDeviceTable.swift`:

```swift
import SwiftUI
import OpenSimCore

public struct PerformanceDeviceTable: View {
    @Bindable private var model: PerformanceTabModel

    public init(model: PerformanceTabModel) {
        self.model = model
    }

    public var body: some View {
        Table(model.snapshots, selection: Binding(
            get: { model.selectedDeviceID },
            set: { value in if let value { model.select(value) } }
        )) {
            TableColumn("Device") { snapshot in
                Text(snapshot.sample.deviceID.rawValue)
                    .lineLimit(1)
                    .accessibilityIdentifier("performance-device-\(snapshot.sample.deviceID.rawValue)")
            }
            TableColumn("CPU") { snapshot in
                Text("\(snapshot.sample.cpuPercent, specifier: "%.1f")%")
                    .monospacedDigit()
                    .accessibilityIdentifier("performance-cpu")
            }
            .width(80)
            TableColumn("Memory") { snapshot in
                Text(ByteCountFormatter.string(fromByteCount: Int64(snapshot.sample.memoryBytes), countStyle: .memory))
                    .monospacedDigit()
                    .accessibilityIdentifier("performance-memory")
            }
            .width(100)
            TableColumn("Processes") { snapshot in
                Text("\(snapshot.sample.processCount)").monospacedDigit()
            }
            .width(90)
            TableColumn("Warning") { snapshot in
                Text(snapshot.warnings.isEmpty ? "—" : "\(snapshot.warnings.count)")
                    .foregroundStyle(snapshot.warnings.isEmpty ? .secondary : .orange)
            }
            .width(80)
        }
        .accessibilityIdentifier("performance-table")
    }
}
```

Create `App/Sources/OpenSimApp/Performance/PerformanceHistoryView.swift`:

```swift
import Charts
import SwiftUI
import OpenSimCore

public struct PerformanceHistoryView: View {
    public let samples: [MetricSample]

    public init(samples: [MetricSample]) {
        self.samples = samples
    }

    public var body: some View {
        Chart(samples) { sample in
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("CPU %", sample.cpuPercent)
            )
            .interpolationMethod(.catmullRom)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 160)
        .accessibilityIdentifier("performance-history")
    }
}
```

Create `App/Sources/OpenSimApp/Performance/PerformanceTabView.swift`:

```swift
import SwiftUI
import OpenSimCore

public struct PerformanceTabView: View {
    @State private var model: PerformanceTabModel

    public init(model: PerformanceTabModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live").foregroundStyle(model.isConnected ? .green : .orange)
                    .accessibilityIdentifier("performance-connection")
                Spacer()
            }
            PerformanceThresholdBanner(warnings: model.warnings)
            PerformanceDeviceTable(model: model)
                .frame(minHeight: 160)
            if let snapshot = model.selectedSnapshot {
                HStack(alignment: .top, spacing: 16) {
                    Gauge(value: snapshot.sample.cpuPercent, in: 0...100) {
                        Text("CPU")
                    } currentValueLabel: {
                        Text("\(snapshot.sample.cpuPercent, specifier: "%.1f")%")
                    }
                    .gaugeStyle(.accessoryCircular)
                    VStack(alignment: .leading) {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(snapshot.sample.memoryBytes), countStyle: .memory))
                            .font(.title3.bold())
                        Text("Memory").font(.caption).foregroundStyle(.secondary)
                        Text("\(snapshot.sample.processCount) processes").font(.caption)
                    }
                    PerformanceHistoryView(samples: model.samples(for: snapshot.sample.deviceID))
                }
                ProcessTableView(processes: model.processes)
                    .frame(minHeight: 160)
            } else {
                ContentUnavailableView(
                    "No booted devices",
                    systemImage: "gauge",
                    description: Text("Boot a simulator to see CPU and memory samples.")
                )
                .accessibilityIdentifier("performance-empty")
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 520)
        .task { model.start() }
        .onDisappear { model.stop() }
        .accessibilityIdentifier("performance-tab")
    }
}
```

Create `App/Sources/OpenSimApp/Performance/ProcessTableView.swift`:

```swift
import SwiftUI
import OpenSimCore

public struct ProcessTableView: View {
    public let processes: [ProcessSample]

    public init(processes: [ProcessSample]) {
        self.processes = processes
    }

    public var body: some View {
        Table(processes) {
            TableColumn("Process") { process in Text(process.name).lineLimit(1) }
            TableColumn("PID") { process in Text("\(process.pid)").monospacedDigit() }.width(70)
            TableColumn("CPU") { process in
                Text("\(process.cpuPercent, specifier: "%.1f")%").monospacedDigit()
            }.width(80)
            TableColumn("Memory") { process in
                Text(ByteCountFormatter.string(fromByteCount: Int64(process.memoryBytes), countStyle: .memory))
                    .monospacedDigit()
            }.width(100)
        }
        .accessibilityIdentifier("performance-process-table")
    }
}
```

Create `App/Sources/OpenSimApp/Performance/PerformanceThresholdBanner.swift`:

```swift
import SwiftUI
import OpenSimCore

public struct PerformanceThresholdBanner: View {
    public let warnings: [MetricsWarning]

    public init(warnings: [MetricsWarning]) {
        self.warnings = warnings
    }

    public var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning.kind.rawValue, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityIdentifier("performance-warning")
        }
    }
}
```

`PerformanceThresholdBanner` giữ native `Label` cho từng warning, không card; `ProcessTableView` dùng `Table` process, identifier `performance-process-table`. Không có terminate/shutdown trong tab này; hai action đó thuộc device inspector và daemon lease/audit.

- [ ] **Step 5: Nối client**

Thêm vào extension `DaemonClient` trong `App/Sources/OpenSimApp/App/DaemonClient.swift`:

```swift
extension DaemonClient: PerformanceAPIClient {
    func metricsSince(_ since: Date?) async throws -> [DeviceMetricsSnapshot] {
        var path = "/v1/perf/devices"
        if let since {
            path += "?since=\(ISO8601DateFormatter().string(from: since))"
        }
        return try await get(path: path, as: [DeviceMetricsSnapshot].self)
    }

    func processes(deviceID: DeviceID) async throws -> [ProcessSample] {
        try await get(path: "/v1/perf/devices/\(deviceID.rawValue)/processes", as: [ProcessSample].self)
    }

    func metricsStream() -> AsyncStream<[DeviceMetricsSnapshot]> {
        AsyncStream { continuation in
            Task {
                for await event in events(lastEventID: nil) where event.type == .metricsSample {
                    if let snapshots = try? event.data.decoded([DeviceMetricsSnapshot].self) {
                        continuation.yield(snapshots)
                    }
                }
                continuation.finish()
            }
        }
    }
}
```

`events(lastEventID:)` là API Plan 4; controller/metrics chỉ đọc, không có write action.

- [ ] **Step 5A: Bật Performance và thay shell**

Sửa `App/Sources/OpenSimApp/App/AppFeature.swift`:

```swift
public enum AppFeature {
    public static let performance = true
}
```

Sửa `AppShell` case `.performance`:

```swift
case .performance:
    PerformanceTabView(model: environment.performance)
```

`AppEnvironment` tạo `PerformanceTabModel` từ app `DaemonClient` và giữ nó như `catalog`/`runtimes`; không tạo model mới trong view. Xoá `StorageShellView`/`ServiceShellModel` sau khi `StorageTabView` thay thế; cập nhật `Tests/OpenSimAppUITests/ServiceShellUITests.swift` sang `storage-tab`, và assert `sidebar-performance` tồn tại sau khi bật flag.

```bash
xcodegen generate --spec App/project.yml
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -only-testing:OpenSimAppUITests/ServiceShellUITests
```

Expected: `storage-tab` hiện; `sidebar-performance` tồn tại; không còn `storage-shell`/`performance-shell`.

- [ ] **Step 6: Chạy UI test để thấy pass**

Run:

```bash
xcodegen generate --spec App/project.yml
xcrun simctl boot "iPhone Air" || true
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -only-testing:OpenSimAppUITests/PerformanceTabUITests
```

Expected: PASS 1 test khi có ít nhất một device booted; nếu không có device booted, test fail với "No booted devices" và người thực thi boot device rồi chạy lại.

- [ ] **Step 7: Commit**

```bash
git add App/Sources/OpenSimApp/Performance App/Sources/OpenSimApp/App/AppShell.swift App/Sources/OpenSimApp/App/AppFeature.swift App/Sources/OpenSimApp/App/AppEnvironment.swift App/Sources/OpenSimApp/App/DaemonClient.swift Tests/OpenSimAppUITests/PerformanceTabUITests.swift Tests/OpenSimAppUITests/ServiceShellUITests.swift
git commit -m "feat(app): add performance tab and enable performance flag"
```

### Task 17: Integration tests, in-use blocking và kiểm tra cuối

**Files:**
- Create: `Tests/OpenSimDaemonTests/StorageServiceTests.swift`
- Create: `Tests/IntegrationTests/StorageIntegrationTests.swift`
- Create: `Tests/IntegrationTests/MetricsIntegrationTests.swift`
- Modify: `Tests/OpenSimDaemonTests/StorageScannerTests.swift` (chỉ khi cần helper dùng chung)

**Interfaces:**
- Consumes: toàn bộ `StorageService`, `StorageScanner`, `CleanPlanStore`, `CleanExecutor`, `MetricsSampler`, `LibProcProcessSampler`, `ProcessMapper` từ các task trước.
- Produces: bằng chứng test cho scan fixture, size tolerance, plan/apply, token reuse, in-use blocking, process mapping trên device booted.

- [ ] **Step 1: Viết test in-use blocking thất bại**

Create `Tests/OpenSimDaemonTests/StorageServiceTests.swift`:

```swift
import XCTest
@testable import OpenSimDaemon
@testable import OpenSimProtocol

final class StorageServiceTests: XCTestCase {
    private actor FakeScanner: StorageScanning {
        var result: StorageScanResult
        init(result: StorageScanResult) { self.result = result }

        func scan(
            scanID: String,
            options: StorageScanOptions,
            progress: @Sendable (StorageScanProgress) -> Void
        ) async throws -> StorageScanResult {
            result
        }
    }

    private actor MutableMetadata: StorageMetadataProviding {
        var booted: Set<DeviceID>
        var failBooted = false
        init(booted: Set<DeviceID>) { self.booted = booted }
        func setBooted(_ ids: Set<DeviceID>) { booted = ids }
        func setFailBooted(_ value: Bool) { failBooted = value }
        func simulatorDevices() async throws -> [SimulatorStorageRecord] { [] }
        func runtimes() async throws -> [RuntimeStorageRecord] { [] }
        func bootedDeviceIDs() async throws -> Set<DeviceID> {
            if failBooted {
                throw OpenSimError(
                    code: "simctl_failed",
                    message: "inventory unavailable",
                    details: [:],
                    recovery: "Retry",
                    retryable: true
                )
            }
            return booted
        }
        func apps(on device: DeviceID) async throws -> [AppInfo] { [] }
        func appContainerPath(on device: DeviceID, bundleID: String, kind: ContainerKind) async throws -> String {
            "/tmp/container"
        }
    }

    private actor NoopTrash: TrashExecuting {
        func trash(path: String) async throws {}
    }

    private actor NoopSimctl: SimctlRunning {
        func run(_ arguments: [String]) async throws {}
    }

    private func fixture() throws -> (StorageScanResult, DeviceID, String) {
        let deviceID = DeviceID(rawValue: "11111111-2222-3333-4444-555555555555")
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-service-\(UUID().uuidString)/Devices/\(deviceID.rawValue)", isDirectory: true)
            .path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        }
        let item = StorageItem(
            id: "device-item",
            category: .simulatorDevice,
            path: path,
            sizeBytes: 1_048_576,
            lastUsedAt: nil,
            safeToDelete: true,
            reason: nil,
            children: []
        )
        let root = StorageItem(
            id: "device-root",
            category: .simulatorDevice,
            path: "/Users/tester/Library/Developer/CoreSimulator/Devices",
            sizeBytes: 1_048_576,
            lastUsedAt: nil,
            safeToDelete: false,
            reason: "Category root is not a clean target",
            children: [item]
        )
        let scan = StorageScan(
            id: "scan-service",
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            approximate: true,
            items: [root],
            totalBytes: 1_048_576,
            reclaimableBytes: 1_048_576
        )
        let detail = StorageItemDetail(
            item: item,
            metadata: .simulatorDevice(
                SimulatorDeviceMetadata(
                    platform: .iOS,
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                    runtimeVersion: "27.0",
                    lastBootedAt: nil,
                    appCount: 0,
                    isBooted: false,
                    topApps: []
                )
            )
        )
        return (StorageScanResult(scan: scan, detailsByID: [item.id: detail]), deviceID, path)
    }

    func testApplyBlocksItemThatBecameBootedAfterPlan() async throws {
        let (result, deviceID, _) = try fixture()
        let metadata = MutableMetadata(booted: [])
        let service = StorageService(
            scanner: FakeScanner(result: result),
            plans: CleanPlanStore(),
            executor: CleanExecutor(trash: NoopTrash(), simctl: NoopSimctl(), audit: { _ in }),
            metadata: metadata,
            fileSystem: FileManagerStorage(),
            emit: { _, _ in },
            now: { Date(timeIntervalSince1970: 1_790_000_000) },
            makeID: { "scan-service" }
        )

        await service.storeForTesting(result)
        let plan = try await service.planDetail(scanID: "scan-service", itemIDs: ["device-item"])
        XCTAssertEqual(plan.plan.itemIDs, ["device-item"])

        await metadata.setBooted([deviceID])
        do {
            _ = try await service.applyClean(
                planToken: plan.plan.token,
                itemIDs: ["device-item"],
                confirmationPhrase: nil,
                actor: "test",
                sessionID: nil,
                leaseID: nil
            )
            XCTFail("Apply must block a device that became booted")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "storage_in_use")
        }
    }

    func testPlanAndApplyFailClosedWhenInventoryFails() async throws {
        let (result, _, _) = try fixture()
        let metadata = MutableMetadata(booted: [])
        let service = StorageService(
            scanner: FakeScanner(result: result),
            plans: CleanPlanStore(),
            executor: CleanExecutor(trash: NoopTrash(), simctl: NoopSimctl(), audit: { _ in }),
            metadata: metadata,
            fileSystem: FileManagerStorage(),
            emit: { _, _ in },
            now: { Date(timeIntervalSince1970: 1_790_000_000) },
            makeID: { "scan-service" }
        )
        await service.storeForTesting(result)

        await metadata.setFailBooted(true)
        do {
            _ = try await service.planDetail(scanID: "scan-service", itemIDs: ["device-item"])
            XCTFail("Plan must fail closed when inventory fails")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "storage_scan_failed")
        }

        await metadata.setFailBooted(false)
        let plan = try await service.planDetail(scanID: "scan-service", itemIDs: ["device-item"])
        await metadata.setFailBooted(true)
        do {
            _ = try await service.applyClean(
                planToken: plan.plan.token,
                itemIDs: ["device-item"],
                confirmationPhrase: nil,
                actor: "test",
                sessionID: nil,
                leaseID: nil
            )
            XCTFail("Apply must fail closed when inventory fails")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "storage_scan_failed")
        }
    }
}
```

Thêm method test-only vào `StorageService`:

```swift
public func storeForTesting(_ result: StorageScanResult) {
    scans[result.scan.id] = result
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter OpenSimDaemonTests.StorageServiceTests
```

Expected: FAIL vì `storeForTesting` chưa có; sau khi thêm, test phải pass 1 test.

- [ ] **Step 3: Viết integration test storage**

Create `Tests/IntegrationTests/StorageIntegrationTests.swift`:

```swift
import XCTest
@testable import OpenSimCore
@testable import OpenSimDaemon

final class StorageIntegrationTests: XCTestCase {
    private struct NoopMetadata: StorageMetadataProviding {
        func simulatorDevices() async throws -> [SimulatorStorageRecord] { [] }
        func runtimes() async throws -> [RuntimeStorageRecord] { [] }
        func bootedDeviceIDs() async throws -> Set<DeviceID> { [] }
        func apps(on device: DeviceID) async throws -> [AppInfo] { [] }
        func appContainerPath(on device: DeviceID, bundleID: String, kind: ContainerKind) async throws -> String {
            "/tmp/container"
        }
    }

    private struct MoveToTestTrash: TrashExecuting {
        let directory: URL
        func trash(path: String) async throws {
            let destination = directory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(atPath: path, toPath: destination.path)
        }
    }

    private struct NoopSimctl: SimctlRunning {
        func run(_ arguments: [String]) async throws {}
    }

    func testScanPlanApplyFixtureArchive() async throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENSIM_INTEGRATION=1 to run storage integration tests")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-storage-integration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archives = root.appendingPathComponent("Archives/2026-10-20/MyApp.xcarchive", isDirectory: true)
        try FileManager.default.createDirectory(at: archives, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 2_097_152)
            .write(to: archives.appendingPathComponent("payload.bin"))
        let trashDirectory = root.appendingPathComponent("test-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)

        let resolver = StorageRootResolver(
            homeDirectory: NSHomeDirectory(),
            overrides: [.archive: root.appendingPathComponent("Archives").path]
        )
        let walker = DirectorySizeWalker(fileSystem: FileManagerStorage())
        let scanner = StorageScanner(
            resolver: resolver,
            fileSystem: FileManagerStorage(),
            metadata: NoopMetadata(),
            cache: StorageIndexCache(
                fileURL: root.appendingPathComponent("storage-index.json")
            ),
            sources: [ArchiveSource(walker: walker)]
        )
        var audits: [AuditEvent] = []
        let service = StorageService(
            scanner: scanner,
            plans: CleanPlanStore(),
            executor: CleanExecutor(
                trash: MoveToTestTrash(directory: trashDirectory),
                simctl: NoopSimctl(),
                audit: { audits.append($0) }
            ),
            metadata: NoopMetadata(),
            fileSystem: FileManagerStorage(),
            emit: { _, _ in },
            makeID: { "scan-integration" }
        )

        let scan = try await service.scanStorage(refresh: true)
        let archiveRoot = try XCTUnwrap(scan.items.first { $0.category == .archive })
        let item = try XCTUnwrap(archiveRoot.children.first)
        XCTAssertTrue(item.safeToDelete)
        XCTAssertGreaterThanOrEqual(item.sizeBytes, 2_097_152)

        let resourceValues = try archives.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        let measured = Int64(resourceValues.totalFileAllocatedSize ?? 0)
        XCTAssertEqual(Double(item.sizeBytes), Double(measured), accuracy: Double(measured) * 0.05)

        let plan = try await service.planDetail(scanID: scan.id, itemIDs: [item.id])
        XCTAssertEqual(plan.plan.reclaimableBytes, item.sizeBytes)

        let result = try await service.applyClean(
            planToken: plan.plan.token,
            itemIDs: [item.id],
            confirmationPhrase: nil,
            actor: "integration",
            sessionID: nil,
            leaseID: nil
        )
        XCTAssertTrue(result.results[0].success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.path))
        XCTAssertFalse(audits.isEmpty)

        do {
            _ = try await service.applyClean(
                planToken: plan.plan.token,
                itemIDs: [item.id],
                confirmationPhrase: nil,
                actor: "integration",
                sessionID: nil,
                leaseID: nil
            )
            XCTFail("Plan token must be one-time")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "confirmation_required")
        }
    }
}
```

- [ ] **Step 4: Viết integration test metrics**

Create `Tests/IntegrationTests/MetricsIntegrationTests.swift`:

```swift
import XCTest
@testable import OpenSimCore
@testable import OpenSimDaemon

final class MetricsIntegrationTests: XCTestCase {
    private struct BootedInventory: DeviceInventoryProviding {
        var ids: Set<DeviceID>
        func bootedDeviceIDs() async throws -> Set<DeviceID> { ids }
    }

    private struct SimctlDevice: Decodable {
        let udid: String
    }

    private struct SimctlList: Decodable {
        let devices: [String: [SimctlDevice]]
    }

    private func bootedUDIDs() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "booted", "-j"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let list = try JSONDecoder().decode(SimctlList.self, from: data)
        return list.devices.values.flatMap { $0 }.map(\.udid)
    }

    func testMapsProcessesForBootedDevice() async throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENSIM_INTEGRATION=1 to run metrics integration tests")
        }
        let udids = try bootedUDIDs()
        guard let udid = udids.first else {
            throw XCTSkip("BLOCKED: no booted simulator for metrics mapping")
        }
        let sampler = LibProcProcessSampler()
        let mapping = ProcessMapper().map(try await sampler.snapshot())
        let deviceID = DeviceID(rawValue: udid)
        XCTAssertNotNil(mapping.groups[deviceID])
        XCTAssertFalse(mapping.groups[deviceID]?.isEmpty ?? true)

        let metrics = MetricsSampler(
            processSampler: sampler,
            inventory: BootedInventory(ids: [deviceID]),
            diskFreeProvider: { 100_000_000_000 },
            emit: { _ in }
        )
        _ = try await metrics.sampleOnce(at: Date())
        let second = try await metrics.sampleOnce(at: Date().addingTimeInterval(1))
        let snapshot = try XCTUnwrap(second.first { $0.sample.deviceID == deviceID })
        XCTAssertGreaterThan(snapshot.sample.processCount, 0)
        XCTAssertNotNil(await metrics.processes(deviceID: deviceID).first)
    }
}
```

- [ ] **Step 5: Chạy integration test**

Run:

```bash
OPENSIM_INTEGRATION=1 swift test --filter IntegrationTests.StorageIntegrationTests
OPENSIM_INTEGRATION=1 swift test --filter IntegrationTests.MetricsIntegrationTests
```

Expected: storage PASS 1 test; metrics PASS 1 test khi có device booted, hoặc `SKIPPED` với `BLOCKED: no booted simulator for metrics mapping`. Không chuyển skip thành fail.

- [ ] **Step 6: Chạy toàn bộ test của Plan 5**

Run:

```bash
swift test --filter OpenSimCoreTests
swift test --filter OpenSimDaemonTests
swift test --filter OpenSimCLITests
swift test --filter OpenSimMCPTests
```

Expected: PASS toàn bộ; không có test bị disable ngoài integration gate.

- [ ] **Step 7: Commit**

```bash
git add Sources/OpenSimDaemon/Storage/StorageService.swift Tests/OpenSimDaemonTests/StorageServiceTests.swift Tests/IntegrationTests/StorageIntegrationTests.swift Tests/IntegrationTests/MetricsIntegrationTests.swift
git commit -m "test(storage): add in-use blocking and integration coverage"
```

---

## Spec coverage

| Mục spec | Nội dung | Task |
|---|---|---|
| 5.1 | `OpenSimCore` giữ storage rules, metrics aggregation; daemon giữ I/O | 1, 5, 12, 13 |
| 5.5 Storage scan | Scan nền, `scanId`, SSE progress, size/lastUsed/category/safety | 5, 6, 9 |
| 5.5 Metrics | Sample 1 giây khi Performance bật/có subscriber, SSE khi view mở, snapshot/ring 10 phút | 13, 16 |
| 6 | `StorageItem`, `MetricSample`, `AuditEvent` dùng đúng contract | 1, 9, 13 |
| 7.2 | `storage scan/list/clean/reveal`, `perf top/watch/stats` | 10, 14 |
| 7.1 | Envelope, `--json`, exit code qua Plan 1 | 10, 14 |
| 8.2 | `storage_scan`, `storage_list`, `storage_clean`, `perf_devices`, `perf_processes` | 10, 11, 14 |
| 8.3 | `storage_scan_failed`, `storage_in_use`, `confirmation_required`, `permission_denied` | 7, 8, 9 |
| 9.1 Storage tab | `Table` native, summary, footer CTA, clean sheet; không chart/card | 15 |
| 9.1 Performance tab | `Table` device, `Gauge`/`Chart` native, process table, cảnh báo; flag bật ở Plan 5 | 16 |
| 9.3 | Native components, sheet xác nhận, cảnh báo item đang dùng, không mock data | 15, 16 |
| 9.8 | Performance flag false ở Plan 4, bật ở Plan 5 | 16 |
| 10.1 | Device, cache, log, runtime, DerivedData, Archives, app container | 5, 6 |
| 10.2 | Allocated size, approximate, symlink, inaccessible, index cache, metadata | 2, 4, 5, 6 |
| 10.3 | Plan/apply, token 5 phút một lần, chặn in-use, Trash, simctl, audit, >20 GB | 7, 8, 9, 17 |
| 11 | 1 giây, CPU delta, RAM footprint, process mapping, ring 10 phút, ngưỡng, action | 12, 13, 16 |
| 12 | Không shell string, path allowlist, token file, audit | 3, 7, 8, 9 |
| 13 | Audit JSONL qua audit handler của Plan 3, OSLog category | 8, 9 |
| 14.1 | Unit cho storage rules, plan token, process mapping | 1, 7, 8, 12, 13 |
| 14.2 | Scan fixture, size tolerance, plan/apply, in-use, metrics booted, CLI golden, MCP contract | 2, 5, 6, 10, 11, 14, 17 |
| 14.3 | UI Storage/Performance với dữ liệu thật | 15, 16 |
| 17.1 mục 10 | Storage scan báo size; clean plan/apply; chặn in-use | 5, 9, 17 |
| 17.1 mục 11 | Performance (khi flag bật) hiển thị CPU/RAM; ngưỡng cảnh báo | 13, 16 |
| 17.2 | Scan 100 GB ≤ 60 giây; size lệch ≤ 5% | 2, 17 (đo thủ công) |

## Exit criteria

- `swift test` xanh cho `OpenSimCoreTests`, `OpenSimDaemonTests`, `OpenSimCLITests`, `OpenSimMCPTests`.
- Scan fixture trả đúng category, allocated size lệch ≤ 5% so với `totalFileAllocatedSize`, `approximate` true khi có clone/inaccessible.
- `storage_clean` dry run trả token TTL 300 giây; apply lần hai trả `confirmation_required`; token hết hạn bị từ chối.
- Device booted, cache khi có device booted, runtime đang dùng và runtime hệ thống bị chặn với reason tương ứng; plan và apply đều chặn.
- Inventory `bootedDeviceIDs()` throw thì scan/plan/apply trả `storage_scan_failed`; không item nào bị đánh dấu safe hoặc bị xoá (test `testPlanAndApplyFailClosedWhenInventoryFails`).
- Apply > 20 GB không có `confirmationPhrase` trả `confirmation_required`; gõ đúng `ARCHIVES`/`DERIVEDDATA`/`MULTIPLE` thì chạy.
- Xcode artifact đi qua `FileManager.trashItem`; simulator đi qua `simctl delete`; app data đi qua `simctl uninstall`; runtime đi qua `simctl runtime delete`.
- Mỗi lần plan, apply và item thất bại có `AuditEvent` với actor, target, result, durationMs.
- `GET /v1/storage/scans/{id}` và SSE `storage.scan.progress` hoạt động khi scan chạy; `GET /v1/perf/devices` trả sample 1 giây; ring giữ 600 sample/device.
- Process mapping tìm được `launchd_sim` theo argv UDID; process con map theo cây; env fallback; process không map vào `unknown`.
- Ngưỡng CPU 150% trong 30 giây, RAM 2 GB, disk free 10 GB sinh `MetricsWarning` đúng một lần cho mỗi lần vượt.
- Tab Storage dùng `Table`/`Form` native và daemon thật, không mock; UI test chạy với fixture root trong thư mục tạm.
- Performance ẩn khi `AppFeature.performance=false`; Plan 5 bật flag sau khi nối metrics; UI test không còn card/sparkline tự chế.
- CLI JSON golden cho `storage scan` và `perf top` khớp; MCP tool schema và gate destructive khớp spec 8.2.
- Đo thủ công trên máy owner: scan 100 GB cache nguội ≤ 60 giây; ghi số thật vào báo cáo Plan 5. Nếu vượt, mở issue tối ưu và không tuyên bố đạt.
- Không có thay đổi nào ngoài phạm vi spec 10 và 11; visionOS, thiết bị thật, debugger vẫn ngoài phạm vi.







