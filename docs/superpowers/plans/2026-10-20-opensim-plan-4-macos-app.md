# OpenSim Plan 4 — macOS App

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dựng `OpenSim.app` native bằng SwiftUI + AppKit: sidebar native với Devices/Runtimes/Storage/Activity, bảng device + inspector, New Simulator, Runtimes theo version/Add Runtime, nhiều cửa sổ device render trực tiếp bằng `SimulatorScreenView`, gesture parity theo `InputControlling` của Plan 2, lease/takeover, quick switch `Cmd+K`, menu bar extra, agent activity, Settings scene và capabilities/doctor. Storage có shell; Performance ẩn sau `AppFeature.performance=false` và nối ở Plan 5.

**Architecture:** `OpenSimApp` là composition root duy nhất. Device list, lifecycle, session, lease, audit và SSE đi qua daemon client của Plan 3. Render, input, screenshot, record và doctor đi trực tiếp qua `SimctlBridge` trong process. `SimulatorScreenView` của Plan 2 được dùng đúng public API; chỉ thêm extension additive. Không có model device thứ hai, không có lifecycle riêng, không có mock data.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Observation, XcodeGen, macOS 27.0+, arm64, Xcode 27.1, XCUITest, `OpenSimCore`, `OpenSimBridge`, `OpenSimBridgeUI`, `OpenSimProtocol`, `OpenSimDaemon` client.

**Spec:** `docs/superpowers/specs/2026-10-19-open-simulator-design.md`

**Plan 1:** `docs/superpowers/plans/2026-10-20-opensim-plan-1-core-bridge-cli.md`

**Plan 2:** `docs/superpowers/plans/2026-10-20-opensim-plan-2-screen-input-a11y.md`

**Plan 3:** `docs/superpowers/plans/2026-10-20-opensim-plan-3-daemon-session-mcp.md`

**Plan 5:** `docs/superpowers/plans/2026-10-20-opensim-plan-5-storage-performance.md`

## Global Constraints

- Chỉ tạo/sửa file dưới `App/`, `App/project.yml`, `Tests/OpenSimAppUITests/`. Không sửa spec, contract, Plan 1-3, Plan 5, `Package.swift`, hay module khác.
- App bundle `OpenSim.app`, bundle ID `dev.opensim.app`, scheme `OpenSim`, project `App/OpenSim.xcodeproj`. App Sandbox tắt, Hardened Runtime bật. Không thêm entitlement `disable-library-validation`; quyết định thuộc Plan 0/7 sau khi có bằng chứng.
- Swift 6 language mode, strict concurrency complete. UI state là `@MainActor`; type qua task phải `Sendable`.
- Không mock data trong app. Device, state, lease, audit, capability, doctor đều lấy từ daemon hoặc Bridge thật. UI test dùng daemon/device thật; thiếu điều kiện thì `XCTSkip` kèm lý do.
- Không tạo lifecycle path thứ hai. Boot/shutdown/erase/delete chỉ gọi operation của daemon. App không gọi `simctl` trực tiếp, không gọi `SimDevice`/CoreSimulator. Render, input, screenshot, record, doctor dùng `SimctlBridge` in-process.
- Device presentation: chỉ cửa sổ riêng qua `WindowGroup(id: "device")`; không có chế độ tab hoặc embedded device pane, không có tab top-level "Device Window". Sidebar chỉ Devices/Runtimes/Storage/Activity; Performance chỉ hiện khi `AppFeature.performance=true`.
- Dùng đúng public API `SimulatorScreenView`: `init(device:) throws`, `init(device:bridge:)`, `connect() async throws`, `disconnect()`, `screenSize`, `onScreenSizeChange`, `onError`, `rotation`, `setRotation(_:)`, `simulatorPoint(fromViewPoint:)`, `viewPoint(fromSimulatorPoint:)`. Không đổi tên hay signature. Extension additive duy nhất là `isReadyForInput`.
- App định nghĩa `DaemonClient` trong module `OpenSimApp` để Plan 5 mở rộng. Transport của Plan 3 luôn viết đủ `OpenSimDaemon.DaemonClient` để tránh nhầm tên.
- Storage không hiển thị số liệu giả. Khi daemon thiếu endpoint, hiện đúng thông điệp "not connected" kèm lý do, Retry và lối mở Doctor. Performance không có shell/tab khi flag tắt; Plan 5 bật sau khi nối metrics.
- `Cmd+V` dán text vào simulator qua `InputControlling.typeText`. Copy từ simulator sang Mac cần operation `device_pasteboard`; Plan 1 hoãn operation này nên menu Copy bị disable kèm lý do, không giả lập.
- Toolbar Rotate xoay presentation qua `setRotation`; xoay orientation thiết bị không thuộc Plan 2 và không được tuyên bố trong plan này.
- Take control mở sheet xác nhận, hiện owner, hạn lease, hậu quả; focus mặc định vào Cancel.
- Không dùng Chrome/browser automation. Không download, cài đặt, xoá file, commit trong lúc viết plan. Implementation agent commit theo task.
- Văn xuôi tiếng Việt; code, type, identifier, command tiếng Anh; không ký tự CJK; không placeholder, không ellipsis, không tham chiếu task khác bằng tên suy diễn.

## Integration Decisions

### State ownership

| Dữ liệu | Nguồn duy nhất | Ghi chú |
|---|---|---|
| Device, runtime | `GET /v1/devices`, operation `runtime_list` | Refresh khi mở app, SSE đổi state, hoặc bấm refresh |
| Boot/shutdown | operation `device_boot`, `device_shutdown` | Control lease ngắn hạn hoặc lease của cửa sổ |
| Session, lease, audit | `/v1/leases`, `session_list`, SSE | Không suy đoán owner từ UI |
| Render | `SimulatorScreenView` + `SimctlBridge` | In-process, không stream frame qua daemon |
| Input | `InputControlling` của `SimctlBridge` | Chỉ gửi khi app giữ lease `control` |
| Screenshot/record | `ScreenControlling` | Ghi qua `NSSavePanel` hoặc thư mục recordings |
| Doctor | `DoctorReporting`; fallback operation `doctor_report` | CLI doctor vẫn là đường chính thức |
| Storage | Endpoint Plan 5 | Plan 4 chỉ probe và hiện shell |
| Performance | Endpoint Plan 5 | Plan 4 ẩn sau `AppFeature.performance=false`; Plan 5 bật |

App tạo session `clientKind = "app"`, `clientName` từ Settings. Daemon restart đổi token và session; app tạo session mới, tăng `generation`, cửa sổ acquire lại lease. Không tái dùng session cũ.

### SimulatorScreenView usage

```swift
let view = try SimulatorScreenView(device: deviceID, bridge: displayBridge)
view.onScreenSizeChange = { model.screenSizeChanged($0) }
view.onError = { model.screenFailed($0) }
try await view.connect()
```

`displayBridge` là `any SimulatorScreenDisplaying`; `SimctlBridge` conform theo Plan 2. App không gọi `makeDisplaySurface`, không tạo `NSView` render riêng. Point mapping dùng `view.simulatorPoint(fromViewPoint:)`; không tự tính aspect-fit hay rotation. Extension additive duy nhất:

```swift
import OpenSimBridgeUI

public extension SimulatorScreenView {
    var isReadyForInput: Bool { screenSize.width > 0 && screenSize.height > 0 }
}
```

Nếu Plan 2 đổi API trước khi implement, dừng task và báo lệch contract; không tự vá bằng selector private.

### Gesture parity

| Gesture | Chuột | Trackpad | API Plan 2 |
|---|---|---|---|
| Tap | Click trái, không di chuyển | Tap | `tap(on:at:settle:)` |
| Long press | Giữ 0.65 giây hoặc right-click | Force click giữ | `longPress(on:at:durationMs:)` |
| Swipe | Kéo nhanh dưới 0.25 giây, xa hơn 20 point | Two-finger swipe | `swipe(on:from:to:durationMs:)` |
| Drag | Kéo giữ hơn 0.25 giây | Three-finger drag | `drag(on:from:to:durationMs:)` |
| Pinch | Option + kéo dọc | Pinch | `pinch(on:center:scale:durationMs:)` |
| Rotate | Command + kéo ngang | Rotate | `rotate(on:center:angle:durationMs:)` |
| Scroll | Wheel | Two-finger scroll | `scroll(on:deltaX:deltaY:at:)` |
| Multi-touch | Option/Command chord | Pinch, rotate, scroll | Ba API multi-touch của Plan 2 |
| Keyboard | Phím Mac | Phím Mac | `key(on:key:modifiers:)`, `typeText(on:text:)` |
| Hardware | Toolbar | Toolbar | `button(on:button:)` |

`InputControlling` không có arbitrary N-point touch. Plan 4 không bịa API; multi-touch được đại diện bằng pinch, rotate, scroll là các gesture hai ngón thật. Hạn chế này ghi trong checklist thủ công.

### Storage shell và Performance flag

- Storage shell probe endpoint thật `GET /v1/storage/scans/00000000-0000-0000-0000-000000000000`; response có envelope nghĩa là service tồn tại. HTTP 404/405 là unavailable; lỗi transport là error state có Retry.
- Không hiển thị byte hay scan giả; không tự tạo scan.
- Performance không có shell trong Plan 4: `AppFeature.performance=false`, sidebar/view không tồn tại. Plan 5 nối metrics thật rồi bật flag và thay `StorageShellView` bằng `StorageTabView`.
- `DaemonClient` vẫn là struct `Sendable`; protocol app-side của Plan 5 phải là `Sendable`, không `AnyObject`/`@MainActor` class-bound.

### App DaemonClient và điểm nối Plan 5

```swift
public struct DaemonClient: Sendable {
    public let transport: OpenSimDaemon.DaemonClient
    public let session: Session
    public func get<T: Decodable & Sendable>(path: String, as type: T.Type) async throws -> T
    public func post<Body: Encodable & Sendable, T: Decodable & Sendable>(
        path: String, body: Body, as type: T.Type
    ) async throws -> T
}
```

Plan 5 thêm `extension DaemonClient: StorageAPIClient` và `PerformanceAPIClient` trong cùng file. Không đổi tên `get`/`post`, không tạo client thứ hai.
## File Structure

| File | Trách nhiệm | Task |
|---|---|---|
| `App/project.yml` | XcodeGen app, UI test target, scheme, local package | 1 |
| `App/Sources/OpenSimApp/App/OpenSimApp.swift` | `@main`, scenes, Settings, MenuBarExtra | 1, 4, 8, 10 |
| `App/Sources/OpenSimApp/App/AppDelegate.swift` | Activation, state restoration, termination | 1 |
| `App/Sources/OpenSimApp/App/AppTab.swift` | Tab identifiers | 1 |
| `App/Sources/OpenSimApp/App/AppShell.swift` | Sidebar, detail theo tab | 1, 3, 11 |
| `App/Sources/OpenSimApp/App/AppEnvironment.swift` | Composition root | 1, 2, 3, 8, 9 |
| `App/Sources/OpenSimApp/App/AppEventBus.swift` | Fan-out `DaemonEvent` | 2 |
| `App/Sources/OpenSimApp/App/AppSettings.swift` | Preference bền vững | 2, 10 |
| `App/Sources/OpenSimApp/App/AppLog.swift` | OSLog subsystem `dev.opensim` | 1 |
| `App/Sources/OpenSimApp/App/ConnectionStatusView.swift` | Trạng thái daemon, retry | 2 |
| `App/Sources/OpenSimApp/App/DaemonBootstrap.swift` | Tìm CLI, LaunchAgent, chờ health | 2 |
| `App/Sources/OpenSimApp/App/DaemonClient.swift` | Facade client, `get`/`post`/probe | 2 |
| `App/Sources/OpenSimApp/App/DaemonConnectionModel.swift` | Session, health, SSE reconnect | 2 |
| `App/Sources/OpenSimApp/App/OpenSimCLILocator.swift` | Tìm binary `opensim` | 2 |
| `App/Sources/OpenSimApp/App/BridgeHandles.swift` | Optional Bridge services | 2 |
| `App/Sources/OpenSimApp/App/DeviceLifecycleAction.swift` | Enum boot/shutdown | 3 |
| `App/Sources/OpenSimApp/App/DeviceLifecycleService.swift` | Lease, lifecycle, release | 3 |
| `App/Sources/OpenSimApp/App/DeviceWindowManager.swift` | Mở, focus, registry cửa sổ | 3 |
| `App/Sources/OpenSimApp/App/LeaseConflict.swift` | Map `lease_conflict` | 3, 7 |
| `App/Sources/OpenSimApp/App/ServiceProbeResult.swift` | Kết quả probe service | 2 |
| `App/Sources/OpenSimApp/App/AppFeature.swift` | Feature flag `performance` | 1 |
| `App/Sources/OpenSimApp/Sidebar/DeviceCatalogModel.swift` | Device, lease, lifecycle, preview | 3 |
| `App/Sources/OpenSimApp/Sidebar/DevicePreviewStore.swift` | Ảnh cuối của device booted | 3 |
| `App/Sources/OpenSimApp/Devices/DevicesView.swift` | `Table` + inspector, New Device | 3 |
| `App/Sources/OpenSimApp/Devices/DeviceInspectorView.swift` | Preview, metadata, CTA | 3 |
| `App/Sources/OpenSimApp/Devices/NewDeviceSheet.swift` | Sheet tạo device | 3 |
| `App/Sources/OpenSimApp/Devices/NewDeviceModel.swift` | Validation và `device_create` | 3 |
| `App/Sources/OpenSimApp/Runtimes/RuntimesView.swift` | Row theo version, Add Runtime | 3A |
| `App/Sources/OpenSimApp/Runtimes/RuntimeModel.swift` | Install/download/remove/state | 3A |
| `App/Sources/OpenSimApp/Runtimes/AddRuntimeSheet.swift` | Download/From File | 3A |
| `App/Sources/OpenSimApp/Shared/EmptyStateView.swift` | Empty state | 3 |
| `App/Sources/OpenSimApp/Shared/ErrorStateView.swift` | Error + Retry | 3 |
| `App/Sources/OpenSimApp/Shared/LoadingStateView.swift` | Loading state | 1 |
| `App/Sources/OpenSimApp/Shared/Formatters.swift` | Byte, date | 3 |
| `App/Sources/OpenSimApp/Windows/DeviceWindowRoot.swift` | Nội dung cửa sổ device | 4, 7 |
| `App/Sources/OpenSimApp/Windows/DeviceWindowModel.swift` | State cửa sổ, input dispatch | 4, 5, 6 |
| `App/Sources/OpenSimApp/Windows/SimulatorScreenHost.swift` | `NSViewRepresentable` | 4 |
| `App/Sources/OpenSimApp/Windows/SimulatorScreenContainerView.swift` | Container, zoom, overlay | 4, 5 |
| `App/Sources/OpenSimApp/Windows/WindowAccessor.swift` | `NSWindow`, focus, close | 4, 7 |
| `App/Sources/OpenSimApp/Windows/SimulatorScreenView+Readiness.swift` | Extension additive | 4 |
| `App/Sources/OpenSimApp/Windows/DeviceBootRequiredView.swift` | Shutdown + Boot | 4 |
| `App/Sources/OpenSimApp/Windows/InputOverlayView.swift` | Chuột, wheel, magnify, key | 5 |
| `App/Sources/OpenSimApp/Windows/SimulatorGesture.swift` | Gesture DTO | 5 |
| `App/Sources/OpenSimApp/Windows/GestureController.swift` | Gesture thành Bridge call | 5 |
| `App/Sources/OpenSimApp/Windows/KeyboardController.swift` | Key, paste, hardware | 5, 6 |
| `App/Sources/OpenSimApp/Windows/DeviceToolbar.swift` | Toolbar device | 6 |
| `App/Sources/OpenSimApp/Windows/DeviceWindowCommands.swift` | Menu Device, shortcut | 6 |
| `App/Sources/OpenSimApp/Windows/DeviceCaptureController.swift` | Screenshot, record | 6 |
| `App/Sources/OpenSimApp/Windows/LeaseCoordinator.swift` | Acquire, heartbeat, takeover | 7 |
| `App/Sources/OpenSimApp/Windows/LeaseBanner.swift` | Banner control/conflict/revoked | 7 |
| `App/Sources/OpenSimApp/Windows/TakeControlSheet.swift` | Xác nhận takeover | 7, 12 |
| `App/Sources/OpenSimApp/QuickSwitch/QuickSwitchPanelController.swift` | `NSPanel` quick switch | 8 |
| `App/Sources/OpenSimApp/QuickSwitch/QuickSwitchPalette.swift` | Search, list, action | 8 |
| `App/Sources/OpenSimApp/QuickSwitch/QuickSwitchModel.swift` | Filter, highlight, perform | 8 |
| `App/Sources/OpenSimApp/MenuBar/MenuBarContentView.swift` | Menu bar extra | 8 |
| `App/Sources/OpenSimApp/MenuBar/MenuBarModel.swift` | Booted device, lease, action | 8 |
| `App/Sources/OpenSimApp/Activity/AgentActivityView.swift` | Table, filter, pause, inspector | 9 |
| `App/Sources/OpenSimApp/Activity/AgentActivityModel.swift` | Audit history, SSE, thumbnail | 9 |
| `App/Sources/OpenSimApp/Activity/ActivityEntry.swift` | Entry model | 9 |
| `App/Sources/OpenSimApp/Activity/ActivityTable.swift` | Table sự kiện | 9 |
| `App/Sources/OpenSimApp/Activity/ActivityInspector.swift` | Payload, session, Open Device | 9 |
| `App/Sources/OpenSimApp/Settings/SettingsView.swift` | Settings window | 10 |
| `App/Sources/OpenSimApp/Settings/GeneralSettingsView.swift` | Connection, client name | 10 |
| `App/Sources/OpenSimApp/Settings/DaemonSettingsView.swift` | Status, CLI path, restart | 10 |
| `App/Sources/OpenSimApp/Settings/InputSettingsView.swift` | Keyboard, paste, gesture | 10 |
| `App/Sources/OpenSimApp/Settings/CapabilitiesSettingsView.swift` | Doctor, capability table | 10 |
| `App/Sources/OpenSimApp/Settings/DoctorModel.swift` | Load doctor direct/fallback | 10 |
| `App/Sources/OpenSimApp/Storage/StorageShellView.swift` | Storage shell đầy đủ state | 11 |
| `App/Sources/OpenSimApp/Shared/ServiceShellModel.swift` | Probe state machine | 11 |
| `Tests/OpenSimAppUITests/Support/TestEnvironment.swift` | Launch app, CLI path | 1, 2 |
| `Tests/OpenSimAppUITests/Support/DaemonTestHarness.swift` | Session/lease thật qua HTTP | 7 |
| `Tests/OpenSimAppUITests/Support/XCUIElement+OpenSim.swift` | Wait helper | 1 |
| `Tests/OpenSimAppUITests/AppLaunchUITests.swift` | Launch, main window | 1 |
| `Tests/OpenSimAppUITests/DaemonConnectionUITests.swift` | Status, retry | 2 |
| `Tests/OpenSimAppUITests/DevicesUITests.swift` | Table, inspector, search, New Simulator | 3 |
| `Tests/OpenSimAppUITests/RuntimesUITests.swift` | Version, install, delete guard | 3A |
| `Tests/OpenSimAppUITests/DeviceWindowUITests.swift` | Window, screen, toolbar | 4, 6 |
| `Tests/OpenSimAppUITests/LeaseTakeoverUITests.swift` | Banner, takeover | 7 |
| `Tests/OpenSimAppUITests/QuickSwitchUITests.swift` | `Cmd+K` | 8 |
| `Tests/OpenSimAppUITests/SettingsUITests.swift` | Settings tabs, doctor | 10 |
| `Tests/OpenSimAppUITests/ServiceShellUITests.swift` | Storage shell; Performance ẩn | 11 |
| `Tests/OpenSimAppUITests/ActivityUITests.swift` | Agent activity feed, pause | 9 |
| `Tests/OpenSimAppUITests/AccessibilityUITests.swift` | Label, focus, Cancel | 12 |
## Build and Test Commands

```bash
swift build
xcodegen generate --spec App/project.yml --project App
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/AppLaunchUITests
```

- `xcodegen` là dependency môi trường dev; thiếu thì dừng và báo, không tự cài. `swift build` phải tạo `.build/debug/opensim` trước UI test; test truyền `OPENSIM_CLI_PATH`.
- UI test cần quyền Automation/Accessibility cho Xcode lần đầu; CI tự host xử lý theo Plan 7. Chạy tuần tự vì dùng chung daemon và lease.
## Tasks

### Task 1: XcodeGen project, app shell và launch UI test

**Files:**
- Create: `App/project.yml`
- Create: `App/Sources/OpenSimApp/App/OpenSimApp.swift`, `App/Sources/OpenSimApp/App/AppDelegate.swift`, `App/Sources/OpenSimApp/App/AppFeature.swift`, `App/Sources/OpenSimApp/App/AppTab.swift`, `App/Sources/OpenSimApp/App/AppShell.swift`, `App/Sources/OpenSimApp/App/AppEnvironment.swift`, `App/Sources/OpenSimApp/App/AppLog.swift`
- Create: `App/Sources/OpenSimApp/Shared/LoadingStateView.swift`
- Create: `Tests/OpenSimAppUITests/Support/TestEnvironment.swift`, `Tests/OpenSimAppUITests/Support/XCUIElement+OpenSim.swift`
- Test: `Tests/OpenSimAppUITests/AppLaunchUITests.swift`

**Interfaces:**
- Consumes: products `OpenSimCore`, `OpenSimBridge`, `OpenSimBridgeUI`, `OpenSimProtocol`, `OpenSimDaemon`.
- Produces: project/scheme; `AppTab`; `AppShell`; `AppEnvironment.shared`; `TestEnvironment.launchApp()`.

- [ ] **Step 1: Viết UI test thất bại**

`Tests/OpenSimAppUITests/Support/TestEnvironment.swift`:

```swift
import XCTest

enum TestEnvironment {
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var cliPath: String {
        repositoryRoot.appendingPathComponent(".build/debug/opensim").path
    }

    static func launchApp(extraEnvironment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OPENSIM_TESTING"] = "1"
        app.launchEnvironment["OPENSIM_CLI_PATH"] = cliPath
        app.launchEnvironment["OPENSIM_DAEMON_AUTOSTART"] = "1"
        for (key, value) in extraEnvironment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        return app
    }
}
```

`Tests/OpenSimAppUITests/Support/XCUIElement+OpenSim.swift`:

```swift
import XCTest

extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
```

`Tests/OpenSimAppUITests/AppLaunchUITests.swift`:

```swift
import XCTest

final class AppLaunchUITests: XCTestCase {
    func testAppLaunchesWithMainWindow() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        XCTAssertTrue(app.windows["OpenSim"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.cells["sidebar-devices"].exists)
        XCTAssertTrue(app.otherElements["main-sidebar"].exists)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodegen generate --spec App/project.yml --project App
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/AppLaunchUITests
```

Expected: FAIL vì `App/project.yml` chưa tồn tại, sau đó vì target chưa có.

- [ ] **Step 3: Viết project và shell**

`App/project.yml`:

```yaml
name: OpenSim
options:
  bundleIdPrefix: dev.opensim
  deploymentTarget:
    macOS: "27.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    MACOSX_DEPLOYMENT_TARGET: "27.0"
    ARCHS: arm64
    ONLY_ACTIVE_ARCH: YES
    CODE_SIGN_STYLE: Automatic
    CODE_SIGN_IDENTITY: "-"
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: YES
    ENABLE_APP_SANDBOX: NO
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
packages:
  OpenSimPackage:
    path: ..
targets:
  OpenSim:
    type: application
    platform: macOS
    sources:
      - path: Sources/OpenSimApp
        excludes:
          - Info.plist
    dependencies:
      - package: OpenSimPackage
        product: OpenSimCore
      - package: OpenSimPackage
        product: OpenSimBridge
      - package: OpenSimPackage
        product: OpenSimBridgeUI
      - package: OpenSimPackage
        product: OpenSimProtocol
      - package: OpenSimPackage
        product: OpenSimDaemon
    info:
      path: Sources/OpenSimApp/Info.plist
      properties:
        CFBundleName: OpenSim
        CFBundleDisplayName: OpenSim
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        LSMinimumSystemVersion: "27.0"
        LSApplicationCategoryType: public.app-category.developer-tools
        NSHighResolutionCapable: true
        NSPrincipalClass: NSApplication
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.opensim.app
        PRODUCT_NAME: OpenSim
  OpenSimAppUITests:
    type: bundle.ui-testing
    platform: macOS
    sources:
      - path: ../Tests/OpenSimAppUITests
    dependencies:
      - target: OpenSim
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.opensim.app.uitests
        TEST_TARGET_NAME: OpenSim
schemes:
  OpenSim:
    build:
      targets:
        OpenSim: all
        OpenSimAppUITests: [test]
    run:
      config: Debug
    test:
      config: Debug
      gatherCoverageData: false
      targets:
        - name: OpenSimAppUITests
          parallelizable: false
```

`App/Sources/OpenSimApp/App/AppTab.swift`:

```swift
import SwiftUI

public enum AppFeature {
    public static let performance = false
}

public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case devices, runtimes, storage, performance, activity
    public var id: String { rawValue }
    public static var visible: [AppTab] {
        allCases.filter { $0 != .performance || AppFeature.performance }
    }
    public var title: String {
        switch self {
        case .devices: return "Devices"
        case .runtimes: return "Runtimes"
        case .storage: return "Storage"
        case .performance: return "Performance"
        case .activity: return "Agent Activity"
        }
    }
    public var systemImage: String {
        switch self {
        case .devices: return "iphone.gen3"
        case .runtimes: return "shippingbox"
        case .storage: return "internaldrive"
        case .performance: return "speedometer"
        case .activity: return "waveform.path.ecg"
        }
    }
    public var accessibilityID: String { "sidebar-\(rawValue)" }
}
```

`App/Sources/OpenSimApp/App/OpenSimApp.swift`:

```swift
import SwiftUI

@main
struct OpenSimMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup("OpenSim", id: "main") {
            AppShell()
                .environment(environment)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
    }
}
```

`App/Sources/OpenSimApp/App/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldRestoreState(_ app: NSApplication) -> Bool {
        ProcessInfo.processInfo.environment["OPENSIM_TESTING"] != "1"
    }
    func applicationShouldSaveState(_ app: NSApplication) -> Bool {
        ProcessInfo.processInfo.environment["OPENSIM_TESTING"] != "1"
    }
}
```

`App/Sources/OpenSimApp/App/AppEnvironment.swift` (Task 2 thay bằng composition root đầy đủ):

```swift
import Foundation

@MainActor
@Observable
public final class AppEnvironment {
    public static let shared = AppEnvironment()
    public private(set) var started = false
    private init() {}
    public func start() async { started = true }
}
```

`App/Sources/OpenSimApp/App/AppLog.swift`:

```swift
import OSLog

public enum AppLog {
    public static let lifecycle = Logger(subsystem: "dev.opensim", category: "app.lifecycle")
    public static let daemon = Logger(subsystem: "dev.opensim", category: "app.daemon")
    public static let window = Logger(subsystem: "dev.opensim", category: "app.window")
    public static let input = Logger(subsystem: "dev.opensim", category: "app.input")
    public static let activity = Logger(subsystem: "dev.opensim", category: "app.activity")
}
```

`App/Sources/OpenSimApp/Shared/LoadingStateView.swift`:

```swift
import SwiftUI

public struct LoadingStateView: View {
    private let message: String
    private let identifier: String
    public init(_ message: String, identifier: String) {
        self.message = message
        self.identifier = identifier
    }
    public var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(identifier)
    }
}
```

`App/Sources/OpenSimApp/App/AppShell.swift`:

```swift
import SwiftUI

struct AppShell: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var tab: AppTab? = .devices

    var body: some View {
        NavigationSplitView {
            List(selection: $tab) {
                ForEach(AppTab.visible) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                        .accessibilityIdentifier(item.accessibilityID)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("OpenSim")
            .accessibilityIdentifier("main-sidebar")
        } detail: {
            switch tab ?? .devices {
            case .devices:
                LoadingStateView("Loading devices", identifier: "devices-loading")
            case .runtimes:
                LoadingStateView("Loading runtimes", identifier: "runtimes-loading")
            case .storage:
                LoadingStateView("Checking storage service", identifier: "storage-probing")
            case .performance:
                EmptyView()
            case .activity:
                LoadingStateView("Loading agent activity", identifier: "activity-loading")
            }
        }
        .navigationTitle("OpenSim")
        .task { await environment.start() }
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

```bash
xcodegen generate --spec App/project.yml --project App
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/AppLaunchUITests
```

Expected: `BUILD SUCCEEDED`; `AppLaunchUITests` pass 1 test.

- [ ] **Step 5: Commit**

```bash
git add App/project.yml App/Sources/OpenSimApp Tests/OpenSimAppUITests/AppLaunchUITests.swift Tests/OpenSimAppUITests/Support
git commit -m "feat(app): scaffold macOS app shell and ui test target"
```
---

### Task 2: Daemon bootstrap, app client, connection state và SSE

**Files:**
- Create: `App/Sources/OpenSimApp/App/OpenSimCLILocator.swift`, `DaemonBootstrap.swift`, `DaemonClient.swift`, `DaemonConnectionModel.swift`, `AppEventBus.swift`, `App/Sources/OpenSimApp/App/AppSettings.swift`, `BridgeHandles.swift`, `ConnectionStatusView.swift`, `ServiceProbeResult.swift`
- Modify: `App/Sources/OpenSimApp/App/AppEnvironment.swift`, `App/Sources/OpenSimApp/App/AppShell.swift`
- Test: `Tests/OpenSimAppUITests/DaemonConnectionUITests.swift`

**Interfaces:**
- Consumes: `OpenSimDaemon.DaemonClient`, `DaemonStateStore`, `LaunchAgentManager`, `DaemonState`, `HealthResponse`, `DaemonEvent`, `OperationRequest`, `Envelope`, `OpenSimJSON`, `SimctlBridge`.
- Produces: `OpenSimCLILocator.locate(override:)`; `DaemonBootstrap.connect(allowAutostart:)`, `.restart()`; `DaemonClient`; `AppSettings`; `AppEventBus`; `DaemonConnectionModel`; `BridgeHandles`.

- [ ] **Step 1: Viết UI test thất bại**

`Tests/OpenSimAppUITests/DaemonConnectionUITests.swift`:

```swift
import XCTest

final class DaemonConnectionUITests: XCTestCase {
    func testDaemonStatusSettlesWithARecoveryAction() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        let status = app.staticTexts["daemon-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let settled = NSPredicate(format: "label == %@ OR label == %@", "Connected", "Disconnected")
        expectation(for: settled, evaluatedWith: status)
        waitForExpectations(timeout: 35)
        if status.label == "Disconnected" {
            XCTAssertTrue(app.buttons["daemon-retry"].exists)
        } else {
            XCTAssertTrue(app.staticTexts["daemon-version"].exists)
        }
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/DaemonConnectionUITests
```

Expected: FAIL vì `daemon-status` chưa tồn tại.

- [ ] **Step 3: Viết bootstrap, client và connection model**

`OpenSimCLILocator.swift`: tìm theo thứ tự `Settings` override, `OPENSIM_CLI_PATH`, `Bundle.main.url(forAuxiliaryExecutable:)`, `/opt/homebrew/bin/opensim`, `/usr/local/bin/opensim`, `~/bin/opensim`; trả path nếu `isExecutableFile`.

`DaemonBootstrap.swift`: `Sendable` struct giữ `paths`, `DaemonStateStore`, `cliPathOverride: String?`; init mặc định `OpenSimPaths()` và override nil. `connect(allowAutostart:)`:

```swift
if let state = try? stateStore.read(), let client = await healthy(state) { return client }
guard allowAutostart else { throw OpenSimError.daemonUnavailable("Automatic connect is disabled") }
guard let cli = OpenSimCLILocator.locate(override: cliPathOverride) else {
    throw OpenSimError(code: .daemonUnavailable, message: "The opensim command line tool was not found",
                       recovery: "Install the CLI or set OPENSIM_CLI_PATH, then retry", retryable: true)
}
let manager = LaunchAgentManager(opensimPath: cli, paths: paths)
try manager.install()
try? manager.bootout()
do { try manager.bootstrap() } catch { try? manager.kickstart() }
for _ in 0..<50 {
    if let state = try? stateStore.read(), let client = await healthy(state) { return client }
    try await Task.sleep(for: .milliseconds(100))
}
throw OpenSimError.daemonUnavailable("Daemon did not become healthy within 5 seconds")
```

`healthy` tạo `OpenSimDaemon.DaemonClient(state:)` và trả nil nếu `health()` throw. `restart()` lấy CLI, install, `kickstart` nếu loaded hoặc `bootstrap` nếu chưa, poll 5 giây. Không chạy `opensim` bằng shell string; chỉ `LaunchAgentManager` của Plan 3.

`ServiceProbeResult.swift`:

```swift
public enum ServiceProbeResult: Sendable, Equatable {
    case available
    case unavailable
    case failed(OpenSimError)
}
```

`DaemonClient.swift` khai báo struct `Sendable` với `transport`, `session`, `http: URLSession`; các method bắt buộc:

- `devices()`, `device(_:)`, `runtimes()`, `leases()`, `operation(_:parameters:leaseID:)`, `acquireLease(device:mode:takeover:ttlSeconds:)`, `heartbeat(_:)`, `release(_:)`, `events(lastEventID:)`.
- `get<T: Decodable & Sendable>(path:as:)` và `post<Body: Encodable & Sendable, T: Decodable & Sendable>(path:body:as:)`.
- `probe(path:) -> ServiceProbeResult` gửi GET có Bearer token; 2xx là `.available`; 404/405 không có envelope là `.unavailable`; envelope error hoặc lỗi transport map tương ứng.

```swift
public func operation(
    _ name: String,
    parameters: [String: String] = [:],
    leaseID: LeaseID? = nil
) async throws -> Data {
    let request = OperationRequest(
        operation: name,
        parameters: parameters,
        sessionID: session.id,
        leaseID: leaseID,
        dryRun: nil
    )
    return try await transport.operation(request).data
}

public func get<T: Decodable & Sendable>(path: String, as type: T.Type) async throws -> T {
    let data = try await send(method: "GET", path: path, body: nil)
    let envelope = try OpenSimJSON.decoder().decode(Envelope<T>.self, from: data)
    guard envelope.ok, let value = envelope.data else {
        throw envelope.error ?? OpenSimError.daemonUnavailable("Daemon returned an empty response")
    }
    return value
}
```

`post` encode body bằng `OpenSimJSON.encoder(pretty: false)`, gọi `send(method: "POST")`, decode `Envelope<T>`. `send` set `Authorization: Bearer \(transport.token)`, decode lỗi HTTP thành `OpenSimError`, wrap lỗi transport thành `daemonUnavailable`. `probe` dùng chung `URLSession` và đọc `Envelope<EmptyBody>`.

`AppEventBus.swift`: `@MainActor final class` giữ `[UUID: (DaemonEvent) -> Void]`, method `subscribe`, `unsubscribe`, `publish`.

`App/Sources/OpenSimApp/App/AppSettings.swift`: `@MainActor @Observable final class` với `autoConnect` và `clientName`, lưu `UserDefaults`; khi `OPENSIM_TESTING=1` dùng suite `dev.opensim.app.uitests` và xoá persistent domain lúc khởi tạo; client name mặc định `OpenSim App UI Test`.

`BridgeHandles.swift`:

```swift
public struct BridgeHandles: Sendable {
    public var screen: (any ScreenControlling)?
    public var input: (any InputControlling)?
    public var display: (any SimulatorScreenDisplaying)?
    public var doctor: (any DoctorReporting)?
    public var capabilities: BridgeCapabilities?
}
```

`DaemonConnectionModel`: `@MainActor @Observable` với state `idle/connecting/connected(HealthResponse)/disconnected(OpenSimError)`, `client`, `session`, `generation`, `onEvent`, `bootstrap`, `settings`, `eventTask`, `lastEventID`.

- `connect()`: guard không phải connecting; gọi `bootstrap.connect(allowAutostart:)`, `health()`, `createSession(clientKind: "app", clientName:)`; tạo app `DaemonClient`, set state connected, tăng `generation`, start stream. Mọi lỗi thành `.disconnected`.
- `retry()`: cancel stream, gọi `connect()`.
- `restartDaemon()`: `bootstrap.restart()`, health, session mới, tăng generation, restart stream.
- `startEventStream`: vòng `for try await client.events(lastEventID:)`, lưu `lastEventID`, forward `onEvent`; khi stream kết thúc/lỗi thì set disconnected, sleep backoff 1, 2, 4, tối đa 10 giây, gọi `connect()` nếu vẫn disconnected. Không dùng polling khi stream còn sống.

`App/Sources/OpenSimApp/App/AppEnvironment.swift` thay bằng composition root:

```swift
@MainActor
@Observable
public final class AppEnvironment {
    public static let shared = AppEnvironment()
    public let settings: AppSettings
    public let bootstrap: DaemonBootstrap
    public let events: AppEventBus
    public let connection: DaemonConnectionModel
    public private(set) var bridge: BridgeHandles
    public private(set) var bridgeError: OpenSimError?

    private init() {
        let settings = AppSettings()
        let bootstrap = DaemonBootstrap()
        let events = AppEventBus()
        let connection = DaemonConnectionModel(bootstrap: bootstrap, settings: settings)
        self.settings = settings
        self.bootstrap = bootstrap
        self.events = events
        self.connection = connection
        self.bridge = BridgeHandles()
        connection.onEvent = { [weak events] event in events?.publish(event) }
    }

    public func start() async {
        if bridge.capabilities == nil { loadBridge() }
        if case .idle = connection.state { await connection.connect() }
    }

    private func loadBridge() {
        do {
            let live = try SimctlBridge.live()
            bridge = BridgeHandles(
                screen: live.screen,
                input: live.input,
                display: live,
                doctor: live,
                capabilities: live.capabilities
            )
            bridgeError = nil
        } catch let error as OpenSimError {
            bridge = BridgeHandles()
            bridgeError = error
        } catch {
            bridge = BridgeHandles()
            bridgeError = .capabilityUnavailable("bridge")
        }
    }
}
```

`ConnectionStatusView.swift`: HStack với dot, `Text(label)` identifier `daemon-status`, version identifier `daemon-version` khi connected, Button `Retry` identifier `daemon-retry` khi disconnected. Label đúng `Connected`/`Disconnected`/`Connecting`.

`AppShell` thêm `ConnectionStatusView()` và Divider phía trên detail.

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift build
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/DaemonConnectionUITests
```

Expected: PASS 1 test. Nếu thiếu `.build/debug/opensim`, chạy `swift build` trước.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/OpenSimApp/App Tests/OpenSimAppUITests/DaemonConnectionUITests.swift
git commit -m "feat(app): connect to daemon with session and sse"
```
---

### Task 3: Devices table, inspector, New Simulator và boot/shutdown

**Files:**
- Create: `App/Sources/OpenSimApp/App/DeviceLifecycleAction.swift`, `DeviceLifecycleService.swift`, `LeaseConflict.swift`, `DeviceWindowManager.swift`
- Create: `App/Sources/OpenSimApp/Sidebar/DeviceCatalogModel.swift`, `DevicePreviewStore.swift`
- Create: `App/Sources/OpenSimApp/Devices/DevicesView.swift`, `DeviceInspectorView.swift`, `NewDeviceSheet.swift`, `NewDeviceModel.swift`
- Create: `App/Sources/OpenSimApp/Shared/EmptyStateView.swift`, `ErrorStateView.swift`, `Formatters.swift`
- Modify: `App/Sources/OpenSimApp/App/AppEnvironment.swift`, `App/Sources/OpenSimApp/App/AppShell.swift`, `App/Sources/OpenSimApp/App/DaemonClient.swift`
- Test: `Tests/OpenSimAppUITests/DevicesUITests.swift` (chứa cả `DevicesUITests` và `NewDeviceUITests`)

**Interfaces:**
- Consumes: `DaemonClient`; `Device`, `Runtime`, `RuntimeID`, `Lease`, `LeaseMode`, `OpenSimError`, `ScreenControlling`, `Screenshot`; operation `device_create`.
- Produces: `DeviceLifecycleService.perform(_:on:using:takeover:)`; `DeviceCatalogModel`; `DeviceWindowManager`; `DevicesView`; `DeviceInspectorView`; `NewDeviceModel`.

- [ ] **Step 1: Viết UI test thất bại**

```swift
import XCTest

final class DevicesUITests: XCTestCase {
    func testDevicesTableSearchAndInspector() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        XCTAssertTrue(app.otherElements["devices-table"].waitForExistence(timeout: 25))
        if app.staticTexts["device-list-error"].exists {
            throw XCTSkip("Daemon unavailable: \(app.staticTexts["device-list-error"].label)")
        }
        let firstRow = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'device-row-'")).firstMatch
        if !firstRow.waitForExistence(timeout: 15) {
            XCTAssertTrue(app.otherElements["device-list-empty"].exists)
            return
        }
        firstRow.click()
        XCTAssertTrue(app.otherElements["device-inspector"].waitForExistence(timeout: 5))
        let search = app.textFields["device-search"]
        search.click()
        search.typeText("zzzz-no-such-device")
        XCTAssertTrue(app.otherElements["device-search-empty"].waitForExistence(timeout: 5))
    }
}

final class NewDeviceUITests: XCTestCase {
    func testCreateSimulatorValidationAndResult() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        app.buttons["new-device-button"].click()
        XCTAssertTrue(app.sheets["new-device-sheet"].waitForExistence(timeout: 5))
        let name = app.textFields["new-device-name"]
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("iPhone Air")
        XCTAssertTrue(app.staticTexts["new-device-name-error"].exists)
        XCTAssertFalse(app.buttons["new-device-create"].isEnabled)
        name.typeKey("a", modifierFlags: .command)
        name.typeText("iPhone Air 2")
        XCTAssertTrue(app.buttons["new-device-create"].isEnabled)
        app.buttons["new-device-create"].click()
        XCTAssertTrue(app.staticTexts["iPhone Air 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["device-inspector"].staticTexts["iPhone Air 2"].exists)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/DevicesUITests -only-testing:OpenSimAppUITests/NewDeviceUITests
```

Expected: FAIL vì `devices-table`/`new-device-button` chưa tồn tại.

- [ ] **Step 3: Viết lifecycle, catalog, table, inspector và New Simulator**

`DeviceLifecycleAction`: enum `String, Sendable, CaseIterable` với `boot = "device_boot"`, `shutdown = "device_shutdown"`, `title`.

`LeaseConflict`: `Identifiable, Equatable, Sendable`, khởi tạo từ `OpenSimError` chỉ khi code `lease_conflict`; đọc `owner`, `expiresAt` từ `details`, fallback `another session`.

`DeviceLifecycleService`:

```swift
@MainActor
public final class DeviceLifecycleService {
    private let connection: DaemonConnectionModel

    public func perform(
        _ action: DeviceLifecycleAction,
        on device: DeviceID,
        using lease: Lease?,
        takeover: Bool = false
    ) async throws -> Device {
        guard let client = connection.client else {
            throw OpenSimError.daemonUnavailable("Daemon is not connected")
        }
        if let lease {
            let data = try await client.operation(
                action.rawValue,
                parameters: ["device": device.rawValue, "wait": "true"],
                leaseID: lease.id
            )
            return try OpenSimJSON.decoder().decode(Device.self, from: data)
        }
        let temporary = try await client.acquireLease(
            device: device, mode: .control, takeover: takeover, ttlSeconds: 120
        )
        do {
            let data = try await client.operation(
                action.rawValue,
                parameters: ["device": device.rawValue, "wait": "true"],
                leaseID: temporary.id
            )
            try? await client.release(temporary)
            return try OpenSimJSON.decoder().decode(Device.self, from: data)
        } catch {
            try? await client.release(temporary)
            throw error
        }
    }
}
```

`DeviceWindowManager`: `@MainActor @Observable`, giữ `OpenWindowAction`, dictionary `[DeviceID: NSWindow]`, `openDevices: Set<DeviceID>`. `show(_:)` focus cửa sổ hiện có cùng device, nếu không gọi `openAction?(id: "device", value: device)`. `register(window:device:)` set `window.identifier = NSUserInterfaceItemIdentifier("device-<udid>")`; `unregister(device:)` xoá entry.

`DevicePreviewStore`:

```swift
@MainActor
@Observable
public final class DevicePreviewStore {
    private var images: [DeviceID: NSImage] = [:]
    private var lastCapture: [DeviceID: Date] = [:]

    public func image(for device: DeviceID) -> NSImage? { images[device] }

    public func refresh(devices: [Device], screen: (any ScreenControlling)?) async {
        guard let screen else { return }
        for device in devices where device.state == .booted {
            if let last = lastCapture[device.id], Date().timeIntervalSince(last) < 5 { continue }
            guard let shot = try? await screen.screenshot(
                on: device.id, format: .jpeg, scale: 0.25, quality: 60
            ) else { continue }
            let data = shot.data ?? shot.path.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
            if let data, let image = NSImage(data: data) {
                images[device.id] = image
                lastCapture[device.id] = Date()
            }
        }
    }
}
```

`DeviceCatalogModel`: `@MainActor @Observable`, state `idle/loading/loaded/failed`, `devices`, `runtimes`, `leases`, `pending`, `conflict`, `lastError`, `searchText`, `selectedDeviceID`, `previews`, `connection`, `lifecycle`, `didLoad`.

- `refresh()`: guard client; `async let` devices/runtimes/leases; lưu lease control; state loaded; `didLoad = true`. Lỗi map `OpenSimError`, không xoá danh sách cũ.
- `filteredDevices`: lọc `devices` theo `searchText` trên name, udid, deviceType, runtime name.
- `perform(_:on:)`: chặn trùng qua `pending`; lưu `pendingAction`; gọi lifecycle với lease nil; refresh; `lease_conflict` set `conflict`, lỗi khác set `lastError`.
- `takeControl(_:)`: gọi lifecycle với `pendingAction` đã lưu (mặc định `.boot` nếu nil) và takeover true, clear conflict, refresh.
- `apply(_:)`: `device.state.changed` cập nhật state tại chỗ; `lease.changed` upsert; `lease.revoked` xoá theo lease ID.
- `lease(for:)` trả control lease của device.

`DevicesView`: `Table(catalog.filteredDevices, selection: $catalog.selectedDeviceID)` cột Device/State/Agent; header `New Device` identifier `new-device-button`; `.searchable` identifier `device-search`; row identifier `device-row-<udid>` gắn với tên device; double-click mở cửa sổ. `.inspector` hiển thị `DeviceInspectorView` cho selection. Container `devices-table`; loading `devices-loading`; error `device-list-error` + Retry; empty `device-list-empty`; search rỗng `device-search-empty`; refresh `device-refresh`. `.task` gọi `refreshIfNeeded` rồi `previews.refresh(devices:screen:)`.

`DeviceInspectorView`: preview từ `DevicePreviewStore`, name/state, runtime/screen/last boot/agent; primary action theo state identifier `device-primary-action`; Take control khi có agent; More menu cho lifecycle. Container `device-inspector`. Không card/badge lặp trên row.

`NewDeviceModel`: `@MainActor @Observable`, fields `name`, `deviceType`, `runtime: RuntimeID?`, `runtimes`, `validation`, `isCreating`; `loadRuntimes(using:)` lọc theo platform của device type; `validate` chặn tên rỗng/trùng, runtime thiếu/sai platform; `submit(using:)` gọi `device_create` với `runtime.id.rawValue`, trả `Device`.

```swift
@MainActor
@Observable
public final class NewDeviceModel {
    public enum Validation: Equatable {
        case valid
        case missingName
        case duplicateName
        case runtimeMissing(String)
        case wrongPlatform(String)
    }
    public var name: String = ""
    public var deviceType: String = ""
    public var runtime: RuntimeID?
    public private(set) var validation: Validation = .missingName
    public func loadRuntimes(using client: DaemonClient, deviceType: String) async
    public func submit(using client: DaemonClient) async throws -> Device
}
```

`NewDeviceSheet`: `Form` native với TextField `new-device-name`, Picker device type `new-device-type`, Picker runtime `new-device-runtime`; lỗi `new-device-name-error`, note `new-device-runtime-note` (link Open Runtimes), Create `new-device-create`; sheet `new-device-sheet`. Khi mở, chọn runtime mới nhất **đã cài** cùng platform; nếu không có thì để trống và disable Create. `New Device` mở sheet; create xong đóng, refresh catalog, chọn row mới. Không auto-boot; device mới `Shutdown`.

`EmptyStateView`: `ContentUnavailableView(title, systemImage, description)`, identifier truyền vào.

`ErrorStateView`: icon, message identifier truyền vào, code, recovery, Retry identifier `<id>-retry`.

`Formatters`: ByteCountFormatter MB/GB, RelativeDateTimeFormatter.

`AppEnvironment` thêm `windows`, `lifecycle`, `catalog`, `runtimes`, `activity` theo thứ tự connection, windows, lifecycle, catalog, runtimes, activity; `connection.onEvent` publish bus và `catalog.apply(event)`. `start()` sau connect gọi `catalog.refreshIfNeeded()`. `AppShell` detail `.devices` dùng `DevicesView(catalog:)`; sidebar chỉ là `List(selection:)` native. Sheet conflict tối thiểu: owner, expiresAt, Cancel (`cancelAction`), Take Control gọi `catalog.takeControl`. Task 7 thay bằng `TakeControlSheet` đầy đủ.

- [ ] **Step 4: Chạy để thấy pass**

```bash
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/DevicesUITests -only-testing:OpenSimAppUITests/NewDeviceUITests
```

Expected: `BUILD SUCCEEDED`; table/inspector và New Simulator pass, hoặc skip có lý do nếu daemon không có device.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/OpenSimApp Tests/OpenSimAppUITests/DevicesUITests.swift
git commit -m "feat(app): add device table inspector and new simulator flow"
```
---

### Task 3A: Runtimes theo version và Add Runtime

**Files:**
- Create: `App/Sources/OpenSimApp/Runtimes/RuntimesView.swift`, `RuntimeModel.swift`, `AddRuntimeSheet.swift`
- Modify: `App/Sources/OpenSimApp/App/AppEnvironment.swift`, `App/Sources/OpenSimApp/App/AppShell.swift`, `App/Sources/OpenSimApp/App/DaemonClient.swift`
- Test: `Tests/OpenSimAppUITests/RuntimesUITests.swift`

**Interfaces:**
- Consumes: operation `runtime_list`, `runtime_download`, `runtime_install`, `runtime_delete`; `Runtime`, `RuntimeID`, `RuntimeSource`, `OpenSimError`; `DeviceCatalogModel`.
- Produces: `RuntimeModel`; `RuntimesView`; `AddRuntimeSheet`; `RuntimeModel.load(using:)`, `.install(_:)`, `.cancelInstall()`, `.remove(_:)`.

- [ ] **Step 1: Viết UI test thất bại**

```swift
import XCTest

final class RuntimesUITests: XCTestCase {
    func testVersionRowsAndAddRuntime() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        app.cells["sidebar-runtimes"].click()
        XCTAssertTrue(app.otherElements["runtimes-list"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["add-runtime-button"].exists)
        XCTAssertTrue(app.staticTexts["runtime-row-iOS 26.4"].exists)
        XCTAssertTrue(app.staticTexts["runtime-row-watchOS 27.0"].exists)
        app.buttons["add-runtime-button"].click()
        XCTAssertTrue(app.sheets["add-runtime-sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-runtime-source-download"].exists)
        XCTAssertTrue(app.buttons["add-runtime-source-file"].exists)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/RuntimesUITests
```

Expected: FAIL vì `runtimes-list` chưa tồn tại.

- [ ] **Step 3: Viết model và view**

`RuntimeModel` là `@MainActor @Observable`; `load()` lấy `runtime_list` (installed + catalog known), giữ mọi version, không gộp platform. `install(_:)` gọi `runtime_download` cho version catalog hoặc `runtime_install` với path `.dmg`; `cancelInstall()` cancel Task; `remove(_:)` gọi `runtime_delete` sau xác nhận và chỉ khi `deviceCount == 0`. Sau install/remove gọi `catalog.refresh()` và refresh NewDeviceModel runtime list.

```swift
@MainActor
@Observable
public final class RuntimeModel {
    public enum State: Equatable {
        case idle
        case loading
        case ready
        case installing(RuntimeID)
        case failed(String)
    }
    public private(set) var runtimes: [Runtime] = []
    public private(set) var state: State = .idle
    public func load(using client: DaemonClient) async
    public func install(_ runtime: Runtime) async
    public func cancelInstall()
    public func remove(_ runtime: Runtime) async throws
}
```

`RuntimesView`: `List` row theo platform + version; mỗi row name/version, installed/not, size, `deviceCount ?? 0`, source; actions Install/Cancel/Reveal/Remove; header `Add Runtime` identifier `add-runtime-button`. Container `runtimes-list`, row `runtime-row-<name>`, install `runtime-install-button`, cancel `runtime-cancel-button`, remove `runtime-remove-button`, progress `runtime-progress`, error `runtime-error`.

`AddRuntimeSheet`: segmented Download/From File; Download chọn platform/version từ catalog best-effort, version đã cài disable; From File dùng `.fileImporter` cho `.dmg`; nút Install gọi `runtime_download`/`runtime_install`. Identifier `add-runtime-sheet`, `add-runtime-source-download`, `add-runtime-source-file`, `add-runtime-version`, `add-runtime-confirm`.

Remove chặn khi `deviceCount > 0`: sheet giải thích và đưa `Show Devices`; không xoá ngầm.

- [ ] **Step 4: Chạy để thấy pass**

```bash
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/RuntimesUITests
```

Expected: `BUILD SUCCEEDED`; row version hiện, Add Runtime mở, Download/From File tồn tại.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/OpenSimApp/Runtimes App/Sources/OpenSimApp/App/AppEnvironment.swift App/Sources/OpenSimApp/App/AppShell.swift Tests/OpenSimAppUITests/RuntimesUITests.swift
git commit -m "feat(app): add runtimes version management and add runtime"
```
---

### Task 4: Device window, `SimulatorScreenView` host và nhiều cửa sổ

**Files:**
- Create: `App/Sources/OpenSimApp/Windows/DeviceWindowRoot.swift`, `App/Sources/OpenSimApp/Windows/DeviceWindowModel.swift`, `SimulatorScreenHost.swift`, `App/Sources/OpenSimApp/Windows/SimulatorScreenContainerView.swift`, `WindowAccessor.swift`, `SimulatorScreenView+Readiness.swift`, `DeviceBootRequiredView.swift`, `SimulatorGesture.swift`
- Modify: `App/Sources/OpenSimApp/App/OpenSimApp.swift`, `App/Sources/OpenSimApp/App/AppShell.swift`
- Test: `Tests/OpenSimAppUITests/DeviceWindowUITests.swift`

**Interfaces:**
- Consumes: `SimulatorScreenView`, `SimulatorScreenDisplaying`, `SimctlBridge`, `Device`, `DeviceID`, `ScreenRotation`, `OpenSimError`.
- Produces: `DeviceWindowRoot`; `DeviceWindowModel`; `SimulatorScreenHost`; `WindowAccessor`; scene `WindowGroup(id: "device", for: DeviceID.self)`.

- [ ] **Step 1: Viết UI test thất bại**

`Tests/OpenSimAppUITests/DeviceWindowUITests.swift`:

```swift
import XCTest

final class DeviceWindowUITests: XCTestCase {
    func testDeviceWindowOpensWithScreenOrBootPrompt() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        let firstRow = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'device-row-'")).firstMatch
        guard firstRow.waitForExistence(timeout: 25) else {
            throw XCTSkip("No device available for window test")
        }
        firstRow.doubleClick()
        XCTAssertTrue(app.otherElements["device-window"].waitForExistence(timeout: 20))
        let screenReady = app.otherElements["simulator-screen"].waitForExistence(timeout: 15)
        let bootPrompt = app.buttons["device-boot-button"].exists
        let loadError = app.staticTexts["device-window-error"].exists
        XCTAssertTrue(screenReady || bootPrompt || loadError)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/DeviceWindowUITests
```

Expected: FAIL vì scene `device` và `device-window` chưa tồn tại.

- [ ] **Step 3: Viết window và screen host**

`SimulatorScreenView+Readiness.swift`:

```swift
import OpenSimBridgeUI

public extension SimulatorScreenView {
    var isReadyForInput: Bool { screenSize.width > 0 && screenSize.height > 0 }
}
```

`SimulatorGesture.swift` (Task 5 thêm enum `SimulatorGesture` vào cùng file):

```swift
public enum GestureMode: String, CaseIterable, Identifiable, Sendable {
    case direct, pinch, rotate
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .direct: return "Direct"
        case .pinch: return "Pinch"
        case .rotate: return "Rotate"
        }
    }
}
```

`WindowAccessor.swift`: `NSViewRepresentable` nhận `DeviceID`. Trong `DispatchQueue.main.async` của `makeNSView`, lấy `view.window`, gọi `AppEnvironment.shared.windows.register(window:device:)`, và đăng ký `NSWindow.willCloseNotification` để gọi `unregister(device:)` trong `Task { @MainActor in }`. Không giữ strong reference tới window.

`DeviceBootRequiredView.swift`: VStack icon `power`, text "`<name>` is `<state>`", text "Boot the device to open a live screen.", Button "Boot" identifier `device-boot-button` với `.keyboardShortcut(.defaultAction)`, container identifier `device-boot-required`.

`App/Sources/OpenSimApp/Windows/DeviceWindowModel.swift`: `@MainActor @Observable`, property `deviceID`, `device`, `loadError`, `screenError`, `screenSize`, `rotation`, `zoom`, `gestureMode`, `keyboardCapture`, `environment`, `lease`, `eventToken`, `weak screenView`. Computed `displayBridge` lấy từ `environment.bridge.display`; method `reconnect()` release lease cũ, load device và acquire lại. Mọi input phải qua `hasHeldControlLease`; không có đường tắt gọi Bridge input. Hành vi bắt buộc:

- `activate()`: subscribe `environment.events` và forward event cho `apply(_:)`; lấy `client.device(deviceID)`; lỗi map `OpenSimError`.
- `close()`: unsubscribe event, `screenView?.disconnect()`, clear reference.
- `attach(_:)`: lưu weak view, gán `onScreenSizeChange` cập nhật `screenSize`, gán `onError` gọi `screenFailed`.
- `screenFailed(_:)`: lưu error, log OSLog category window.
- `boot()`: `environment.lifecycle.perform(.boot, on: deviceID, using: nil)`, cập nhật device, clear screen error.
- `rotateView(clockwise:)`: cycle `[portrait, landscapeLeft, portraitUpsideDown, landscapeRight]`, gọi `screenView?.setRotation`.
- `zoomChanged(_:)`: clamp 0.5 đến 2.0.
- `apply(_:)`: chỉ nhận `deviceStateChanged` đúng device; cập nhật `device.state`; nếu state khác booted thì `disconnect()` screen.

`App/Sources/OpenSimApp/Windows/SimulatorScreenContainerView.swift`: `NSView` identifier `simulator-screen`, layer đen và masksToBounds. `configure()` chỉ chạy một lần:

```swift
guard !configured, let bridge = model.displayBridge else { return }
configured = true
do {
    let view = try SimulatorScreenView(device: model.deviceID, bridge: bridge)
    addSubview(view)
    screenView = view
    model.attach(view)
    Task { [weak self] in
        do {
            try await view.connect()
            self?.needsLayout = true
        } catch let error as OpenSimError {
            self?.model.screenFailed(error)
        } catch {
            self?.model.screenFailed(.capabilityUnavailable("render"))
        }
    }
} catch let error as OpenSimError {
    model.screenFailed(error)
} catch {
    model.screenFailed(.capabilityUnavailable("render"))
}
```

`layout()` đặt `screenView.frame = bounds`; `apply(zoom:rotation:)` gọi `setRotation`, layout lại, và đặt frame `bounds.insetBy(dx: bounds.width * (1 - zoom) / 2, dy: bounds.height * (1 - zoom) / 2)`. Không tạo surface riêng, không gọi private API.

`SimulatorScreenHost.swift`:

```swift
import SwiftUI

struct SimulatorScreenHost: NSViewRepresentable {
    @Bindable var model: DeviceWindowModel

    func makeNSView(context: Context) -> SimulatorScreenContainerView {
        let view = SimulatorScreenContainerView(model: model)
        view.configure()
        return view
    }

    func updateNSView(_ nsView: SimulatorScreenContainerView, context: Context) {
        nsView.apply(zoom: model.zoom, rotation: model.rotation)
    }
}
```

`App/Sources/OpenSimApp/Windows/DeviceWindowRoot.swift`:

```swift
import SwiftUI
import OpenSimCore

struct DeviceWindowRoot: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: DeviceWindowModel

    init(deviceID: DeviceID) {
        _model = State(initialValue: DeviceWindowModel(deviceID: deviceID, environment: AppEnvironment.shared))
    }

    var body: some View {
        Group {
            if let error = model.loadError {
                ErrorStateView(error: error, identifier: "device-window-error")
            } else if let device = model.device {
                if device.state == .booted {
                    SimulatorScreenHost(model: model)
                } else {
                    DeviceBootRequiredView(device: device) {
                        Task { await model.boot() }
                    }
                }
            } else {
                LoadingStateView("Loading device", identifier: "device-window-loading")
            }
        }
        .frame(minWidth: 360, minHeight: 640)
        .background(WindowAccessor(deviceID: model.deviceID))
        .navigationTitle(model.device?.name ?? "Device")
        .accessibilityIdentifier("device-window")
        .task { await model.activate() }
        .onDisappear { model.close() }
    }
}
```

`DeviceWindowRoot` hiển thị `model.screenError` bằng banner identifier `capability-banner` phía trên screen; nếu `displayBridge` nil, container gọi `screenFailed(.capabilityUnavailable("render"))` thay vì im lặng.

`App/Sources/OpenSimApp/App/OpenSimApp.swift` thêm scene:

```swift
        WindowGroup("Device", id: "device", for: DeviceID.self) { $deviceID in
            if let deviceID {
                DeviceWindowRoot(deviceID: deviceID)
                    .environment(environment)
            }
        }
        .defaultSize(width: 430, height: 880)
```

`AppShell` thêm background cấu hình openWindow:

```swift
struct WindowOpenConfigurator: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        Color.clear.onAppear {
            environment.windows.configure(open: openWindow)
        }
    }
}
```

Gắn `.background(WindowOpenConfigurator())` vào `AppShell` root.

- [ ] **Step 4: Chạy để thấy pass**

```bash
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/DeviceWindowUITests
```

Expected: `BUILD SUCCEEDED`; `DeviceWindowUITests` pass 1 test hoặc skip có lý do nếu không có device.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/OpenSimApp App/Sources/OpenSimApp/App/OpenSimApp.swift Tests/OpenSimAppUITests/DeviceWindowUITests.swift
git commit -m "feat(app): add device windows and simulator screen host"
```
---

### Task 5: Gesture overlay, keyboard và paste

**Files:**
- Create: `App/Sources/OpenSimApp/Windows/InputOverlayView.swift`, `GestureController.swift`, `KeyboardController.swift`
- Modify: `App/Sources/OpenSimApp/Windows/SimulatorGesture.swift`, `App/Sources/OpenSimApp/Windows/SimulatorScreenContainerView.swift`, `App/Sources/OpenSimApp/Windows/DeviceWindowModel.swift`, `App/Sources/OpenSimApp/Windows/DeviceWindowRoot.swift`
- Test: `Tests/OpenSimAppUITests/DeviceWindowUITests.swift` (thêm method)

**Interfaces:**
- Consumes: `InputControlling`, `HardwareButton`, `Key`, `KeyModifiers`, `Point`, `NSEvent`, `NSPasteboard`.
- Produces: `SimulatorGesture`; `InputOverlayView`; `GestureController.send(_:on:using:)`; `KeyboardController.handle(event:model:)`.

- [ ] **Step 1: Viết UI test thất bại**

Thêm vào `DeviceWindowUITests`:

```swift
    func testInputOverlayIsInstalled() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        let firstRow = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'device-row-'")).firstMatch
        guard firstRow.waitForExistence(timeout: 25) else {
            throw XCTSkip("No device available for input test")
        }
        firstRow.doubleClick()
        guard app.otherElements["simulator-screen"].waitForExistence(timeout: 20) else {
            throw XCTSkip("Device is not booted; boot a device and rerun")
        }
        XCTAssertTrue(app.otherElements["device-input-overlay"].exists)
    }
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/DeviceWindowUITests/testInputOverlayIsInstalled
```

Expected: FAIL vì `device-input-overlay` chưa tồn tại.

- [ ] **Step 3: Viết overlay, gesture và keyboard**

`SimulatorGesture.swift` (thêm enum vào file đã tạo ở Task 4):

```swift
import OpenSimCore

public enum SimulatorGesture: Sendable, Equatable {
    case tap(Point)
    case longPress(Point)
    case swipe(from: Point, to: Point, durationMs: Int)
    case drag(from: Point, to: Point, durationMs: Int)
    case pinch(center: Point, scale: Double, durationMs: Int)
    case rotate(center: Point, angle: Double, durationMs: Int)
    case scroll(deltaX: Double, deltaY: Double, at: Point)
}
```

`InputOverlayView.swift`: `@MainActor final class InputOverlayView: NSView`, `acceptsFirstResponder = true`, accessibility identifier `device-input-overlay`. Cần các callback `onTap`, `onLongPress`, `onSwipe`, `onDrag`, `onScroll`, `onMagnify`, `onRotate`, `onKey`. Hành vi bắt buộc:

- `mouseDown`: `makeFirstResponder(self)`, lưu point/time, hẹn `Timer` 0.65 giây; timer cháy thì set `didLongPress` và gọi `onLongPress`.
- `rightMouseDown`: gọi `onLongPress` ngay.
- `mouseDragged`: Option + kéo gọi `onMagnify(start, exp(deltaY * 0.01))`; Command + kéo gọi `onRotate(start, deltaX * 0.5)`.
- `mouseUp`: nếu đã long press thì bỏ qua; distance ≤ 8 point là tap; duration < 250 ms và distance > 20 point là swipe; còn lại là drag. Duration tính bằng ms.
- `scrollWheel`, `magnify`, `rotate` forward delta và point.
- `keyDown` và `performKeyEquivalent` gọi `onKey`; trả `true` thì không gọi super.

`GestureController.swift`: enum static `send(_:on:using:)`, switch đủ bảy case và gọi đúng `InputControlling` method. Long press cố định 800 ms, settle tap là false. Không tự đổi tọa độ; point đã ở hệ simulator.

`KeyboardController.swift`: struct với `handle(event:capture:) -> KeyEvent?`.

```swift
public enum KeyEvent: Sendable, Equatable {
    case key(Key, KeyModifiers)
    case paste(String)
    case ignored
}
```

`handle` trả nil khi capture tắt. Map `event.modifierFlags` sang `KeyModifiers`; name lấy `charactersIgnoringModifiers`; `Cmd+V` đọc `NSPasteboard.general.string(forType: .string)` và trả `.paste(text)`, pasteboard rỗng trả `.ignored`; còn lại trả `.key(Key(name:keyCode:), modifiers)`. Không gửi `Cmd+V` như phím thường.

`DeviceWindowModel` thêm:

```swift
    public private(set) var inputError: OpenSimError?

    public var canSendInput: Bool { hasHeldControlLease }

    private var hasHeldControlLease: Bool {
        guard case .held(let held) = lease.state else { return false }
        return held.mode == .control && held.deviceID == deviceID && held.expiresAt > Date()
    }

    private func requireControlLease() -> Bool {
        guard hasHeldControlLease else {
            inputError = OpenSimError(
                code: ErrorCode.leaseRequired.rawValue,
                message: "Control lease is required before sending input",
                details: ["device": deviceID.rawValue],
                recovery: "Acquire control or take control from the agent",
                retryable: true
            )
            return false
        }
        return true
    }

    public func handle(_ gesture: SimulatorGesture) {
        guard requireControlLease(), let input = environment.bridge.input else {
            if environment.bridge.input == nil { inputError = .capabilityUnavailable("hid") }
            return
        }
        Task {
            do {
                try await GestureController.send(gesture, on: deviceID, using: input)
                inputError = nil
            } catch let error as OpenSimError {
                inputError = error
            } catch {
                inputError = .capabilityUnavailable("hid")
            }
        }
    }

    public func handleKey(_ event: NSEvent) -> Bool {
        guard keyboardCapture else { return false }
        guard requireControlLease(), let input = environment.bridge.input else { return true }
        guard let mapped = KeyboardController().handle(event: event, capture: true) else { return false }
        switch mapped {
        case .paste(let text):
            Task { try? await input.typeText(on: deviceID, text: text) }
            return true
        case .key(let key, let modifiers):
            Task { try? await input.key(on: deviceID, key: key, modifiers: modifiers) }
            return true
        case .ignored:
            return true
        }
    }

    public func sendButton(_ button: HardwareButton) {
        guard requireControlLease(), let input = environment.bridge.input else {
            if environment.bridge.input == nil { inputError = .capabilityUnavailable("hid") }
            return
        }
        Task {
            do {
                try await input.button(on: deviceID, button: button)
                inputError = nil
            } catch let error as OpenSimError {
                inputError = error
            } catch {
                inputError = .capabilityUnavailable("hid")
            }
        }
    }
```

`SimulatorScreenContainerView` thêm overlay; `overlay.isUserInteractionEnabled = model.canSendInput` và cập nhật khi `lease.state` đổi. `canSendInput` chỉ true khi `held` lease còn hạn; callbacks vẫn kiểm tra lại trong model, nên lease conflict/revoked không thể lọt input.

```swift
    private let overlay = InputOverlayView()

    // trong init:
    addSubview(overlay)

    // trong configure:
    overlay.onTap = { [weak self] point in self?.forward(point) { .tap($0) } }
    overlay.onLongPress = { [weak self] point in self?.forward(point) { .longPress($0) } }
    overlay.onSwipe = { [weak self] start, end, duration in
        self?.forward(start, end) { .swipe(from: $0, to: $1, durationMs: duration) }
    }
    overlay.onDrag = { [weak self] start, end, duration in
        self?.forward(start, end) { .drag(from: $0, to: $1, durationMs: duration) }
    }
    overlay.onScroll = { [weak self] point, dx, dy in
        self?.forward(point) { .scroll(deltaX: dx, deltaY: dy, at: $0) }
    }
    overlay.onMagnify = { [weak self] point, scale in
        self?.forward(point) { .pinch(center: $0, scale: scale, durationMs: 200) }
    }
    overlay.onRotate = { [weak self] point, angle in
        self?.forward(point) { .rotate(center: $0, angle: angle, durationMs: 200) }
    }
    overlay.onKey = { [weak self] event in self?.model.handleKey(event) ?? false }

    // helper:
    private func forward(_ point: NSPoint, _ build: (Point) -> SimulatorGesture) {
        guard let screenView, screenView.isReadyForInput,
              let simulator = screenView.simulatorPoint(fromViewPoint: convert(point, to: screenView)) else {
            return
        }
        model.handle(build(simulator))
    }

    private func forward(_ start: NSPoint, _ end: NSPoint, _ build: (Point, Point) -> SimulatorGesture) {
        guard let screenView, screenView.isReadyForInput,
              let from = screenView.simulatorPoint(fromViewPoint: convert(start, to: screenView)),
              let to = screenView.simulatorPoint(fromViewPoint: convert(end, to: screenView)) else {
            return
        }
        model.handle(build(from, to))
    }

    // layout:
    overlay.frame = bounds
```

Trong `layout`, đặt `overlay.frame = bounds` sau `screenView.frame`.

`DeviceWindowRoot` hiển thị banner lỗi input khi có:

```swift
if let error = model.inputError {
    Text(error.message)
        .font(.caption)
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.16))
        .accessibilityIdentifier("input-error-banner")
}
```

Đặt phía trên `SimulatorScreenHost` trong VStack. Khi capability `hid` unavailable, toàn bộ gesture và keyboard bị disable qua guard; app không crash.

- [ ] **Step 4: Chạy để thấy pass**

```bash
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/DeviceWindowUITests
```

Expected: `BUILD SUCCEEDED`; 2 test pass hoặc skip đúng lý do nếu device không booted.

- [ ] **Step 5: Kiểm tra thủ công gesture với fixture Plan 2**

Mở cửa sổ device booted, cài fixture `dev.opensim.fixture`, rồi kiểm tra: tap tăng counter, long press đổi label, swipe đổi trang, drag di chuyển, pinch đổi scale, rotate đổi góc, scroll, gõ text, `Cmd+V` dán text. Ghi kết quả vào checklist cuối plan. Không dùng Chrome.

- [ ] **Step 6: Commit**

```bash
git add App/Sources/OpenSimApp/Windows Tests/OpenSimAppUITests/DeviceWindowUITests.swift
git commit -m "feat(app): add gesture overlay and keyboard input"
```
---

### Task 6: Toolbar, hardware buttons, screenshot, record, zoom và menu Device

**Files:**
- Create: `App/Sources/OpenSimApp/Windows/DeviceToolbar.swift`, `DeviceCaptureController.swift`, `DeviceWindowCommands.swift`
- Modify: `App/Sources/OpenSimApp/Windows/DeviceWindowModel.swift`, `App/Sources/OpenSimApp/Windows/DeviceWindowRoot.swift`, `App/Sources/OpenSimApp/App/OpenSimApp.swift`
- Test: `Tests/OpenSimAppUITests/DeviceWindowUITests.swift`

**Interfaces:**
- Consumes: `ScreenControlling`, `Screenshot`, `RecordingID`, `HardwareButton`, `NSSavePanel`, `UniformTypeIdentifiers`, `OpenSimPaths`.
- Produces: `DeviceToolbar`; `DeviceCaptureController`; `DeviceWindowCommands`; `DeviceFocusedValueKey`.

- [ ] **Step 1: Viết UI test thất bại**

Thêm method:

```swift
    func testDeviceToolbarExposesHardwareAndCaptureActions() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        let firstRow = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'device-row-'")).firstMatch
        guard firstRow.waitForExistence(timeout: 25) else {
            throw XCTSkip("No device available for toolbar test")
        }
        firstRow.doubleClick()
        guard app.otherElements["simulator-screen"].waitForExistence(timeout: 20) else {
            throw XCTSkip("Device is not booted; boot a device and rerun")
        }
        for identifier in ["toolbar-home", "toolbar-lock", "toolbar-rotate-left", "toolbar-screenshot", "toolbar-keyboard", "toolbar-zoom"] {
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5), "Missing \(identifier)")
        }
    }
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/DeviceWindowUITests/testDeviceToolbarExposesHardwareAndCaptureActions
```

Expected: FAIL vì toolbar chưa có.

- [ ] **Step 3: Viết toolbar và capture**

`DeviceToolbar.swift`: `ToolbarContent` nhận `@Bindable model`, dùng `ToolbarItemGroup(placement: .primaryAction)` với các control theo thứ tự: Home `toolbar-home` (`.home`), Lock `toolbar-lock`, Side `toolbar-side`, Menu Volume Up/Down `toolbar-volume`, Rotate View Left `toolbar-rotate-left`, Rotate View Right `toolbar-rotate-right`, Screenshot `toolbar-screenshot`, Record `toolbar-record` (icon đổi theo `recordingID`), Toggle keyboard `toolbar-keyboard` bound `keyboardCapture`, Picker gesture `toolbar-gesture-mode`, Menu zoom `toolbar-zoom` (50, 75, 100, 125, 150, 200 phần trăm). Mỗi control có `help` và accessibility label.

`DeviceCaptureController.swift`: `@MainActor final class` giữ `AppEnvironment`.

- `saveScreenshot(device:name:)`: guard `bridge.screen`; `NSSavePanel` allowed `.png`, name `<device>.png`; gọi `screenshot(on:format:.png,scale:1.0,quality:nil)`; nếu `data` ghi atomic, nếu `path` copy sang URL, nếu cả hai nil throw `invalid_argument`; user Cancel thì return.
- `toggleRecording(device:current:)`: guard `bridge.screen`; nếu current thì `stopRecording`, reveal file, trả nil; nếu chưa thì tạo thư mục `OpenSimPaths.baseDirectory/recordings` quyền 0700, path `<udid>-<epoch>.mov`, gọi `startRecording(codec: .h264)`, trả `RecordingID`.
- Mọi lỗi map `OpenSimError`; lỗi capability trả `capability_unavailable`.

`DeviceWindowModel` thêm:

```swift
    public private(set) var recordingID: RecordingID?
    public private(set) var captureError: OpenSimError?
    private lazy var capture = DeviceCaptureController(environment: environment)

    public func captureScreenshot() async {
        do {
            try await capture.saveScreenshot(device: deviceID, name: device?.name ?? deviceID.rawValue)
            captureError = nil
        } catch let error as OpenSimError {
            captureError = error
        } catch {
            captureError = .capabilityUnavailable("screenshot")
        }
    }

    public func toggleRecording() async {
        do {
            recordingID = try await capture.toggleRecording(device: deviceID, current: recordingID)
            captureError = nil
        } catch let error as OpenSimError {
            captureError = error
        } catch {
            captureError = .capabilityUnavailable("video")
        }
    }
```

`DeviceWindowRoot` thêm `.toolbar { DeviceToolbar(model: model) }`, hiển thị `captureError` banner identifier `capture-error-banner`, và `.focusedSceneValue(\.deviceWindowModel, model)`.

`DeviceWindowCommands.swift`:

```swift
import SwiftUI

struct DeviceFocusedValueKey: FocusedValueKey {
    typealias Value = DeviceWindowModel
}

extension FocusedValues {
    var deviceWindowModel: DeviceWindowModel? {
        get { self[DeviceFocusedValueKey.self] }
        set { self[DeviceFocusedValueKey.self] = newValue }
    }
}

struct DeviceWindowCommands: Commands {
    @FocusedValue(\.deviceWindowModel) private var model

    var body: some Commands {
        CommandMenu("Device") {
            Button("Home") { model?.sendButton(.home) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Lock") { model?.sendButton(.lock) }
                .keyboardShortcut("l", modifiers: [.command])
            Divider()
            Button("Rotate View Left") { model?.rotateView(clockwise: false) }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
            Button("Rotate View Right") { model?.rotateView(clockwise: true) }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
            Divider()
            Button("Save Screenshot") { Task { await model?.captureScreenshot() } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Toggle Recording") { Task { await model?.toggleRecording() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Toggle("Capture Keyboard", isOn: Binding(
                get: { model?.keyboardCapture ?? false },
                set: { model?.keyboardCapture = $0 }
            ))
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
}
```

`OpenSimApp` gắn `.commands { DeviceWindowCommands() }` cho device scene. Cmd+K để dành cho quick switch Task 8; device command dùng Cmd+Shift+K.

- [ ] **Step 4: Chạy để thấy pass**

```bash
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/DeviceWindowUITests
```

Expected: `BUILD SUCCEEDED`; toolbar test pass hoặc skip nếu device không booted.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/OpenSimApp/Windows App/Sources/OpenSimApp/App/OpenSimApp.swift Tests/OpenSimAppUITests/DeviceWindowUITests.swift
git commit -m "feat(app): add device toolbar capture and menu commands"
```
---

### Task 7: Lease coordinator, banner và takeover

**Files:**
- Create: `App/Sources/OpenSimApp/Windows/LeaseCoordinator.swift`, `LeaseBanner.swift`, `TakeControlSheet.swift`
- Create: `Tests/OpenSimAppUITests/Support/DaemonTestHarness.swift`
- Modify: `App/Sources/OpenSimApp/Windows/DeviceWindowModel.swift`, `App/Sources/OpenSimApp/Windows/DeviceWindowRoot.swift`
- Test: `Tests/OpenSimAppUITests/LeaseTakeoverUITests.swift`

**Interfaces:**
- Consumes: `DaemonClient.acquireLease`, `.heartbeat`, `.release`; `Lease`, `LeaseMode`, `DaemonEvent`, `LeaseChangedPayload`, `LeaseConflict`.
- Produces: `LeaseCoordinator.State`; `LeaseCoordinator.acquire(takeover:)`, `.takeControl()`, `.release()`, `.handle(_:)`; `LeaseBanner`; `TakeControlSheet`; `DaemonTestHarness`.

- [ ] **Step 1: Viết test thất bại**

`DaemonTestHarness` (test support, không phải app code): struct `Sendable`, đọc `daemon.json` từ `OPENSIM_HOME` hoặc `~/Library/Application Support/OpenSim`, lưu `baseURL` và bearer token. Định nghĩa `HarnessDevice` (`id`, `name`, `state`), `HarnessSession` (`id`), `HarnessLease` (`id`, `deviceID`), envelope `ok/data/error` và `HarnessError` (`code`, `message`).

```swift
func firstDevice() async throws -> HarnessDevice {
    let devices: [HarnessDevice] = try await get(path: "/v1/devices")
    guard let device = devices.first else {
        throw NSError(domain: "OpenSimUITest", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "No simulator device"])
    }
    return device
}

func acquireControl(device: String, owner: String) async throws -> HarnessLease {
    let session: HarnessSession = try await post(
        path: "/v1/sessions",
        body: CreateSession(clientKind: "test", clientName: owner)
    )
    return try await post(
        path: "/v1/leases",
        body: AcquireLease(deviceID: device, sessionID: session.id,
                           mode: "control", ttlSeconds: 300, ownerName: owner)
    )
}
```

`get`/`post` dùng `URLSession.ephemeral`, set `Authorization: Bearer <token>`, decode envelope; `ok == false` hoặc thiếu data thì throw `NSError` chứa error code. `CreateSession` có `clientKind`, `clientName`; `AcquireLease` có `deviceID`, `sessionID`, `mode`, `ttlSeconds`, `ownerName`. Không mock device, không đọc private API.

`Tests/OpenSimAppUITests/LeaseTakeoverUITests.swift`:

```swift
import XCTest

final class LeaseTakeoverUITests: XCTestCase {
    func testConflictBannerAndTakeControl() async throws {
        continueAfterFailure = false
        let harness = try DaemonTestHarness()
        let device = try await harness.firstDevice()
        _ = try await harness.acquireControl(device: device.id, owner: "ui-test-agent")

        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        let row = app.staticTexts[device.name]
        guard row.waitForExistence(timeout: 25) else {
            throw XCTSkip("Device row not available for \(device.name)")
        }
        row.doubleClick()

        let banner = app.otherElements["lease-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["lease-owner"].label.contains("ui-test-agent"))
        app.buttons["lease-take-control"].click()
        XCTAssertTrue(app.otherElements["takeover-sheet"].waitForExistence(timeout: 5))
        app.buttons["takeover-confirm"].click()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 20))
    }

    func testInputIsBlockedWhenHarnessHoldsLease() async throws {
        let harness = DaemonTestHarness()
        let device = try await harness.firstDevice()
        _ = try await harness.acquireControl(device: device.id, owner: "ui-test-agent")
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        let row = app.staticTexts[device.name]
        XCTAssertTrue(row.waitForExistence(timeout: 25))
        row.doubleClick()
        XCTAssertTrue(app.otherElements["simulator-screen"].waitForExistence(timeout: 20))
        app.otherElements["simulator-screen"].click()
        XCTAssertTrue(app.staticTexts["input-error-banner"].label.contains("Control lease is required"))
    }
}
```

Test này bắt buộc: `DeviceWindowModel` phải chặn gesture/key/button khi chưa giữ lease; không chỉ ẩn banner. `input-lease-required` lấy từ `inputError` trong inspector/toolbar. Kiểm tra thêm audit JSONL không có operation input nào sau cú click.

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/LeaseTakeoverUITests
```

Expected: FAIL vì `lease-banner` chưa tồn tại.

- [ ] **Step 3: Viết lease coordinator và UI**

`LeaseCoordinator.swift`:

```swift
import Foundation
import OpenSimCore
import OpenSimProtocol

@MainActor
@Observable
public final class LeaseCoordinator {
    public enum State: Equatable {
        case idle
        case acquiring
        case held(Lease)
        case conflict(LeaseConflict)
        case takingOver(LeaseConflict)
        case revoked
        case failed(OpenSimError)
    }

    public let deviceID: DeviceID
    public private(set) var state: State = .idle
    private let connection: DaemonConnectionModel
    private var heartbeatTask: Task<Void, Never>?

    public init(deviceID: DeviceID, connection: DaemonConnectionModel) {
        self.deviceID = deviceID
        self.connection = connection
    }

    public func acquire(takeover: Bool = false) async {
        if case .held = state { return }
        guard let client = connection.client else {
            state = .failed(.daemonUnavailable("Daemon is not connected"))
            return
        }
        state = .acquiring
        do {
            let lease = try await client.acquireLease(
                device: deviceID,
                mode: .control,
                takeover: takeover,
                ttlSeconds: 300
            )
            state = .held(lease)
            startHeartbeat(lease, client: client)
        } catch let error as OpenSimError {
            if let conflict = LeaseConflict(deviceID: deviceID, error: error) {
                state = .conflict(conflict)
            } else {
                state = .failed(error)
            }
        } catch {
            state = .failed(.daemonUnavailable(String(describing: error)))
        }
    }

    public func takeControl() async {
        guard case .conflict(let conflict) = state else { return }
        state = .takingOver(conflict)
        await acquire(takeover: true)
    }

    public func release() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        guard case .held(let lease) = state, let client = connection.client else {
            state = .idle
            return
        }
        try? await client.release(lease)
        state = .idle
    }

    public func handle(_ event: DaemonEvent) {
        guard event.type == .leaseChanged || event.type == .leaseRevoked else { return }
        guard let payload = try? event.data.decoded(LeaseChangedPayload.self),
              payload.lease.deviceID == deviceID,
              payload.lease.mode == .control else {
            return
        }
        guard case .held(let held) = state else { return }
        if payload.lease.id != held.id && payload.lease.sessionID != held.sessionID {
            state = .revoked
            heartbeatTask?.cancel()
        }
    }

    private func startHeartbeat(_ lease: Lease, client: DaemonClient) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { return }
                do {
                    _ = try await client.heartbeat(lease)
                } catch let error as OpenSimError where error.code == "lease_revoked" || error.code == "lease_conflict" {
                    self?.state = .revoked
                    return
                } catch {
                    self?.state = .failed(.daemonUnavailable(String(describing: error)))
                    return
                }
            }
        }
    }
}
```

`LeaseBanner.swift`: View nhận `LeaseCoordinator.State`, closure `takeControl`, `retry`. Chỉ render khi state là conflict/takingOver/revoked/failed. Nội dung:
- conflict/takingOver: title "Agent is controlling this device", detail "`<owner>` holds the control lease" identifier `lease-owner`, Button "Take control" identifier `lease-take-control`.
- revoked: title "Control lease was revoked", detail "Another session took control", Button "Retry" identifier `lease-retry`.
- failed: title "Control is unavailable", detail là error message, Button "Retry".
Container identifier `lease-banner`, accessibility children contain, nền cam nhạt. Held/acquiring/idle không hiện banner.

`TakeControlSheet.swift`: View nhận `LeaseConflict`, closure confirm/cancel. Nội dung: title "Take control of this device?", giải thích owner đang dùng, lease bị thu hồi sau grace period, client kia nhận `lease_revoked` ở lần ghi tiếp theo, hiển thị `expiresAt` nếu có. HStack Button Cancel identifier `takeover-cancel` với `.keyboardShortcut(.cancelAction)` và `@FocusState` được set true trong `onAppear`; Button "Take Control" role destructive identifier `takeover-confirm`. Container identifier `takeover-sheet`, width 460.

`DeviceWindowModel` thêm `public let lease: LeaseCoordinator`, khởi tạo trong init. `activate()` chỉ load device và subscribe event chuyển cho `lease.handle(event)`; **không** acquire khi cửa sổ mới mở. `WindowAccessor`/`DeviceWindowRoot` acquire khi window becomeKey và release khi resignKey (trừ lúc takeover), đúng spec 9.2. `close()` release lease trước khi unsubscribe. `boot()` truyền `using: lease.heldLease` với computed:

```swift
extension LeaseCoordinator {
    var heldLease: Lease? {
        if case .held(let lease) = state { return lease }
        return nil
    }
}
```

Nếu chưa held, `boot()` acquire trước rồi dùng lease; nếu conflict, banner hiện và boot không chạy. `DeviceWindowRoot` quan sát `environment.connection.generation`; khi giá trị tăng, gọi `model.reconnect()` để release lease cũ, load lại device và acquire lease mới.

`DeviceWindowRoot`:

```swift
VStack(spacing: 0) {
    LeaseBanner(
        state: model.lease.state,
        takeControl: { model.showTakeover = true },
        retry: { Task { await model.lease.acquire() } }
    )
    if let error = model.inputError {
        Text(error.message)
            .font(.caption)
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.16))
            .accessibilityIdentifier("input-error-banner")
    }
    content
}
.sheet(isPresented: $model.showTakeover) {
    if case .conflict(let conflict) = model.lease.state {
        TakeControlSheet(
            conflict: conflict,
            confirm: {
                model.showTakeover = false
                Task { await model.lease.takeControl() }
            },
            cancel: { model.showTakeover = false }
        )
    }
}
```

`showTakeover` là `public var` trong model. Sheet dùng `.sheet` trên device window; identifier vẫn thấy trong XCUITest.

`DeviceWindowRoot` giữ `NSWindow` từ `WindowAccessor` và dùng `.onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification))`/`didResignKeyNotification`, lọc đúng window: becomeKey gọi `model.lease.acquire()`, resignKey gọi `model.lease.release()` trừ khi takeover sheet đang mở. Không acquire lease khi cửa sổ chỉ mở nhưng không key.

- [ ] **Step 4: Chạy để thấy pass**

```bash
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/LeaseTakeoverUITests
```

Expected: PASS 1 test; takeover mất tối đa 3 giây grace, banner biến mất trong 20 giây.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/OpenSimApp/Windows Tests/OpenSimAppUITests/Support/DaemonTestHarness.swift Tests/OpenSimAppUITests/LeaseTakeoverUITests.swift
git commit -m "feat(app): add lease banner and takeover flow"
```
---

### Task 8: Quick switch `Cmd+K`, nhiều cửa sổ và menu bar extra

**Files:**
- Create: `App/Sources/OpenSimApp/QuickSwitch/QuickSwitchPanelController.swift`, `App/Sources/OpenSimApp/QuickSwitch/QuickSwitchPalette.swift`, `App/Sources/OpenSimApp/QuickSwitch/QuickSwitchModel.swift`, `App/Sources/OpenSimApp/MenuBar/MenuBarContentView.swift`, `App/Sources/OpenSimApp/MenuBar/MenuBarModel.swift`, `App/Sources/OpenSimApp/App/AppCommands.swift`
- Modify: `App/Sources/OpenSimApp/App/OpenSimApp.swift`, `App/Sources/OpenSimApp/App/AppEnvironment.swift`
- Test: `Tests/OpenSimAppUITests/QuickSwitchUITests.swift`

**Interfaces:**
- Consumes: `DeviceCatalogModel`, `DeviceWindowManager`, `DeviceLifecycleService`, `DaemonConnectionModel`, `Device`, `DeviceState`.
- Produces: `QuickSwitchModel`; `QuickSwitchPanelController.show()`; `MenuBarModel`; `AppCommands`; shortcut `Cmd+K`.

- [ ] **Step 1: Viết UI test thất bại**

```swift
import XCTest

final class QuickSwitchUITests: XCTestCase {
    func testCommandKOpensPaletteAndOpensDevice() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        let firstRow = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'device-row-'")).firstMatch
        guard firstRow.waitForExistence(timeout: 25) else {
            throw XCTSkip("No device available for quick switch")
        }
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.otherElements["quick-switch-palette"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["quick-switch-search"].exists)
        app.textFields["quick-switch-search"].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.otherElements["device-window"].waitForExistence(timeout: 20))
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/QuickSwitchUITests
```

Expected: FAIL vì palette chưa tồn tại.

- [ ] **Step 3: Viết quick switch và menu bar**

`QuickSwitchModel.swift`:

```swift
@MainActor
@Observable
public final class QuickSwitchModel {
    public var query = ""
    public var highlighted = 0
    private let catalog: DeviceCatalogModel
    private let windows: DeviceWindowManager
    private let lifecycle: DeviceLifecycleService

    public init(catalog: DeviceCatalogModel, windows: DeviceWindowManager, lifecycle: DeviceLifecycleService) {
        self.catalog = catalog
        self.windows = windows
        self.lifecycle = lifecycle
    }

    public var results: [Device] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return catalog.devices }
        return catalog.devices.filter {
            $0.name.lowercased().contains(text) || $0.id.rawValue.lowercased().contains(text)
        }
    }

    public func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        highlighted = min(max(highlighted + delta, 0), results.count - 1)
    }

    public func activate() async {
        guard results.indices.contains(highlighted) else { return }
        let device = results[highlighted]
        if device.state != .booted {
            _ = try? await lifecycle.perform(.boot, on: device.id, using: nil)
        }
        windows.show(device.id)
        query = ""
        highlighted = 0
    }
}
```

`QuickSwitchPanelController.swift`: `@MainActor final class` giữ `NSPanel?`. `show(environment:)` tạo `NSPanel(contentRect: 560x360, styleMask: [.titled, .closable, .fullSizeContentView])`, `titleVisibility = .hidden`, `titlebarAppearsTransparent = true`, `isMovableByWindowBackground = true`, `level = .floating`, content `NSHostingController(rootView: QuickSwitchPalette(model:))`, `center()`, `makeKeyAndOrderFront`, `NSApp.activate`. `hide()` orderOut. Panel identifier `quick-switch-panel`.

`QuickSwitchPalette.swift`: VStack gồm TextField identifier `quick-switch-search` (focused on appear), List kết quả với row identifier `quick-switch-row-<udid>`, state badge, lease owner; chân hiển thị "Return to open, Esc to close". `.onKeyPress(.upArrow)`, `.downArrow`, `.return`, `.escape`; `.onExitCommand` hide. Container identifier `quick-switch-palette`. Row click gọi `activate` rồi hide.

`MenuBarModel.swift`:

```swift
@MainActor
@Observable
public final class MenuBarModel {
    private let catalog: DeviceCatalogModel
    private let windows: DeviceWindowManager
    private let lifecycle: DeviceLifecycleService
    private let connection: DaemonConnectionModel

    public var bootedDevices: [Device] { catalog.devices.filter { $0.state == .booted } }
    public var activeLeases: [Lease] { catalog.leases }

    public func open(_ id: DeviceID) { windows.show(id) }
    public func toggle(_ device: Device) async {
        let action: DeviceLifecycleAction = device.state == .booted ? .shutdown : .boot
        await catalog.perform(action, on: device.id)
    }
}
```

`MenuBarContentView.swift`: header `daemon-status-menubar` với label connection state; section "Booted Devices" rows identifier `menubar-device-<udid>` gồm Open và Shut Down; section "Agent Control" hiển thị mỗi control lease owner + device, nút "Open Device"; footer Open OpenSim (`openWindow(id: "main")`), Settings (`openSettings`), Quit. Không thao tác destructive ngoài shutdown đã có lease.

`AppCommands.swift`:

```swift
struct AppCommands: Commands {
    let environment: AppEnvironment
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Quick Switch") {
                environment.quickSwitch.show(environment: environment)
            }
            .keyboardShortcut("k", modifiers: [.command])
        }
    }
}
```

`AppEnvironment` thêm `let quickSwitch: QuickSwitchPanelController`, `let menuBar: MenuBarModel`, khởi tạo sau `catalog`, `lifecycle`. `OpenSimApp` thêm `.commands { AppCommands(environment: environment) }` cho main scene và `MenuBarExtra("OpenSim", systemImage: "iphone.gen3") { MenuBarContentView().environment(environment) }.menuBarExtraStyle(.window)`.

Nhiều cửa sổ: `DeviceWindowManager.show` đã focus cửa sổ cùng device; hai device khác nhau mở hai cửa sổ, mỗi model giữ lease riêng. Chuyển device bằng palette hoặc menu bar không đóng cửa sổ cũ.

- [ ] **Step 4: Chạy để thấy pass**

```bash
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/QuickSwitchUITests
```

Expected: `BUILD SUCCEEDED`; palette mở, Return mở cửa sổ device.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/OpenSimApp/QuickSwitch App/Sources/OpenSimApp/MenuBar App/Sources/OpenSimApp/App/AppCommands.swift App/Sources/OpenSimApp/App/OpenSimApp.swift Tests/OpenSimAppUITests/QuickSwitchUITests.swift
git commit -m "feat(app): add quick switch palette and menu bar extra"
```
---

### Task 9: Agent activity table và audit

**Files:**
- Create: `App/Sources/OpenSimApp/Activity/ActivityEntry.swift`, `AgentActivityModel.swift`, `AgentActivityView.swift`, `ActivityTable.swift`, `ActivityInspector.swift`
- Modify: `App/Sources/OpenSimApp/App/AppEnvironment.swift`, `App/Sources/OpenSimApp/App/AppShell.swift`
- Test: `Tests/OpenSimAppUITests/ActivityUITests.swift`

**Interfaces:**
- Consumes: `DaemonEvent`, `AuditAppendedPayload`, `LeaseChangedPayload`, `DeviceStateChangedPayload`, `OpenSimPaths.auditFile`, `ScreenControlling`.
- Produces: `ActivityEntry`; `AgentActivityModel.entries`, `.isPaused`, `.filter`, `.ingest(_:)`, `.loadHistory()`; `AgentActivityView`.

- [ ] **Step 1: Viết UI test thất bại**

`Tests/OpenSimAppUITests/ActivityUITests.swift`:

```swift
import XCTest

final class ActivityUITests: XCTestCase {
    func testActivityTabShowsFeedOrEmptyState() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        app.cells["sidebar-activity"].click()
        XCTAssertTrue(app.otherElements["activity-table"].waitForExistence(timeout: 10))
        let row = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'activity-row-'")).firstMatch
        XCTAssertTrue(row.exists || app.otherElements["activity-empty"].exists)
        XCTAssertTrue(app.buttons["activity-pause"].exists)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/ActivityUITests
```

Expected: FAIL vì `activity-table` chưa tồn tại.

- [ ] **Step 3: Viết activity model và view**

`ActivityEntry`: `Identifiable, Equatable, Sendable` gồm `id`, `timestamp`, `kind` (enum `lease/lifecycle/operation/session`), `title`, `detail`, `actor`, `deviceID`, `result`, `durationMs`, `thumbnail: NSImage?`.

`AgentActivityModel` là `@MainActor @Observable`, giữ `entries` (tối đa 500), `selectedID`, `filter`, `isPaused`, `pausedCount`, buffer `pending`, `paths`, `screenProvider`. Hành vi:

- `ingest(event)`: map `audit.appended` thành `ActivityEntry(audit:)`, `lease.changed` thành `ActivityEntry(lease:)`, `device.state.changed` thành `ActivityEntry(device:)`; nếu paused thì append vào buffer và cập nhật `pausedCount`, ngược lại append vào feed.
- `setPaused(false)`: flush buffer theo thứ tự, clear buffer.
- `loadHistory()`: đọc tối đa 200 dòng cuối của `paths.auditFile`, decode từng dòng `AuditEvent`, append; bỏ dòng hỏng, không throw.
- `append`: giữ ring 500 entry.
- Thumbnail: chỉ với entry operation có action bắt đầu `ui.`, gọi `screenProvider()?.screenshot` scale 0.2 JPEG, gán `NSImage`; lỗi bỏ qua, không chặn feed; chỉ chạy khi Settings bật `activityThumbnails`.

`AgentActivityView`: `Table` cột Time/Session/Action/Target/Result, selection theo entry; phần inspector bên phải hiển thị event, payload JSON, owner/lease/device, nút `Open Device` identifier `activity-open-device`; không tự takeover. Header có Picker filter All/Leases/Lifecycle/Operations, Button Pause identifier `activity-pause` + paused count, Button "Open Audit Log" dùng `NSWorkspace.activateFileViewerSelecting([paths.auditFile])`. Table identifier `activity-table`; row identifier `activity-row-<id>`; empty `activity-empty`; inspector `activity-inspector`. Không feed card, tag hay thumbnail tự chế.

`AppEnvironment` thêm `activity` và subscribe bus; `AppShell` case `.activity` dùng `AgentActivityView(model: environment.activity)`.

- [ ] **Step 4: Chạy để thấy pass**

```bash
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/ActivityUITests
```

Expected: `BUILD SUCCEEDED`; table hiện hoặc empty state, Pause tồn tại.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/OpenSimApp/Activity App/Sources/OpenSimApp/App/AppEnvironment.swift App/Sources/OpenSimApp/App/AppShell.swift Tests/OpenSimAppUITests/ActivityUITests.swift
git commit -m "feat(app): add agent activity feed and audit history"
```
---

### Task 10: Settings, capabilities và doctor

**Files:**
- Create: `App/Sources/OpenSimApp/Settings/SettingsView.swift`, `GeneralSettingsView.swift`, `DaemonSettingsView.swift`, `InputSettingsView.swift`, `CapabilitiesSettingsView.swift`, `DoctorModel.swift`
- Modify: `App/Sources/OpenSimApp/App/OpenSimApp.swift`, `App/Sources/OpenSimApp/App/AppSettings.swift`, `App/Sources/OpenSimApp/App/AppShell.swift`
- Test: `Tests/OpenSimAppUITests/SettingsUITests.swift`

**Interfaces:**
- Consumes: `DoctorReporting.doctorReport()`, operation `doctor_report`, `DoctorReport`, `BridgeCapabilities`, `HealthResponse`, `DaemonBootstrap.restart`, `OpenSimPaths.daemonLogFile`.
- Produces: `SettingsView`; `DoctorModel`; Settings scene; tab identifiers.

- [ ] **Step 1: Viết UI test thất bại**

```swift
import XCTest

final class SettingsUITests: XCTestCase {
    func testSettingsTabsAndDoctorReport() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.otherElements["settings-window"].waitForExistence(timeout: 10))
        for tab in ["general", "daemon", "input", "capabilities"] {
            XCTAssertTrue(app.buttons["settings-tab-\(tab)"].exists)
        }
        app.buttons["settings-tab-capabilities"].click()
        app.buttons["doctor-run-button"].click()
        let row = app.staticTexts["doctor-capability-render"]
        XCTAssertTrue(row.waitForExistence(timeout: 20) || app.staticTexts["doctor-error"].exists)
        XCTAssertTrue(app.buttons["doctor-run-button"].exists || app.buttons["doctor-retry"].exists)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/SettingsUITests
```

Expected: FAIL vì `settings-window` chưa tồn tại.

- [ ] **Step 3: Viết settings và doctor**

`SettingsView`: `TabView` native với bốn tab General/Daemon/Input/Capabilities, nội dung dùng `Form`/`GroupBox`; root `.accessibilityIdentifier("settings-window")`; tab identifier `settings-tab-general`, `settings-tab-daemon`, `settings-tab-input`, `settings-tab-capabilities`. Không custom tab bar, không frame cứng. Cửa sổ mở bằng gear trên titlebar hoặc `⌘,` qua `Settings` scene.

`GeneralSettingsView`: Toggle "Connect automatically" identifier `settings-auto-connect`; TextField "Client name" identifier `settings-client-name`; dòng trạng thái daemon read-only; Button "Reconnect" identifier `settings-reconnect`.

`DaemonSettingsView`: hiển thị version, protocol, pid, port, xcodeVersion, startedAt từ `HealthResponse`; CLI path phát hiện bởi `OpenSimCLILocator` và override trong `AppSettings`; Button "Choose" mở `NSOpenPanel` chọn executable và lưu override identifier `settings-daemon-choose-cli`; Button "Restart Daemon" identifier `settings-daemon-restart` gọi `connection.restartDaemon()`, hiển thị ProgressView và lỗi `settings-daemon-error`; Button "Reveal Daemon Log" dùng `NSWorkspace.activateFileViewerSelecting([paths.daemonLogFile])`, nếu file chưa có thì mở thư mục log.

`InputSettingsView`: Toggle "Capture Mac keyboard by default" identifier `settings-keyboard-default`; Toggle "Paste text with Command-V" identifier `settings-paste-command-v`; Picker `GestureMode.allCases` (`Direct`/`Pinch`/`Rotate`) identifier `settings-default-gesture`; Toggle "Activity thumbnails" identifier `settings-activity-thumbnails`; dòng capability `hid` từ health, nếu unavailable hiện text giải thích.

`DoctorModel.swift`:

```swift
@MainActor
@Observable
public final class DoctorModel {
    public enum State: Equatable {
        case idle
        case loading
        case loaded(DoctorReport)
        case failed(OpenSimError)
    }

    public private(set) var state: State = .idle
    private let environment: AppEnvironment

    public init(environment: AppEnvironment) { self.environment = environment }

    public func load() async {
        state = .loading
        do {
            if let doctor = environment.bridge.doctor {
                state = .loaded(try await doctor.doctorReport())
                return
            }
            guard let client = environment.connection.client else {
                throw OpenSimError.daemonUnavailable("Daemon is not connected")
            }
            let data = try await client.operation("doctor_report")
            state = .loaded(try OpenSimJSON.decoder().decode(DoctorReport.self, from: data))
        } catch let error as OpenSimError {
            state = .failed(error)
        } catch {
            state = .failed(.capabilityUnavailable("doctor"))
        }
    }
}
```

`CapabilitiesSettingsView`: Button "Run Doctor" identifier `doctor-run-button`; `.task` load lần đầu; loading identifier `doctor-loading`; error `ErrorStateView` identifier `doctor-error` với Retry `doctor-retry`; loaded hiển thị bảng capability `render`, `hid`, `accessibility`, `screenshot`, `video`, `watch`, `tv` với row identifier `doctor-capability-<tên>`, private API status, daemon health, disk free, device/runtime count, notes. Button "Copy JSON" ghi JSON report vào `NSPasteboard`. Không hiển thị token hay secret.

`OpenSimApp` thêm `Settings { SettingsView().environment(environment) }`. `AppSettings` thêm `keyboardCaptureDefault`, `pasteWithCommandV`, `defaultGestureMode`, `activityThumbnails`, `cliPathOverride`, tất cả lưu UserDefaults. `AppEnvironment` tạo `DaemonBootstrap(cliPathOverride: settings.cliPathOverride)`; đổi CLI path cần restart daemon hoặc reconnect.

- [ ] **Step 4: Chạy để thấy pass**

```bash
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/SettingsUITests
```

Expected: `BUILD SUCCEEDED`; Settings mở bằng `Cmd+,`; doctor pass hoặc error state có Retry.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/OpenSimApp/Settings App/Sources/OpenSimApp/App/AppSettings.swift App/Sources/OpenSimApp/App/OpenSimApp.swift Tests/OpenSimAppUITests/SettingsUITests.swift
git commit -m "feat(app): add settings capabilities and doctor"
```
---

### Task 11: Storage shell và Performance flag

**Files:**
- Create: `App/Sources/OpenSimApp/Shared/ServiceShellModel.swift`, `Storage/StorageShellView.swift`
- Modify: `App/Sources/OpenSimApp/App/AppShell.swift`
- Test: `Tests/OpenSimAppUITests/ServiceShellUITests.swift`

**Interfaces:**
- Consumes: `DaemonClient.probe(path:)`, `OpenSimError`, `AppTab`.
- Produces: `ServiceProbeResult`; `ServiceKind`; `ServiceShellModel`; `StorageShellView`.

- [ ] **Step 1: Viết UI test thất bại**

```swift
import XCTest

final class ServiceShellUITests: XCTestCase {
    func testStorageAndPerformanceShellsExposeServiceState() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }

        XCTAssertTrue(app.cells["sidebar-storage"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.cells["sidebar-performance"].exists)
        app.cells["sidebar-storage"].click()
        XCTAssertTrue(app.otherElements["storage-shell"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["storage-state"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["storage-retry"].exists)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/ServiceShellUITests
```

Expected: FAIL vì `storage-shell` chưa tồn tại.

- [ ] **Step 3: Viết probe và shell**

`ServiceProbeResult` đã tạo ở Task 2 với ba case `available`, `unavailable`, `failed(OpenSimError)`. Task 11 chỉ dùng lại, không định nghĩa lần hai.

`ServiceShellModel.swift`:

```swift
@MainActor
@Observable
public final class ServiceShellModel {
    public enum State: Equatable {
        case probing
        case unavailable
        case failed(OpenSimError)
        case ready
    }

    public enum Service: String, Sendable {
        case storage, performance

        var probePath: String {
            switch self {
            case .storage: return "/v1/storage/scans/00000000-0000-0000-0000-000000000000"
            case .performance: return "/v1/perf/devices"
            }
        }

        var title: String {
            switch self {
            case .storage: return "Storage"
            case .performance: return "Performance"
            }
        }

        var unavailableMessage: String {
            switch self {
            case .storage:
                return "Storage service is not connected. This daemon build does not expose storage endpoints. Connect a daemon built with Plan 5 to load real scan data. No mock data is shown."
            case .performance:
                return "Performance service is not connected. This daemon build does not expose metrics endpoints. Connect a daemon built with Plan 5 to load real samples. No mock data is shown."
            }
        }
    }

    public let service: Service
    public private(set) var state: State = .probing
    private let clientProvider: () -> DaemonClient?

    public init(service: Service, clientProvider: @escaping () -> DaemonClient?) {
        self.service = service
        self.clientProvider = clientProvider
    }

    public func probe() async {
        guard let client = clientProvider() else {
            state = .failed(.daemonUnavailable("Daemon is not connected"))
            return
        }
        state = .probing
        switch await client.probe(path: service.probePath) {
        case .available:
            state = .ready
        case .unavailable:
            state = .unavailable
        case .failed(let error):
            state = .failed(error)
        }
    }
}
```

`StorageShellView`:

```swift
struct StorageShellView: View {
    @State private var model: ServiceShellModel

    init(clientProvider: @escaping () -> DaemonClient?) {
        _model = State(initialValue: ServiceShellModel(service: .storage, clientProvider: clientProvider))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Storage")
                .font(.title2.weight(.semibold))
            Text("Disk usage, scan results and clean plans are owned by the storage service.")
                .foregroundStyle(.secondary)
            switch model.state {
            case .probing:
                LoadingStateView("Checking storage service", identifier: "storage-probing")
            case .unavailable:
                ContentUnavailableView(
                    "Storage service is not connected",
                    systemImage: "internaldrive",
                    description: Text(model.service.unavailableMessage)
                )
                .accessibilityIdentifier("storage-unavailable")
                Text(model.service.unavailableMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("storage-state")
                Button("Retry") { Task { await model.probe() } }
                    .accessibilityIdentifier("storage-retry")
            case .failed(let error):
                ErrorStateView(error: error, identifier: "storage-state") {
                    Task { await model.probe() }
                }
                Button("Retry") { Task { await model.probe() } }
                    .accessibilityIdentifier("storage-retry")
            case .ready:
                EmptyStateView(
                    title: "No storage scan yet",
                    message: "The storage service is connected. Scan and clean controls arrive with the Plan 5 view.",
                    systemImage: "internaldrive",
                    identifier: "storage-empty"
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("storage-shell")
        .task { await model.probe() }
    }
}
```

`AppShell` case `.storage` dùng `StorageShellView(clientProvider: { environment.connection.client })`. Performance không có case view trong Plan 4: `AppFeature.performance=false`, sidebar và detail không tồn tại; Plan 5 thay bằng `PerformanceTabView` và bật flag.

- [ ] **Step 4: Chạy để thấy pass**

```bash
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/ServiceShellUITests
```

Expected: `BUILD SUCCEEDED`; Storage hiện `unavailable` với message thật từ probe; sidebar không có Performance khi flag tắt; không có số liệu giả.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/OpenSimApp/Shared/ServiceShellModel.swift App/Sources/OpenSimApp/Storage App/Sources/OpenSimApp/Performance App/Sources/OpenSimApp/App/AppShell.swift Tests/OpenSimAppUITests/ServiceShellUITests.swift
git commit -m "feat(app): add storage and performance service shells"
```
---

### Task 12: Accessibility, keyboard navigation và final UI suite

**Files:**
- Modify: toàn bộ view có control; `TakeControlSheet.swift`, `DevicesView.swift`, `DeviceInspectorView.swift`, `RuntimesView.swift`, `SettingsView.swift`, `QuickSwitchPalette.swift`
- Test: `Tests/OpenSimAppUITests/AccessibilityUITests.swift`

**Interfaces:**
- Consumes: SwiftUI accessibility modifiers, `@FocusState`.
- Produces: accessibility identifier/label ổn định; final UI suite.

- [ ] **Step 1: Viết UI test thất bại**

```swift
import XCTest

final class AccessibilityUITests: XCTestCase {
    func testControlsExposeLabelsAndStateText() throws {
        continueAfterFailure = false
        let app = TestEnvironment.launchApp()
        addTeardownBlock { app.terminate() }

        for tab in ["sidebar-devices", "sidebar-runtimes", "sidebar-storage", "sidebar-activity"] {
            let row = app.cells[tab]
            XCTAssertTrue(row.waitForExistence(timeout: 20))
            XCTAssertFalse(row.label.isEmpty)
        }
        XCTAssertFalse(app.cells["sidebar-performance"].exists)
        let firstRow = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH 'device-row-'")).firstMatch
        if firstRow.exists {
            XCTAssertFalse(firstRow.label.isEmpty)
        }
        app.cells["sidebar-storage"].click()
        XCTAssertTrue(app.staticTexts["storage-state"].waitForExistence(timeout: 20))
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/AccessibilityUITests
```

Expected: FAIL vì một số control thiếu label/identifier.

- [ ] **Step 3: Hoàn thiện accessibility và focus**

- Sidebar `List` row có label "Devices", "Runtimes", "Storage", "Agent Activity"; trạng thái chọn native; Performance không xuất hiện khi flag tắt.
- `DevicesView`/`DeviceInspectorView` label gồm name, state, lease owner; state luôn có text; primary action đọc được state hiện tại.
- Toolbar button có `help` và `accessibilityLabel`; keyboard toggle có label "Capture Mac keyboard", state on/off.
- `TakeControlSheet` dùng `@FocusState` đặt Cancel làm focus đầu tiên, Cancel có `.keyboardShortcut(.cancelAction)`, Take Control có role destructive và label nêu hậu quả.
- `QuickSwitchPalette` search field focus khi mở; row có label name + state + owner; arrow/return/escape hoạt động; `Esc` đóng panel.
- Settings tab button có label; Capabilities table row có label `render: available` dạng text, không chỉ màu.
- Storage state có text `storage-state`; lỗi có code và recovery; màu chỉ là phụ.
- Tất cả icon-only button có `accessibilityLabel`; không dùng màu làm tín hiệu duy nhất.
- `DeviceWindowRoot` đặt `.accessibilityIdentifier("device-window")`; `SimulatorScreenContainerView` có label "Simulator screen for <device>" và value state.

- [ ] **Step 4: Chạy toàn bộ UI suite**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests
```

Expected: tất cả test pass, trừ test skip có lý do khi thiếu device booted hoặc daemon. Không có crash, không có treo quá 60 giây mỗi test.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/OpenSimApp Tests/OpenSimAppUITests/AccessibilityUITests.swift
git commit -m "feat(app): complete accessibility and ui suite"
```
---
## Manual Visual Checklist

Chạy app bằng `open App/OpenSim.xcodeproj`, scheme `OpenSim`, hoặc `xcodebuild build` rồi mở `OpenSim.app`. Kiểm tra trên cửa sổ nhỏ nhất 980x640, màn Retina và một lần với Reduce Motion. Không dùng Chrome.

| Màn hình | Trạng thái cần xem | Tiêu chí đạt |
|---|---|---|
| Main window | Loading, loaded, empty, daemon disconnected | Sidebar không nhảy layout; status có text; Retry rõ; không màu-only |
| Devices table | Nhiều platform/runtime, search, lease owner | Table native; search lọc ngay; row không có button/badge lặp; booted state đọc được |
| Device inspector | Booted, Shutdown, Runtime missing | Preview đúng tỉ lệ; CTA đổi theo state; metadata đủ runtime/screen/last boot/agent |
| New Simulator | Valid, tên trùng, runtime thiếu | Sheet native; Create disabled đúng; tạo xong chọn row Shutdown; count cập nhật |
| Runtimes | Installed, not installed, installing, error | Row theo version; Install/Cancel/Remove rõ; Add Runtime Download/From File; device chờ runtime chuyển Shutdown |
| Device window booted | Portrait, landscape, zoom 50/100/200 | Screen fit, không cắt; toolbar không tràn; rotate đổi hướng presentation |
| Device window shutdown | Boot prompt | Nút Boot rõ; sau boot screen tự xuất hiện; lỗi render có banner |
| Lease conflict | Banner, Take Control, sheet | Owner và hạn lease đúng; Cancel focus trước; takeover xong banner biến mất |
| Input | Tap, long press, swipe, drag, pinch, rotate, scroll, type, Cmd+V | Fixture phản hồi đúng; không gửi input khi chưa giữ lease; lỗi có banner |
| Quick switch | Cmd+K, search, arrow, Return, Esc | Panel nổi trên cửa sổ hiện tại; mở đúng device; không mở trùng cửa sổ |
| Menu bar extra | Có device booted, agent lease | Danh sách đúng; Open/Shut Down hoạt động; status khớp main window |
| Agent activity | Empty, có event, paused | Table cập nhật realtime; pause giữ buffer; inspector/payload đọc được; audit mở được |
| Settings general/daemon | Connected, disconnected, restart | Không lộ token; restart có progress; lỗi có recovery |
| Settings input | Capability hid available/unavailable | Toggle phản ánh đúng; unavailable giải thích rõ |
| Settings capabilities | Loading, loaded, error | Bảng đủ 7 capability; doctor error có Retry; JSON copy được |
| Storage shell | Probing, unavailable, error, empty | Không có số liệu giả; message nêu Plan 5; Retry hoạt động |
| Performance hidden | Flag tắt | Không có row Performance, không có shell/empty state; Plan 5 bật sau khi nối metrics |
| VoiceOver | Sidebar, toolbar, lease sheet, palette | Đọc đúng label/state; focus không kẹt; Cancel đọc trước Take Control |

Ghi kết quả từng mục vào PR description hoặc task log. Mục fail phải sửa trước khi đánh dấu Exit criteria.
## Spec Coverage

| Mục spec | Nội dung | Task |
|---|---|---|
| 5.2 | App kết nối daemon, auto-start 5 giây, render in-process, daemon chết có Retry | 2, 4 |
| 5.3 | Session, lease control, heartbeat, takeover grace, banner | 2, 7 |
| 5.4 | Private API chỉ trong Bridge; app gate capability, không crash | 2, 4, 5 |
| 5.5 | Boot flow, agent tranh quyền, người dùng take control | 3, 7 |
| 6 | Device, Lease, Session, AuditEvent hiển thị đúng domain | 2, 3, 7, 9 |
| 9.1 | Sidebar native; Devices table/inspector, Runtimes, Storage, Activity; Performance ẩn | 1, 3, 3A, 9, 11 |
| 9.2 | Device window, toolbar, gesture, nhiều cửa sổ, Cmd+K, menu bar, đóng cửa sổ release lease | 4, 5, 6, 7, 8 |
| 9.3 | Không mock, native components, capability banner, destructive confirm, accessibility | 1, 3, 3A, 9, 10, 11, 5, 7, 12 |
| 9.4 | New Simulator: name/type/runtime, validation, tạo Shutdown | 3 |
| 9.5 | Runtimes theo version, Add Runtime Download/From File, delete guard | 3A |
| 9.6 | Settings scene native, 4 tab, Doctor loading/error/retry | 10 |
| 9.8 | Performance flag false trong Plan 4 | 1, 11 |
| 12 | App Sandbox tắt, Hardened Runtime, không lộ token, không shell string | 1, 2, 10 |
| 13 | Error có code/recovery, OSLog subsystem, audit feed | 2, 9, 10 |
| 14.3 | XCUITest launch/table/new device/runtimes/window/lease/settings; checklist thủ công | 1, 3, 3A, 9, 10, 11, 4, 7, 8, 12 |
| 16 Plan 4 | App macOS, device windows, full gesture, quick switch, New Device, Runtimes, Settings, activity | tất cả |
| 17.1 | Acceptance 9-12: mở app, lease gate, New Device, Runtimes, Settings | 1, 3, 3A, 9, 10, 4, 5, 7, 8 |
| 18 | Private API đổi hoặc thiếu thì capability gate + fallback, không crash | 2, 4, 5 |
## Exit Criteria

- `xcodegen generate --spec App/project.yml --project App` tạo `App/OpenSim.xcodeproj`; `xcodebuild build` thành công với Swift 6 strict concurrency.
- Toàn bộ `Tests/OpenSimAppUITests` pass hoặc skip có lý do rõ; không có test bị disable vĩnh viễn.
- App mở main window, load device thật từ daemon, boot/shutdown qua daemon operation, mở nhiều cửa sổ device, render `SimulatorScreenView`, chỉ nhận input khi giữ lease control còn hạn; harness giữ lease thì input bị chặn với `lease_required`.
- New Simulator tạo device `Shutdown`, validate tên trùng/runtime thiếu; Runtimes cài version cũ/import `.dmg`, cancel progress, delete bị chặn khi còn device; New Device picker cập nhật version đã cài.
- Lease conflict hiện banner đúng owner; Take Control qua sheet xác nhận, hoàn tất sau grace period; đóng cửa sổ release lease; heartbeat 30 giây.
- `Cmd+K` mở palette từ bất kỳ cửa sổ nào, mở/focus đúng device; menu bar extra boot/shutdown/switch được.
- Agent activity đọc audit history và SSE, pause/resume đúng; không có thumbnail giả.
- Settings là `Settings` scene native, mở bằng gear/`⌘,`, bốn tab; doctor chạy direct hoặc fallback; capability table đủ render/hid/a11y/screenshot/video/watch/tv.
- Storage shell phản ánh service thật, error có Retry, không mock; Performance ẩn hoàn toàn khi `AppFeature.performance=false`, không có shell/tab chết.
- UI chỉ dùng native components; không còn `StorageCategoryChart`, `DeviceCardView`, `StatusBadge`, custom Settings tab bar hay `.font(.system(size:))` trong app.
- `grep -R "simctl\|SimDevice\|CoreSimulator" App/Sources/OpenSimApp` không có kết quả; app không có lifecycle path thứ hai.
- `grep -R "Mock\|FakeDevice\|SampleDevice" App/Sources/OpenSimApp` không có kết quả; test support chỉ nằm dưới `Tests/OpenSimAppUITests`.
- Không đổi tên hay signature `SimulatorScreenView`; chỉ có extension `isReadyForInput`.
- Manual visual checklist hoàn tất, ghi rõ mục pass/fail và đã sửa mọi mục fail.
