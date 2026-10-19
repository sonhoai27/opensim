# OpenSim Plan 10 — Android Emulator

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm Android Emulator (AVD) làm platform thứ hai của OpenSim: cùng daemon, operation catalog, lease/audit, CLI, MCP và macOS app. Apple path không đổi.

**Architecture:** `OpenSimAndroid` là adapter độc lập, không chạm private API Apple. Nó dùng `emulator` + `avdmanager` cho lifecycle, `adb` cho app/log/input fallback/uiautomator, và emulator gRPC `EmulatorController` cho live screen/touch. `OpenSimDaemon` route operation theo `Device.platform`; CLI/MCP/UI giữ nguyên bề mặt lệnh.

**Tech Stack:** Swift 6, Foundation `Process`, `XMLParser`, `OpenSimCore`, `OpenSimDaemon`, app macOS native của Plan 4; `grpc-swift` 2.x + generated protobuf stubs cho emulator gRPC; adb/emulator/avdmanager/sdkmanager; JDK 17+.

**Spec:** `docs/superpowers/specs/2026-10-19-open-simulator-design.md`

**Depends on:** Plan 2 (`DisplaySurface`/selector contracts), Plan 3 (operation catalog, daemon, lease), Plan 4 (app shell). Plan 10 is additive; it can run after Plan 4 and in parallel with Plan 5/6, or after Plan 7 if Android is not in the Apple release.

## Global Constraints

- Không sửa hành vi Apple hiện có. `OpenSimBridge` vẫn là boundary private API duy nhất; Android code không import CoreSimulator/SimulatorKit.
- Không tự tải Android SDK, system image, JDK hoặc license. Mọi thao tác cài đặt cần owner consent rõ ràng.
- Không dùng shell string. Mọi process (`adb`, `emulator`, `avdmanager`, `sdkmanager`) dùng argument array qua `Process`.
- Không xoá AVD/system image khi đang chạy hoặc đang được AVD khác dùng. Delete cần confirm và kiểm tra in-use ngay trước khi xoá.
- Android Emulator chỉ chạy trên macOS host trong plan này; không hỗ trợ Android physical devices, Genymotion, BlueStacks.
- Loopback only: emulator gRPC bind `127.0.0.1`; adb server theo mặc định của Android SDK.
- Không log token/console auth; không đưa screenshot/log lên mạng.
- Native UI only: không đưa card/chart/custom style mới; Android UI dùng chung shell/Table/List/Form của Plan 4.
- Không đổi tên `Device`, `Runtime`, `DeviceID`, `Platform` ngoài việc thêm `Platform.android`.
- Văn xuôi tiếng Việt; code/type/identifier/command tiếng Anh; không CJK; không placeholder.

## Environment Reference

Máy tham chiếu đã có:

- Android SDK: `~/Library/Android/sdk`
- `adb`: `~/Library/Android/sdk/platform-tools/adb`
- `emulator`: `~/Library/Android/sdk/emulator/emulator`
- Java: OpenJDK/JBR 17.0.9
- `avdmanager`/`sdkmanager`: không có trên `PATH`; locator phải tìm dưới `cmdline-tools/latest/bin` hoặc `cmdline-tools/<version>/bin`.

Không giả định có AVD/system image sẵn. Integration test phải `XCTSkip` với `BLOCKED: no Android AVD` nếu thiếu; release Apple không bị chặn bởi Plan 10.

## File Structure

| File | Trách nhiệm | Task |
|---|---|---|
| `Package.swift` | Thêm target `OpenSimAndroid` và dependency gRPC | 1, 6 |
| `Sources/OpenSimAndroid/AndroidSDK.swift` | Locator SDK/JDK/adb/emulator/avdmanager/sdkmanager | 1 |
| `Sources/OpenSimAndroid/AndroidCommandRunner.swift` | Process runner, timeout, output capture | 1 |
| `Sources/OpenSimAndroid/AndroidAVDService.swift` | List/create/boot/shutdown/erase/delete AVD | 2 |
| `Sources/OpenSimAndroid/AndroidDeviceService.swift` | Map AVD/serial sang `Device` | 2 |
| `Sources/OpenSimAndroid/AndroidAppService.swift` | install/uninstall/launch/terminate/list/info | 3 |
| `Sources/OpenSimAndroid/AndroidLogService.swift` | logcat tail/stream | 3 |
| `Sources/OpenSimAndroid/AndroidScreenService.swift` | screencap fallback + gRPC stream | 4, 6 |
| `Sources/OpenSimAndroid/AndroidInputService.swift` | adb input fallback + gRPC touch/key | 4, 6 |
| `Sources/OpenSimAndroid/AndroidAccessibilityService.swift` | uiautomator XML → `UIElement` | 5 |
| `Sources/OpenSimAndroid/AndroidSystemImageService.swift` | sdkmanager list/install/uninstall | 7 |
| `Sources/OpenSimAndroid/EmulatorGRPCClient.swift` | Generated `EmulatorController` transport | 6 |
| `Sources/OpenSimAndroid/Generated/` | Checked-in protobuf/gRPC Swift stubs | 6 |
| `Sources/OpenSimAndroid/AndroidPlatformAdapter.swift` | Compose services into platform adapter | 8 |
| `Sources/OpenSimDaemon/Platforms/PlatformDoctor.swift` | Compose Apple + Android doctor | 1, 8 |
| `Sources/OpenSimAndroid/Catalog/AndroidOperations.swift` | `android_avd_*`, `android_system_image_*` | 8 |
| `Sources/OpenSimDaemon/Platforms/PlatformRouter.swift` | Route operation theo platform/device | 8 |
| `App/Sources/OpenSimApp/Devices/NewDeviceModel.swift` | Platform + Android device type | 9 |
| `App/Sources/OpenSimApp/Runtimes/RuntimeModel.swift` | Android system images | 9 |
| `App/Sources/OpenSimApp/Windows/DeviceWindowRoot.swift` | Android screen/input/toolbar | 9 |
| `App/Sources/OpenSimApp/Settings/DaemonSettingsView.swift` | Android SDK path/status | 9 |
| `App/Sources/OpenSimApp/Settings/CapabilitiesSettingsView.swift` | Android doctor rows | 9 |
| `Sources/OpenSimAndroid/AndroidStorageService.swift` | AVD/system-image storage items | 10 |
| `Sources/OpenSimAndroid/AndroidMetricsService.swift` | Android process/adb metrics | 10 |
| `Tests/OpenSimAndroidTests/` | SDK/AVD/XML/selector parser tests | 1–7 |
| `Tests/IntegrationTests/AndroidIntegrationTests.swift` | Real AVD smoke/integration | 11 |
| `Fixtures/AndroidFixture/` | Fixture app source/APK | 11 |
| `Scripts/android/create-test-avd.sh` | Owner-approved AVD setup, no auto-download | 11 |

## Build and Test Commands

```bash
swift build
swift test --filter OpenSimAndroidTests
OPENSIM_INTEGRATION=1 swift test --filter AndroidIntegrationTests
```

UI tests use the same `App` scheme as Plan 4:

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/AndroidUITests
```

## Tasks

### Task 1: Android SDK locator, command runner và doctor

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidSDK.swift`, `Sources/OpenSimAndroid/AndroidCommandRunner.swift`, `Tests/OpenSimAndroidTests/AndroidSDKTests.swift`
- Modify: `Package.swift`, `Sources/OpenSimCore/Domain/Doctor.swift` (add Android capability fields), `Sources/OpenSimDaemon/Platforms/PlatformDoctor.swift` (create), `Sources/OpenSimDaemon/DaemonRunner.swift`, `Sources/OpenSimCLI/Runtime/CLIRuntime.swift`

**Interfaces:**
- Consumes: `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `JAVA_HOME`, filesystem.
- Produces: `AndroidSDK.detect()`, `AndroidSDK.adb`, `.emulator`, `.avdmanager`, `.sdkmanager`, `.java`; `AndroidCommandRunner.run(_:timeout:)`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimAndroid

final class AndroidSDKTests: XCTestCase {
    func testDetectsSDKFromEnvironmentFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let platformTools = root.appendingPathComponent("platform-tools", isDirectory: true)
        try FileManager.default.createDirectory(at: platformTools, withIntermediateDirectories: true)
        let adb = platformTools.appendingPathComponent("adb")
        try Data().write(to: adb)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adb.path)
        let emulatorDir = root.appendingPathComponent("emulator", isDirectory: true)
        try FileManager.default.createDirectory(at: emulatorDir, withIntermediateDirectories: true)
        let emulator = emulatorDir.appendingPathComponent("emulator")
        try Data().write(to: emulator)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: emulator.path)

        let sdk = try AndroidSDK.detect(environment: ["ANDROID_HOME": root.path], fileManager: .default)
        XCTAssertEqual(sdk.root.path, root.path)
        XCTAssertEqual(sdk.adb.path, adb.path)
    }

    func testMissingSDKThrowsWithRecovery() throws {
        let emptyHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)
        XCTAssertThrowsError(try AndroidSDK.detect(environment: [:], homeDirectory: emptyHome, fileManager: .default)) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, "android_sdk_not_found")
        }
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter OpenSimAndroidTests.AndroidSDKTests
```

Expected: FAIL vì module/type chưa tồn tại.

- [ ] **Step 3: Viết locator và runner**

```swift
public struct AndroidSDK: Sendable, Equatable {
    public let root: URL
    public let adb: URL
    public let emulator: URL
    public let avdmanager: URL?
    public let sdkmanager: URL?
    public let java: URL?

    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> AndroidSDK
}
```

`detect` thứ tự root: `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `~/Library/Android/sdk`. `adb` tại `platform-tools/adb`; `emulator` tại `emulator/emulator`; cmdline tools tìm `cmdline-tools/latest/bin/avdmanager|sdkmanager`, sau đó version directory bất kỳ. Thiếu `adb` hoặc `emulator` ném `android_sdk_not_found` với recovery nêu đường dẫn cần cấu hình. Java đọc `JAVA_HOME/bin/java` hoặc `/usr/bin/java`; version parse qua `java -version`.

`AndroidCommandRunner`:

```swift
public struct AndroidCommand: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]?
    public var timeout: Duration
}

public struct CommandOutput: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: String
}

public protocol AndroidCommandRunning: Sendable {
    func run(_ command: AndroidCommand) async throws -> CommandOutput
}
```

Không dùng `sh -c`. Timeout mặc định 30 giây; `adb wait-for-device` dùng timeout riêng 120 giây. Capture stdout/stderr, trả `CommandOutput(exitCode:stdout:stderr:)`.

Doctor thêm:

```swift
public struct AndroidDoctorReport: Codable, Sendable, Equatable {
    public var sdkPath: String?
    public var adbVersion: String?
    public var emulatorVersion: String?
    public var avdmanagerAvailable: Bool
    public var sdkmanagerAvailable: Bool
    public var javaVersion: String?
    public var avdCount: Int
    public var systemImageCount: Int
}
```

- [ ] **Step 4: Chạy test xanh**

```bash
swift test --filter OpenSimAndroidTests.AndroidSDKTests
swift build
```

Expected: PASS 2 test; build có target `OpenSimAndroid`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/OpenSimAndroid Sources/OpenSimCore/Domain/Doctor.swift Sources/OpenSimDaemon/Platforms/PlatformDoctor.swift Sources/OpenSimDaemon/DaemonRunner.swift Sources/OpenSimCLI/Runtime/CLIRuntime.swift Tests/OpenSimAndroidTests/AndroidSDKTests.swift
git commit -m "feat(android): detect SDK and expose doctor"
```
---

### Task 2: AVD catalog và lifecycle

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidAVDService.swift`, `AndroidDeviceService.swift`
- Test: `Tests/OpenSimAndroidTests/AndroidAVDTests.swift`

**Interfaces:**
- Consumes: `AndroidSDK`, `AndroidCommandRunning`, `Device`, `DeviceID`, `Platform.android`.
- Produces: `AndroidAVDService.list()`, `.create(_:)`, `.boot(name:grpcPort:)`, `.shutdown(name:)`, `.erase(name:)`, `.delete(name:)`; `AndroidDeviceService.listDevices()`.

- [ ] **Step 1: Viết test parse/list**

```swift
final class AndroidAVDTests: XCTestCase {
    func testParsesAVDNamesAndConfig() throws {
        let sdk = try makeFakeSDK(avdOutput: "Pixel_9_API_36\nTablet_API_35\n")
        let service = AndroidAVDService(sdk: sdk, runner: FakeRunner(outputs: [
            "Pixel_9_API_36": "image.sysdir.1=system-images/android-36/google_apis/arm64-v8a/\nAvdId=Pixel_9_API_36\n"
        ]))
        let avds = try await service.list()
        XCTAssertEqual(avds.map(\.name), ["Pixel_9_API_36", "Tablet_API_35"])
        XCTAssertEqual(avds[0].apiLevel, 36)
        XCTAssertEqual(avds[0].abi, "arm64-v8a")
    }
}
```

- [ ] **Step 2: Viết lifecycle**

`AndroidAVDService`:

```swift
public actor AndroidAVDService {
    public func list() async throws -> [AndroidAVD]
    public func create(name: String, deviceType: String, systemImage: String) async throws -> AndroidAVD
    public func boot(name: String, grpcPort: Int, headless: Bool) async throws -> AndroidAVD
    public func shutdown(name: String) async throws
    public func erase(name: String) async throws
    public func delete(name: String) async throws
}
```

- `list`: chạy `emulator -list-avds`; đọc `~/.android/avd/<name>.avd/config.ini` để lấy `image.sysdir.1`, `abi.type`, `tag.id`, `hw.device.name`; state từ `adb devices -l` (`emulator-<port>`) và process table.
- `create`: `avdmanager create avd -n <name> -k <systemImage> -d <deviceType> --force`; không tự cài image; nếu image thiếu trả `android_image_unavailable`.
- `boot`: `emulator -avd <name> -grpc 127.0.0.1:<port> -no-snapshot-save -no-boot-anim -port <consolePort>`; headless thêm `-no-window`; chờ `adb -s emulator-<port> wait-for-device` và `getprop sys.boot_completed == 1` tối đa 120 giây.
- `shutdown`: `adb -s <serial> emu kill`; fallback kill process đã đăng ký; chờ process exit.
- `erase`: shutdown trước, rồi `emulator -avd <name> -wipe-data`; không xoá config.
- `delete`: chặn nếu running/in-use; `avdmanager delete avd -n <name>`; xác nhận đã biến mất khỏi `-list-avds`.

`AndroidDeviceService.listDevices()` map AVD đang chạy thành `Device`:

```swift
Device(
    id: DeviceID(rawValue: "android:\(avd.name)"),
    name: avd.name,
    platform: .android,
    deviceType: avd.deviceType,
    runtime: RuntimeID(rawValue: avd.systemImage),
    state: avd.state == .running ? .booted : .shutdown,
    isAvailable: true,
    dataPath: avd.dataPath,
    lastBootedAt: avd.lastBootedAt
)
```

- [ ] **Step 3: Chạy test xanh + integration skip**

```bash
swift test --filter OpenSimAndroidTests.AndroidAVDTests
OPENSIM_INTEGRATION=1 swift test --filter AndroidIntegrationTests
```

Expected: unit PASS; integration SKIP với `BLOCKED: no Android AVD` nếu máy chưa có AVD.

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenSimAndroid/AndroidAVDService.swift Sources/OpenSimAndroid/AndroidDeviceService.swift Tests/OpenSimAndroidTests/AndroidAVDTests.swift
git commit -m "feat(android): add AVD lifecycle"
```
---

### Task 3: adb app/log services và lifecycle fallback

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidAppService.swift`, `AndroidLogService.swift`
- Test: `Tests/OpenSimAndroidTests/AndroidAdbTests.swift`

**Interfaces:**
- Consumes: `AndroidCommandRunning`, `AndroidSDK.adb`, `AppInfo`, `LogEntry`.
- Produces: `AndroidAppService.install/uninstall/launch/terminate/listApps/info`, `AndroidLogService.tail/stream`.

- [ ] **Step 1: Test command construction**

```swift
func testInstallUsesArgumentArray() async throws {
    let runner = RecordingRunner()
    let service = AndroidAppService(adb: URL(fileURLWithPath: "/tmp/adb"), runner: runner)
    _ = try await service.install(serial: "emulator-5554", apkPath: "/tmp/app.apk", reinstall: true)
    XCTAssertEqual(runner.last?.arguments, ["-s", "emulator-5554", "install", "-r", "/tmp/app.apk"])
}
```

- [ ] **Step 2: Implement**

- `list`: `adb -s <serial> shell pm list packages -3`; map package name.
- `install`: `adb -s <serial> install -r <path>`; reject non-`.apk` path via allowlist.
- `uninstall`: `adb -s <serial> uninstall <bundleID>`.
- `launch`: `adb -s <serial> shell am start -n <package>/<activity>`; resolve activity qua `cmd package resolve-activity --brief`.
- `terminate`: `adb -s <serial> shell am force-stop <package>`.
- `info`: `adb shell dumpsys package <package>` parse versionName/versionCode/label.
- `log`: `adb -s <serial> logcat -v threadtime` stream; tail dùng `-t <limit>` và cursor timestamp.
- Không dùng `Runtime.exec`/shell string.

- [ ] **Step 3: Chạy test xanh**

```bash
swift test --filter OpenSimAndroidTests.AndroidAdbTests
```

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenSimAndroid/AndroidAppService.swift Sources/OpenSimAndroid/AndroidLogService.swift Tests/OpenSimAndroidTests/AndroidAdbTests.swift
git commit -m "feat(android): add app and log services"
```
---

### Task 4: Screen và input fallback qua adb

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidScreenService.swift`, `AndroidInputService.swift`
- Test: `Tests/OpenSimAndroidTests/AndroidInputTests.swift`

**Interfaces:**
- Consumes: `ScreenControlling`, `InputControlling`, `ScreenInfo`, `Screenshot`, `Point`, `Key`, `KeyModifiers`, `HardwareButton`.
- Produces: `AndroidScreenService.screenshot`, `.screenInfo`; `AndroidInputService.tap/swipe/longPress/drag/scroll/type/key`.

- [ ] **Step 1: Test serial và screenshot**

```swift
func testScreenshotUsesExecOut() async throws {
    let runner = RecordingRunner(stdout: Data([0x89, 0x50, 0x4E, 0x47]))
    let service = AndroidScreenService(adb: URL(fileURLWithPath: "/tmp/adb"), runner: runner)
    _ = try await service.screenshot(on: DeviceID(rawValue: "android:Pixel_9_API_36"), format: .png, scale: 1, quality: 100)
    XCTAssertEqual(runner.last?.arguments, ["-s", "emulator-5554", "exec-out", "screencap", "-p"])
}
```

- [ ] **Step 2: Implement**

- Serial resolve: `android:<avdName>` → running emulator serial từ `AndroidAVDService`/adb; không đoán `emulator-5554`.
- Screen: `adb -s <serial> exec-out screencap -p`; trả PNG data; `screenInfo` lấy `wm size`/`wm density` (hoặc gRPC status).
- Tap/swipe/long-press/drag: `adb shell input tap x y`, `swipe x1 y1 x2 y2 durationMs`; long press dùng swipe cùng điểm với duration; drag dùng swipe duration dài.
- Type: `adb shell input text <escaped>`; escape khoảng trắng thành `%s`, shell metacharacters không đi qua shell vì argument array nhưng adb shell vẫn cần escape đúng; dùng helper `AndroidInputText.escape`.
- Key/button: `input keyevent <code>`; map Home/Back/Overview/Power/Volume/Rotate.
- Scroll: `input swipe` trong vùng screen.
- Multi-touch/pinch/rotate: adb fallback trả `capability_unavailable("android-grpc")`; không gửi gesture sai. gRPC Task 6 mới hỗ trợ.
- Screenshot fallback polling dùng Task 10 app render; tần suất thấp, doctor ghi rõ.

- [ ] **Step 3: Chạy test xanh**

```bash
swift test --filter OpenSimAndroidTests.AndroidInputTests
```

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenSimAndroid/AndroidScreenService.swift Sources/OpenSimAndroid/AndroidInputService.swift Tests/OpenSimAndroidTests/AndroidInputTests.swift
git commit -m "feat(android): add adb screen and input fallback"
```
---

### Task 5: Accessibility tree từ uiautomator

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidAccessibilityService.swift`, `Sources/OpenSimAndroid/AndroidUIAutomatorXML.swift`
- Test: `Tests/OpenSimAndroidTests/AndroidAccessibilityTests.swift`, fixture XML.

**Interfaces:**
- Consumes: `AccessibilityReading.find`, `UIElement`, `ElementSelector`.
- Produces: `AndroidAccessibilityService.find(on:selector:)`, `.tree(on:maxDepth:)`.

- [ ] **Step 1: Test parse XML fixture**

Fixture `Tests/OpenSimAndroidTests/Fixtures/window_dump.xml` contains:

```xml
<hierarchy rotation="0">
  <node index="0" text="" resource-id="" class="android.widget.FrameLayout" package="dev.opensim.fixture" content-desc="" clickable="false" bounds="[0,0][1080,2400]">
    <node index="0" text="Login" resource-id="dev.opensim.fixture:id/login" class="android.widget.Button" package="dev.opensim.fixture" content-desc="login-button" clickable="true" bounds="[40,200][400,280]" />
  </node>
</hierarchy>
```

```swift
func testParsesBoundsAndIdentifiers() throws {
    let tree = try AndroidUIAutomatorXML.parse(Data(fixture.utf8))
    let button = try XCTUnwrap(tree.first { $0.identifier == "dev.opensim.fixture:id/login" })
    XCTAssertEqual(button.label, "Login")
    XCTAssertEqual(button.frame, Rect(x: 40, y: 200, width: 360, height: 80))
    XCTAssertTrue(button.enabled)
}
```

- [ ] **Step 2: Implement**

- Chạy `adb -s <serial> shell uiautomator dump /dev/tty`; nếu output có preamble, cắt từ `<hierarchy`.
- Parse `XMLParser`; attributes: `text`, `resource-id`, `content-desc`, `class`, `package`, `clickable`, `enabled`, `bounds`; build parent/children.
- Selector mapping: `id` match resource-id (allow suffix after `:id/`), `label` match text/content-desc, `text` match text, `role` match class suffix.
- `find` trả element; tap dùng center; nếu bounds rỗng bỏ qua.
- uiautomator chậm: timeout 10 giây; retry 1 lần khi dump lỗi; không cache lâu hơn 500ms.
- Không có fallback tree; thiếu uiautomator trả `a11y_unavailable`.

- [ ] **Step 3: Chạy test xanh**

```bash
swift test --filter OpenSimAndroidTests.AndroidAccessibilityTests
```

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenSimAndroid/AndroidAccessibilityService.swift Sources/OpenSimAndroid/AndroidUIAutomatorXML.swift Tests/OpenSimAndroidTests/AndroidAccessibilityTests.swift Tests/OpenSimAndroidTests/Fixtures/window_dump.xml
git commit -m "feat(android): add uiautomator accessibility"
```
---

### Task 6: Emulator gRPC cho live screen và multi-touch

**Files:**
- Create: `Sources/OpenSimAndroid/EmulatorGRPCClient.swift`, `Sources/OpenSimAndroid/Generated/` (checked-in stubs), `AndroidGRPCDisplaySurface.swift`
- Modify: `Package.swift` (grpc-swift/swift-protobuf), `AndroidScreenService.swift`, `AndroidInputService.swift`
- Test: `Tests/OpenSimAndroidTests/AndroidGRPCTests.swift` with a local fake server.

**Interfaces:**
- Consumes: `emulator_controller.proto` service `android.emulation.control.EmulatorController`, methods `getScreenshot`, `streamScreenshot`, `sendTouch`, `sendKey`, `getStatus`.
- Produces: `EmulatorGRPCClient.connect(port:)`, `.streamScreens()`, `.sendTouch(_:)`, `.sendKey(_:)`, `.status()`; `AndroidGRPCDisplaySurface` conforming to Plan 2 `DisplaySurface`.

- [ ] **Step 1: Generate and check in stubs**

Use the proto from the installed emulator (`$ANDROID_SDK/emulator/lib/emulator_controller.proto`) or Google's prebuilt mirror. Generate Swift/protobuf/gRPC stubs with the pinned `protoc`/plugins, commit under `Sources/OpenSimAndroid/Generated/`. Do not generate during normal build; users need no protoc.

- [ ] **Step 2: Test transport with a fake**

```swift
func testTouchPayloadContainsAllPointers() throws {
    let event = AndroidTouchEvent(points: [
        AndroidTouchPoint(id: 0, x: 100, y: 200),
        AndroidTouchPoint(id: 1, x: 300, y: 400)
    ], action: .down)
    XCTAssertEqual(event.points.count, 2)
}
```

- [ ] **Step 3: Implement client**

- Boot emulator with `-grpc 127.0.0.1:<dynamicPort>`; store port in `AndroidAVD`/device metadata.
- `streamScreens`: consume `streamScreenshot`; decode image; hand frames to `AndroidGRPCDisplaySurface`; drop frames if consumer busy (no unbounded buffer).
- `sendTouch`: map `SimulatorGesture` touch points to `TouchEvent`; multi-touch supported; `sendKey` for hardware keys.
- Fallback: if gRPC connect fails, `capability_unavailable("androidGrpc")`; screen/input use adb fallback; UI/doctor show explicit notice.
- Bind loopback; do not enable TLS in Plan 10; no remote network.

- [ ] **Step 4: Test + skip**

```bash
swift test --filter OpenSimAndroidTests.AndroidGRPCTests
```

Expected: fake server PASS; real emulator gRPC test SKIP when no AVD.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/OpenSimAndroid/EmulatorGRPCClient.swift Sources/OpenSimAndroid/Generated Sources/OpenSimAndroid/AndroidGRPCDisplaySurface.swift Tests/OpenSimAndroidTests/AndroidGRPCTests.swift
git commit -m "feat(android): add emulator gRPC screen and touch"
```
---

### Task 7: System image management

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidSystemImageService.swift`
- Test: `Tests/OpenSimAndroidTests/AndroidSystemImageTests.swift`

**Interfaces:**
- Consumes: `sdkmanager --list`, `sdkmanager --install`, `sdkmanager --uninstall`, license files.
- Produces: `list()`, `install(package:acceptLicense:)`, `uninstall(package:)`.

- [ ] **Step 1: Test package parsing**

```swift
func testParsesInstalledAndAvailableSystemImages() throws {
    let output = """
    Installed packages:
      system-images;android-36;google_apis;arm64-v8a | 36 | Google APIs ARM 64 v8a
    Available Packages:
      system-images;android-35;google_apis;arm64-v8a | 35 | Google APIs ARM 64 v8a
    """
    let images = try AndroidSystemImageService.parse(output: output)
    XCTAssertTrue(images.contains { $0.package == "system-images;android-36;google_apis;arm64-v8a" && $0.installed })
}
```

- [ ] **Step 2: Implement**

- `list`: `sdkmanager --list`; parse only `system-images;` lines; API level, tag, ABI.
- `install`: require explicit `acceptLicense`; run `sdkmanager --install <package>` with `yes` input only after owner consent; never auto-install.
- `uninstall`: block if any AVD references package; `sdkmanager --uninstall <package>` after confirm.
- No system image deletion in background.

- [ ] **Step 3: Test/commit**

```bash
swift test --filter OpenSimAndroidTests.AndroidSystemImageTests
git add Sources/OpenSimAndroid/AndroidSystemImageService.swift Tests/OpenSimAndroidTests/AndroidSystemImageTests.swift
git commit -m "feat(android): add system image management"
```
---

### Task 8: Platform adapter, daemon routing, CLI và MCP

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidPlatformAdapter.swift`, `Sources/OpenSimAndroid/Catalog/AndroidOperations.swift`, `Sources/OpenSimDaemon/Platforms/PlatformRouter.swift`
- Modify: `Package.swift`, `Sources/OpenSimDaemon/DaemonRunner.swift`, `Sources/OpenSimCore/Catalog/OperationCatalog.swift` factory (`openSim()` or `plan5()` merge), `Sources/OpenSimCLI/Commands/OpenSimCommand.swift` (`android` subcommand), `Sources/OpenSimMCP` catalog adapter tests.

**Interfaces:**
- Consumes: all Android services, `OperationCatalog`, `OperationDispatcher`.
- Produces: `AndroidPlatformAdapter` conforms to device/runtime/app/log/screen/input/accessibility protocols; `PlatformRouter` selects Apple/Android by `Device.platform`; `android_avd_*`/`android_system_image_*` operations.

- [ ] **Step 1: Test catalog and routing**

```swift
func testAndroidOperationsAreInUnifiedCatalog() {
    let names = Set(OperationCatalog.plan10().mcpOperations().map(\.mcpName))
    XCTAssertTrue(names.isSuperset(of: ["android_avd_list", "android_avd_create", "android_system_image_list"]))
    XCTAssertTrue(names.contains("ui_tap"))
}

func testRouterSelectsAndroidByDeviceID() async throws {
    let router = PlatformRouter(apple: FakeApple(), android: FakeAndroid())
    XCTAssertEqual(try await router.platform(for: DeviceID(rawValue: "android:Pixel_9")), .android)
}
```

- [ ] **Step 2: Implement routing**

- `OperationCatalog.plan10()` = `plan5()` + `AndroidOperations.all`; no separate tool list. Nếu Plan 9 đã có `OperationCatalog.openSim()`, merge Android registration vào factory đó và dùng một factory duy nhất cho daemon/CLI/MCP; không tạo catalog thứ hai.
- `PlatformRouter` gets platform from device prefix (`android:`) or explicit `platform` parameter; Apple IDs remain UUID. `DeviceResolver` exact-ID branch phải nhận `android:<avdName>` trước UUID validation; AVD name không bị ép thành UUID.
- `OperationDispatcher`/`BridgeOperationExecutor` route device-scoped ops to the adapter; global `android_*` ops go to `AndroidPlatformAdapter`.
- Lease/audit unchanged: `session_acquire` on Android device ID; control lease per AVD; delete/erase destructive confirm.
- CLI: `opensim android avd list/create/delete`, `opensim android system-image list/install`; device/runtime/app/ui commands accept `--platform android` or Android device name.
- MCP: same operation names; no `android_*` tool duplicates for device/ui/app/log.
- Error codes: `android_sdk_not_found`, `avd_not_found`, `emulator_failed`, `adb_failed`, `android_image_unavailable`, `grpc_unavailable`.

- [ ] **Step 3: Test/commit**

```bash
swift test --filter OpenSimAndroidTests
swift test --filter OpenSimMCPTests
git add Package.swift Sources/OpenSimAndroid/AndroidPlatformAdapter.swift Sources/OpenSimAndroid/Catalog Sources/OpenSimDaemon/Platforms Sources/OpenSimDaemon/DaemonRunner.swift Sources/OpenSimCLI/Commands/OpenSimCommand.swift
git commit -m "feat(android): route daemon cli and mcp operations"
```
---

### Task 9: macOS app platform support

**Files:**
- Modify: `App/Sources/OpenSimApp/Devices/DeviceCatalogModel.swift`, `DevicesView.swift`, `NewDeviceModel.swift`, `Runtimes/RuntimeModel.swift`, `RuntimesView.swift`, `Windows/DeviceWindowRoot.swift`, `Windows/DeviceToolbar.swift`, `Settings/DaemonSettingsView.swift`, `Settings/CapabilitiesSettingsView.swift`
- Test: `Tests/OpenSimAppUITests/AndroidUITests.swift`

**Interfaces:**
- Consumes: `Platform.android`, Android doctor/runtime/device metadata, `AndroidGRPCDisplaySurface`.
- Produces: platform filter, Android device type/runtime picker, Android rows in Runtimes, Android SDK settings/doctor, Android device window controls.

- [ ] **Step 1: UI test**

```swift
func testAndroidPlatformFilterAndNewDevice() throws {
    let app = TestEnvironment.launchApp()
    addTeardownBlock { app.terminate() }
    app.popUpButtons["platform-filter"].click()
    app.menuItems["Android"].click()
    XCTAssertTrue(app.otherElements["devices-table"].waitForExistence(timeout: 10))
    app.buttons["new-device-button"].click()
    XCTAssertTrue(app.sheets["new-device-sheet"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.popUpButtons["new-device-platform"].exists)
}
```

- [ ] **Step 2: Implement**

- `DeviceCatalogModel` exposes `platformFilter`; `DevicesView` Picker All/Apple/Android; Android row icon `smartphone` (SF Symbol).
- New Simulator adds platform Picker (Apple/Android), device type Picker (Pixel 9/Pixel 9 Pro/Tablet), system image Picker; Android Create disabled if SDK/AVD image missing; note links to Runtimes/Doctor.
- Runtimes adds Android system-image rows (`API 36 · google_apis · arm64-v8a`, installed/not, size, AVD count); Install requires license consent.
- Device window uses `AndroidGRPCDisplaySurface`; if gRPC unavailable, screenshot polling with a visible "Fallback" capability note; toolbar Back/Home/Overview/Power/Rotate; keyboard/paste via adb/gRPC.
- Settings > Daemon: Android SDK path, adb/emulator/avdmanager/Java status, Choose path; Capabilities > Doctor: Android rows and missing-SDK recovery.
- No new visual system; use existing native Table/List/Form/Gauge/Chart.

- [ ] **Step 3: Test/commit**

```bash
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/AndroidUITests
git add App/Sources/OpenSimApp Tests/OpenSimAppUITests/AndroidUITests.swift
git commit -m "feat(app): add android platform surfaces"
```
---

### Task 10: Android storage và metrics

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidStorageService.swift`, `AndroidMetricsService.swift`
- Modify: `Sources/OpenSimCore/Storage/StorageCategory.swift`, `Sources/OpenSimDaemon/Storage/StorageService.swift`, `Sources/OpenSimDaemon/Metrics/MetricsSampler.swift`, Plan 4 storage UI.

**Interfaces:**
- Consumes: AVD data paths, SDK system images, host process table, adb.
- Produces: storage categories `.androidAVD`, `.androidSystemImage`; metrics samples for running AVDs.

- [ ] **Step 1: Test safety**

- AVD running → `storage_in_use`.
- System image referenced by any AVD → `storage_in_use`.
- Unknown SDK path → skip with explicit reason; never delete outside allowlist.

- [ ] **Step 2: Implement**

- AVD data `~/.android/avd/<name>.avd`; system image `$ANDROID_SDK/system-images/...`; scan sizes allocated; no auto-clean.
- Metrics: map `emulator`/`qemu-system-*` process by `-avd <name>` in argv; CPU/RAM; supplement `adb shell dumpsys meminfo`/`top`; unknown group for unmapped.
- UI: Storage rows use category "Android AVD / System images"; Performance table includes Android devices; no separate tab.

- [ ] **Step 3: Commit**

```bash
git add Sources/OpenSimAndroid/AndroidStorageService.swift Sources/OpenSimAndroid/AndroidMetricsService.swift Sources/OpenSimCore/Storage Sources/OpenSimDaemon/Storage Sources/OpenSimDaemon/Metrics
git commit -m "feat(android): add storage and metrics"
```
---

### Task 11: Integration fixture, AVD smoke và release gate

**Files:**
- Create: `Fixtures/AndroidFixture/` (Gradle app + prebuilt debug APK), `Tests/IntegrationTests/AndroidIntegrationTests.swift`, `Scripts/android/create-test-avd.sh`
- Modify: `Scripts/release/run-release-gate.sh`, docs.

**Interfaces:**
- Consumes: owner-provided Android SDK/system image/AVD.
- Produces: reproducible smoke test; release gate opt-in for Android.

- [ ] **Step 1: Fixture**

- Minimal Android app with a button (`resource-id` `dev.opensim.fixture:id/primary`), text field, counter label; build debug APK with Gradle; commit the APK or build in CI with JDK 17.
- `create-test-avd.sh` checks `system-images;...` installed; if not, prints exact `sdkmanager` command and exits 2; never downloads.
- AVD name `OpenSim_Test_API_36`; `avdmanager create avd -n ... -k ... -d pixel_9`.

- [ ] **Step 2: Integration test**

```swift
func testAndroidLifecycleAndUIActions() async throws {
    try requireAndroid()
    let avd = try await avdService.create(name: "OpenSim_Test_API_36", deviceType: "pixel_9", systemImage: systemImage)
    addTeardownBlock { try? await avdService.delete(name: avd.name) }
    _ = try await avdService.boot(name: avd.name, grpcPort: 0, headless: true)
    try await appService.install(serial: avd.serial, apkPath: fixtureAPK.path, reinstall: true)
    try await appService.launch(serial: avd.serial, bundleID: "dev.opensim.fixture", activity: ".MainActivity")
    let tree = try await accessibility.tree(on: avd.deviceID, maxDepth: 30)
    XCTAssertTrue(tree.contains { $0.identifier == "dev.opensim.fixture:id/primary" })
    try await input.tap(on: avd.deviceID, at: try XCTUnwrap(tree.first { $0.identifier == "dev.opensim.fixture:id/primary" }?.center))
    XCTAssertTrue(try await waitForLabel("1", timeout: 5))
    try await avdService.shutdown(name: avd.name)
}
```

- [ ] **Step 3: Release gate**

- Apple release Plan 7 does not require Android. If Android is in the release, gate runs `OPENSIM_ANDROID=1` and fails when SDK/AVD missing.
- `doctor --json` includes Android fields; README/plan link updated.

- [ ] **Step 4: Run + commit**

```bash
OPENSIM_INTEGRATION=1 OPENSIM_ANDROID=1 swift test --filter AndroidIntegrationTests
git add Fixtures/AndroidFixture Tests/IntegrationTests/AndroidIntegrationTests.swift Scripts/android Scripts/release/run-release-gate.sh
git commit -m "test(android): add fixture and integration gate"
```
---

## Spec Coverage

| Spec | Nội dung | Task |
|---|---|---|
| 2 | Android Emulator là platform thứ hai | all |
| 3 | Không physical Android/emulator bên thứ ba | 1, 8 |
| 4 | AVD + system image của Google | 2, 7 |
| 5.1 | `OpenSimAndroid` adapter, không chạm private Apple | 1, 8 |
| 5.4 | adb/emulator/gRPC/uiautomator | 3–7 |
| 6 | `Platform.android`, AndroidAVD/SystemImage | 2, 7, 8 |
| 7.2 | `opensim android avd/system-image` | 8 |
| 8.2 | `android_avd_*`, `android_system_image_*`; device/ui/app dùng chung | 8 |
| 9.7 | UI platform filter/New Simulator/Runtimes/Doctor | 9 |
| 10 | AVD/system-image storage, in-use guard | 10 |
| 11 | Android process metrics | 10 |
| 14 | unit/XML/adb/gRPC/integration | 1–11 |
| 17.1 | Android AVD smoke | 11 |

## Exit Criteria

- `swift build` và `swift test --filter OpenSimAndroidTests` pass; Apple test suite vẫn pass.
- `AndroidSDK.detect` tìm đúng SDK/adb/emulator/avdmanager/sdkmanager; thiếu SDK trả `android_sdk_not_found` với recovery.
- AVD list/create/boot/shutdown/erase/delete hoạt động; delete bị chặn khi AVD running/in-use.
- App install/launch/terminate/log hoạt động qua adb; screenshot và tap/type hoạt động; gRPC live screen/multi-touch hoạt động khi bật, fallback adb rõ ràng.
- uiautomator tree parse đúng identifier/text/bounds; selector `id=`, `label=`, `text=` tap đúng element.
- System image list/install/uninstall hoạt động; không auto-download/không nhận license thay owner; uninstall bị chặn khi có AVD dùng.
- Operation catalog `plan10()` gồm Android ops + `ui_*`/`storage_*`/`perf_*`; lease/audit dùng chung; MCP `tools/list` thấy Android tools.
- UI: platform filter, New Simulator Android, Runtimes system image, Settings/Doctor Android; device window Android screen/input.
- Storage scan thấy AVD/system image; in-use guard; metrics có Android sample hoặc `Unknown` rõ ràng.
- Integration test Android pass khi có SDK/AVD, hoặc `BLOCKED: no Android AVD` với hướng dẫn; Apple release không bị chặn nếu owner không đưa Android vào release.
- Không thay đổi hành vi Apple ngoài additive platform routing; không có shell string, không auto-download, không xoá ngoài allowlist.
