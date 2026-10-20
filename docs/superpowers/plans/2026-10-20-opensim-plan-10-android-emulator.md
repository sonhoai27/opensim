# OpenSim Plan 10 — Android Emulator

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm Android Emulator (AVD) làm platform thứ hai của OpenSim: cùng daemon, operation catalog, lease/audit, CLI, MCP và macOS app. Apple path không đổi.

**Architecture:** `OpenSimAndroid` là adapter độc lập, không chạm private API Apple. Nó dùng `emulator` + `avdmanager` cho lifecycle, `adb` cho app/log/input fallback/uiautomator, và emulator gRPC `EmulatorController` cho live screen/touch. `OpenSimDaemon` route operation theo `Device.platform`; CLI/MCP/UI giữ nguyên bề mặt lệnh. `OpenSimAndroid` chỉ phụ thuộc `OpenSimCore`; render surface của Android nằm trong app target, không kéo AppKit/`OpenSimBridge` vào adapter.

**Tech Stack:** Swift 6, Foundation `Process`, `XMLParser`, `OpenSimCore`, app macOS native của Plan 4; `grpc-swift-2` + `grpc-swift-nio-transport` + `grpc-swift-protobuf` (generated stubs checked in) cho emulator gRPC; adb/emulator/avdmanager/sdkmanager; JDK 17+.

**Spec:** `docs/superpowers/specs/2026-10-19-open-simulator-design.md`

**Depends on:** Plan 2 (screen/input/selector contracts), Plan 3 (operation catalog, daemon, lease), Plan 4 (app shell), Plan 5 (`openSim()` catalog scaffold). Plan 10 is additive; it can run after Plan 5 and in parallel with Plan 6, or after Plan 7 if Android is not in the Apple release.

## Global Constraints

- Không sửa hành vi Apple hiện có. `OpenSimBridge` vẫn là boundary private API duy nhất; Android code không import CoreSimulator/SimulatorKit.
- Không tự tải Android SDK, system image, JDK hoặc license. Mọi thao tác cài đặt cần owner consent rõ ràng.
- Không dùng shell string. Mọi process (`adb`, `emulator`, `avdmanager`, `sdkmanager`) dùng argument array qua `Process`.
- Không xoá AVD/system image khi đang chạy hoặc đang được AVD khác dùng. Delete cần confirm và kiểm tra in-use ngay trước khi xoá.
- Không ghi đè AVD cùng tên. `create` preflight `emulator -list-avds`; nếu tên đã tồn tại trả `device_name_conflict`. Muốn thay AVD phải `android_avd_delete` (confirm, chỉ khi stopped) rồi `android_avd_create`; Plan 10 không có `replaceExisting`, không dùng `--force`.
- Android Emulator chỉ chạy trên macOS host trong plan này; không hỗ trợ Android physical devices, Genymotion, BlueStacks.
- Loopback only: emulator gRPC bind `127.0.0.1`, bật `-grpc-use-token`; token do emulator ghi vào discovery file `<avdHome>/running/pid_<PID>.ini` (quyền `0600`), không tự sinh token. Không mở gRPC không auth.
- Không log token/console auth; không đưa screenshot/log lên mạng.
- Native UI only: không đưa card/chart/custom style mới; Android UI dùng chung shell/Table/List/Form của Plan 4.
- Không đổi tên `Device`, `Runtime`, `DeviceID`, `Platform` ngoài việc thêm `Platform.android`.
- Văn xuôi tiếng Việt; code/type/identifier/command tiếng Anh; không CJK; không placeholder.

## Decisions (chốt trước khi implement)

1. **gRPC auth:** dùng `-grpc-use-token`; đọc `grpc.port` + `grpc.token` từ discovery file của chính PID emulator. `-grpc-use-jwt`/JWKS không nằm trong Plan 10; nếu emulator hiện tại bỏ token mode, đánh dấu `grpcUnavailable` và dùng adb fallback, không mở gRPC trần.
2. **Port:** không truyền `-port`; emulator tự chọn cặp console/adb (even, 5554–5682). Plan chỉ cấp một gRPC port tự do; đọc console/adb port thật từ serial `emulator-<consolePort>` và discovery.
3. **Surface:** `OpenSimAndroid` chỉ phát frame stream; `AndroidScreenHost` trong app target là view host (không cần conform `DisplaySurface`). Không đưa `NSView`/`OpenSimBridge` vào `OpenSimAndroid`.
4. **Runtime identity:** `AndroidAVD.systemImage` và `RuntimeID` là package `system-images;...`; `imagePath` giữ path filesystem riêng. `AndroidSystemImage` dùng field `packagePath`.
5. **Operation schema:** `android_avd_boot/shutdown/erase/delete` nhận `name` (không phải `device`); operation device-scoped generic vẫn dùng `device`.
6. **Screenshot:** Android service hỗ trợ đủ `format`/`scale`/`quality`; default MCP (JPEG 80, scale 0.5) phải chạy, không reject.
7. **Runtime API:** `downloadRuntime`/`installRuntime(at:)` của adapter Android trả `capability_unavailable`; system image cài/xoá qua `android_system_image_*` với license consent.
8. **Hardware button:** thêm `back`, `overview`, `power`, `rotate` vào `HardwareButton`; Apple bridge trả `capability_unavailable` cho case mới, Android map keyevent (rotate dùng console rotate, không có keycode).
9. **Validation:** AVD name và system-image package được validate canonical trước khi dùng path/command; cấm `..`, leading `-`, path separator và symlink escape.

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
| `Sources/OpenSimAndroid/AndroidSDK.swift` | Locator SDK/JDK/adb/emulator/avdmanager/sdkmanager, explicit `sdkPath` | 1 |
| `Sources/OpenSimAndroid/AndroidCommandRunner.swift` | Process runner, timeout, output capture | 1 |
| `Sources/OpenSimAndroid/AndroidIdentifier.swift` | Validate AVD name/package, canonical path | 1 |
| `Sources/OpenSimAndroid/AndroidAVDService.swift` | List/create/boot/shutdown/erase/delete AVD; allocates ports | 2 |
| `Sources/OpenSimAndroid/AndroidDeviceService.swift` | Map AVD/serial sang `Device` | 2 |
| `Sources/OpenSimAndroid/EmulatorDiscovery.swift` | Parse `running/pid_<PID>.ini`, token `0600` | 2 |
| `Sources/OpenSimAndroid/EmulatorPortAllocator.swift` | Cấp gRPC port tự do, không dùng `-port` | 2 |
| `Sources/OpenSimAndroid/AndroidAppService.swift` | install/uninstall/launch/terminate/list/info | 3 |
| `Sources/OpenSimAndroid/AndroidLogService.swift` | logcat tail/stream | 3 |
| `Sources/OpenSimAndroid/AndroidScreenService.swift` | screencap fallback + gRPC stream + ImageIO | 4, 6 |
| `Sources/OpenSimAndroid/AndroidInputService.swift` | adb input fallback + gRPC touch/key; Unicode policy | 4, 6 |
| `Sources/OpenSimAndroid/AndroidImageProcessor.swift` | PNG/JPEG + scale + quality | 4 |
| `Sources/OpenSimAndroid/AndroidKeyMap.swift` | Android keycode/button mapping | 4 |
| `Sources/OpenSimAndroid/AndroidInputText.swift` | ASCII escape + Unicode gate | 4 |
| `Sources/OpenSimAndroid/AndroidAccessibilityService.swift` | uiautomator XML → `UIElement` | 5 |
| `Sources/OpenSimAndroid/AndroidSystemImageService.swift` | sdkmanager list/install/uninstall | 7 |
| `Sources/OpenSimAndroid/EmulatorGRPCClient.swift` | Generated `EmulatorController` transport | 6 |
| `Sources/OpenSimAndroid/AndroidFrame.swift` | Frame stream cho app host | 6 |
| `Sources/OpenSimAndroid/Generated/` | Checked-in protobuf/gRPC Swift stubs | 6 |
| `Sources/OpenSimAndroid/AndroidPlatformAdapter.swift` | Compose services into platform adapter | 8 |
| `Sources/OpenSimDaemon/Platforms/PlatformDoctor.swift` | Compose Apple + Android doctor | 1, 8 |
| `Sources/OpenSimCore/Catalog/AndroidOperations.swift` | Metadata `android_avd_*`, `android_system_image_*` | 8 |
| `Sources/OpenSimCore/Catalog/OpenSimCatalog.swift` | Mở rộng `openSim()` với Android | 8 |
| `Sources/OpenSimDaemon/Platforms/PlatformRouter.swift` | Route operation theo platform/device | 8 |
| `App/Sources/OpenSimApp/Devices/NewDeviceModel.swift` | Platform + Android device type | 9 |
| `App/Sources/OpenSimApp/Runtimes/RuntimeModel.swift` | Android system images | 9 |
| `App/Sources/OpenSimApp/Windows/DeviceWindowRoot.swift` | Chọn Android/Apple screen host | 9 |
| `App/Sources/OpenSimApp/Windows/AndroidScreenHost.swift` | gRPC/screenshot host cho Android | 9 |
| `App/Sources/OpenSimApp/Settings/DaemonSettingsView.swift` | Android SDK path/status | 9 |
| `App/Sources/OpenSimApp/Settings/CapabilitiesSettingsView.swift` | Android doctor rows | 9 |
| `Sources/OpenSimAndroid/AndroidStorageService.swift` | AVD/system-image storage items + fingerprint | 10 |
| `Sources/OpenSimAndroid/AndroidMetricsService.swift` | Android process/adb metrics | 10 |
| `Sources/OpenSimCore/Domain/Android.swift` | `AndroidSystemImage` shared type | 7 |
| `Sources/OpenSimCore/Storage/AndroidStorageExecuting.swift` | Protocol để CleanExecutor gọi Android storage | 10 |
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
- Create: `Sources/OpenSimAndroid/AndroidSDK.swift`, `Sources/OpenSimAndroid/AndroidCommandRunner.swift`, `Sources/OpenSimAndroid/AndroidIdentifier.swift`, `Tests/OpenSimAndroidTests/AndroidSDKTests.swift`, `Tests/OpenSimAndroidTests/AndroidIdentifierTests.swift`
- Modify: `Package.swift`, `Sources/OpenSimCore/Domain/Doctor.swift` (add Android capability fields), `Sources/OpenSimDaemon/Platforms/PlatformDoctor.swift` (create), `Sources/OpenSimDaemon/Runtime/DaemonRunner.swift`, `Sources/OpenSimCLI/Runtime/CLIRuntime.swift`

**Interfaces:**
- Consumes: `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `JAVA_HOME`, explicit `sdkPath`, filesystem.
- Produces: `AndroidSDK.detect(sdkPath:environment:homeDirectory:fileManager:)`, `AndroidSDK.adb`, `.emulator`, `.avdmanager`, `.sdkmanager`, `.java`; `AndroidCommandRunner.run(_:timeout:)`; `AndroidIdentifier.validateAVDName(_:)`, `.validateSystemImagePackage(_:)`, `.canonicalAVDPath(avdHome:name:)`, `.canonicalSystemImagePath(sdk:packagePath:)`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
import OpenSimCore
@testable import OpenSimAndroid

final class AndroidSDKTests: XCTestCase {
    private func makeFakeSDK(at root: URL) throws -> URL {
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
        return adb
    }

    func testDetectsSDKFromEnvironmentFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let adb = try makeFakeSDK(at: root)

        let sdk = try AndroidSDK.detect(environment: ["ANDROID_HOME": root.path], fileManager: .default)
        XCTAssertEqual(sdk.root.path, root.path)
        XCTAssertEqual(sdk.adb.path, adb.path)
    }

    func testExplicitSDKPathWinsOverEnvironment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        _ = try makeFakeSDK(at: root)

        let sdk = try AndroidSDK.detect(
            sdkPath: root.path,
            environment: ["ANDROID_HOME": "/nonexistent"],
            fileManager: .default
        )
        XCTAssertEqual(sdk.root.path, root.path)
    }

    func testInvalidExplicitSDKPathThrows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertThrowsError(try AndroidSDK.detect(sdkPath: root.path, environment: [:], fileManager: .default)) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, ErrorCode.androidSDKNotFound.rawValue)
        }
    }

    func testMissingSDKThrowsWithRecovery() throws {
        let emptyHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)
        XCTAssertThrowsError(try AndroidSDK.detect(environment: [:], homeDirectory: emptyHome, fileManager: .default)) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, ErrorCode.androidSDKNotFound.rawValue)
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
        sdkPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> AndroidSDK

    public static func avdHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL
}
```

`detect` thứ tự root: `sdkPath` (nếu có, thắng mọi nguồn), `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `~/Library/Android/sdk`. `sdkPath` explicit phải hợp lệ; nếu thiếu `adb`/`emulator` thì ném `android_sdk_not_found`, không fallback im lặng. `adb` tại `platform-tools/adb`; `emulator` tại `emulator/emulator`; cmdline tools tìm `cmdline-tools/latest/bin/avdmanager|sdkmanager`, sau đó version directory bất kỳ. Thiếu `adb` hoặc `emulator` ném `android_sdk_not_found` với recovery nêu đường dẫn cần cấu hình. Java đọc `JAVA_HOME/bin/java` hoặc `/usr/bin/java`; version parse qua `java -version`.

`AndroidIdentifier` validate trước khi dùng path/command: AVD name `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`, cấm `.`/`..`, leading `-`, `/`, `\`; system-image package exact `^system-images;android-[0-9]+;[A-Za-z0-9_-]+;[A-Za-z0-9_-]+$`. Canonical path phải resolve symlink và nằm dưới AVD home/SDK `system-images`; sai trả `invalid_argument`, không chạy `avdmanager`/`sdkmanager`.

`AndroidCommandRunner`:

```swift
public struct AndroidCommand: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]?
    public var stdin: Data?
    public var timeout: Duration?
}

public struct CommandOutput: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: String
}

public struct AndroidProcessHandle: Sendable {
    public let pid: Int32
    public let stdout: AsyncStream<Data>
    public let stderr: AsyncStream<Data>
    public func write(_ data: Data) throws
    public func terminate()
    public func wait() async throws -> CommandOutput
}

public protocol AndroidCommandRunning: Sendable {
    func run(_ command: AndroidCommand) async throws -> CommandOutput
    func start(_ command: AndroidCommand) async throws -> AndroidProcessHandle
}
```

Package.swift trong Task 1 phải có target/test target trước khi chạy `swift build`:

```swift
products: [
    .library(name: "OpenSimAndroid", targets: ["OpenSimAndroid"])
],
targets: [
    .target(name: "OpenSimAndroid", dependencies: ["OpenSimCore"]),
    .testTarget(name: "OpenSimAndroidTests", dependencies: ["OpenSimAndroid", "OpenSimCore"])
]
```

Thêm `OpenSimAndroid` vào danh sách dependencies hiện có của target `OpenSimDaemon` ngay Task 1 vì `PlatformDoctor` map `AndroidDoctorReport`; không thay các dependency cũ. Task 6 bổ sung dependency gRPC vào target Android; Task 8 thêm `OpenSimAndroid` vào deps `IntegrationTests`; Task 9 thêm product vào app.

Không dùng `sh -c`. `run` chỉ dành cho command hữu hạn (timeout mặc định 30 giây). `start` dành cho process dài hạn: `emulator` boot/wipe, `adb logcat`, và `sdkmanager` cần stdin. Handle giữ PID, stream stdout/stderr, cho phép write stdin, terminate và wait; daemon phải đăng ký handle để kill khi shutdown. `adb wait-for-device` dùng timeout riêng 120 giây.

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
    public var emulatorGRPCAvailable: Bool
    public var androidA11yAvailable: Bool
    public var grpcAuthMode: String?
    public var recovery: String?
}
```

`DoctorReport` trong Core thêm các field optional tương ứng (`androidSdkPath`, `androidADBVersion`, `androidEmulatorVersion`, `androidAVDManagerAvailable`, `androidSDKManagerAvailable`, `androidJavaVersion`, `androidEmulatorGRPCAvailable`, `androidA11yAvailable`); `PlatformDoctor` map từ `AndroidDoctorReport`. UI Doctor hiển thị row `androidSdk`, `adb`, `avdmanager`, `emulatorGrpc`, `androidA11y` bằng text, không chỉ màu.

Test validation (cùng Task 1):

```swift
final class AndroidIdentifierTests: XCTestCase {
    func testRejectsTraversalAndOptionInjection() {
        for name in ["../evil", "..", "-avd", "a/b", "a\\b", ""] {
            XCTAssertThrowsError(try AndroidIdentifier.validateAVDName(name), name) { error in
                XCTAssertEqual((error as? OpenSimError)?.code, ErrorCode.invalidArgument.rawValue)
            }
        }
        XCTAssertNoThrow(try AndroidIdentifier.validateAVDName("Pixel_9_API_36"))
    }

    func testRejectsPackageOutsideSystemImages() {
        XCTAssertNoThrow(try AndroidIdentifier.validateSystemImagePackage("system-images;android-36;google_apis;arm64-v8a"))
        for package in ["system-images;../../etc", "platforms;android-36", "system-images;android-36;google_apis;arm64-v8a;extra"] {
            XCTAssertThrowsError(try AndroidIdentifier.validateSystemImagePackage(package), package) { error in
                XCTAssertEqual((error as? OpenSimError)?.code, ErrorCode.invalidArgument.rawValue)
            }
        }
    }

    func testCanonicalPathRejectsSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let avdHome = root.appendingPathComponent("avd", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: avdHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: avdHome.appendingPathComponent("Evil.avd"),
            withDestinationURL: outside
        )
        XCTAssertThrowsError(try AndroidIdentifier.canonicalAVDPath(avdHome: avdHome, name: "Evil")) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, ErrorCode.invalidArgument.rawValue)
        }
    }
}
```

- [ ] **Step 4: Chạy test xanh**

```bash
swift test --filter OpenSimAndroidTests.AndroidSDKTests
swift build
```

Expected: PASS các test SDK/identifier; build có target `OpenSimAndroid`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/OpenSimAndroid Sources/OpenSimCore/Domain/Doctor.swift Sources/OpenSimDaemon/Platforms/PlatformDoctor.swift Sources/OpenSimDaemon/Runtime/DaemonRunner.swift Sources/OpenSimCLI/Runtime/CLIRuntime.swift Tests/OpenSimAndroidTests/AndroidSDKTests.swift Tests/OpenSimAndroidTests/AndroidIdentifierTests.swift
git commit -m "feat(android): detect SDK and expose doctor"
```
---

### Task 2: AVD catalog và lifecycle

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidAVDService.swift`, `AndroidDeviceService.swift`, `EmulatorDiscovery.swift`, `EmulatorPortAllocator.swift`
- Test: `Tests/OpenSimAndroidTests/AndroidAVDTests.swift`

**Interfaces:**
- Consumes: `AndroidSDK`, `AndroidCommandRunning`, `EmulatorPortAllocating`, `Device`, `DeviceID`, `Platform.android`.
- Produces: `AndroidAVDService(sdk:avdHome:runner:portAllocator:)`, `.list()`, `.create(name:deviceType:systemImage:)`, `.boot(name:headless:)`, `.shutdown(name:)`, `.erase(name:)`, `.delete(name:)`; `AndroidDeviceService.listDevices()`; `EmulatorDiscovery`.

```swift
public struct AndroidAVD: Sendable, Equatable, Identifiable {
    public enum State: String, Sendable { case stopped, booting, running }
    public var id: String { name }
    public let name: String
    public let deviceType: String
    /// Package `system-images;android-36;google_apis;arm64-v8a`, không phải path.
    public let systemImage: String
    public let imagePath: String
    public let apiLevel: Int
    public let tag: String
    public let abi: String
    public let dataPath: String
    public var state: State
    public var serial: String?
    public var consolePort: Int?
    public var adbPort: Int?
    public var grpcPort: Int?
    public var grpcTokenPath: String?
    public var grpcReady: Bool
    public var lastBootedAt: Date?
    public var deviceID: DeviceID { DeviceID(rawValue: "android:\(name)") }
}

public protocol EmulatorPortAllocating: Sendable {
    func freeGRPCPort() throws -> Int
}
```

- [ ] **Step 1: Viết test parse/list**

```swift
import XCTest
import OpenSimCore
@testable import OpenSimAndroid

final class AndroidAVDTests: XCTestCase {
    private var root: URL!
    private var avdHome: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        avdHome = root.appendingPathComponent("avd", isDirectory: true)
        try FileManager.default.createDirectory(at: avdHome, withIntermediateDirectories: true)
        try writeConfig(name: "Pixel_9_API_36", sysdir: "system-images/android-36/google_apis/arm64-v8a/")
        try writeConfig(name: "Tablet_API_35", sysdir: "system-images/android-35/google_apis_playstore/arm64-v8a/")
    }

    private func writeConfig(name: String, sysdir: String) throws {
        let dir = avdHome.appendingPathComponent("\(name).avd", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = """
        image.sysdir.1=\(sysdir)
        abi.type=arm64-v8a
        tag.id=google_apis
        hw.device.name=pixel_9
        """
        try config.write(to: dir.appendingPathComponent("config.ini"), atomically: true, encoding: .utf8)
    }

    private func makeSDK() throws -> AndroidSDK {
        let adb = root.appendingPathComponent("platform-tools/adb")
        let emulator = root.appendingPathComponent("emulator/emulator")
        let avdmanager = root.appendingPathComponent("cmdline-tools/latest/bin/avdmanager")
        let sdkmanager = root.appendingPathComponent("cmdline-tools/latest/bin/sdkmanager")
        for executable in [adb, emulator, avdmanager, sdkmanager] {
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
        return AndroidSDK(root: root, adb: adb, emulator: emulator, avdmanager: avdmanager, sdkmanager: sdkmanager, java: nil)
    }

    private final class FakeRunner: AndroidCommandRunning, @unchecked Sendable {
        var listOutput: String
        var commands: [AndroidCommand] = []
        init(listOutput: String) { self.listOutput = listOutput }

        func run(_ command: AndroidCommand) async throws -> CommandOutput {
            commands.append(command)
            if command.arguments.contains("-list-avds") {
                return CommandOutput(exitCode: 0, stdout: Data(listOutput.utf8), stderr: "")
            }
            return CommandOutput(exitCode: 0, stdout: Data(), stderr: "")
        }

        func start(_ command: AndroidCommand) async throws -> AndroidProcessHandle {
            throw OpenSimError(code: .internalError, message: "start not used in this unit test")
        }
    }

    func testParsesAVDNamesAndConfig() async throws {
        let runner = FakeRunner(listOutput: "Pixel_9_API_36\nTablet_API_35\n")
        let service = AndroidAVDService(sdk: try makeSDK(), avdHome: avdHome, runner: runner)
        let avds = try await service.list()
        XCTAssertEqual(avds.map(\.name), ["Pixel_9_API_36", "Tablet_API_35"])
        XCTAssertEqual(avds[0].apiLevel, 36)
        XCTAssertEqual(avds[0].abi, "arm64-v8a")
        XCTAssertEqual(avds[0].systemImage, "system-images;android-36;google_apis;arm64-v8a")
    }

    func testCreateRejectsDuplicateAndSendsNoToPrompt() async throws {
        let runner = FakeRunner(listOutput: "Pixel_9_API_36\n")
        let service = AndroidAVDService(sdk: try makeSDK(), avdHome: avdHome, runner: runner)
        do {
            _ = try await service.create(name: "Pixel_9_API_36", deviceType: "pixel_9", systemImage: "system-images;android-36;google_apis;arm64-v8a")
            XCTFail("Duplicate must fail")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, ErrorCode.deviceNameConflict.rawValue)
        }
        XCTAssertFalse(runner.commands.contains { $0.arguments.contains("create") })

        try writeConfig(name: "Fresh_AVD", sysdir: "system-images/android-36/google_apis/arm64-v8a/")
        _ = try await service.create(name: "Fresh_AVD", deviceType: "pixel_9", systemImage: "system-images;android-36;google_apis;arm64-v8a")
        let create = try XCTUnwrap(runner.commands.last { $0.arguments.contains("create") })
        XCTAssertEqual(create.stdin, Data("no\n".utf8))
    }

    func testLaunchArgumentsNeverPassConsolePortAndUseTokenAuth() {
        let args = AndroidAVDService.launchArguments(name: "Pixel_9_API_36", headless: true, grpcPort: 8554, wipeData: false)
        XCTAssertFalse(args.contains("-port"))
        XCTAssertTrue(args.contains("-grpc-use-token"))
        XCTAssertTrue(args.contains("-grpc"))
        XCTAssertTrue(args.contains("-no-window"))
    }
}
```

- [ ] **Step 2: Viết lifecycle**

`AndroidAVDService`:

```swift
public actor AndroidAVDService {
    public init(sdk: AndroidSDK, avdHome: URL, runner: any AndroidCommandRunning, portAllocator: any EmulatorPortAllocating = EmulatorPortAllocator())
    public static func launchArguments(name: String, headless: Bool, grpcPort: Int, wipeData: Bool) -> [String]
    public func list() async throws -> [AndroidAVD]
    public func create(name: String, deviceType: String, systemImage: String) async throws -> AndroidAVD
    public func startBoot(name: String, headless: Bool) async throws -> AndroidAVD
    public func waitForBoot(name: String) async throws -> AndroidAVD
    public func boot(name: String, headless: Bool) async throws -> AndroidAVD
    public func shutdown(name: String) async throws
    public func erase(name: String) async throws
    public func delete(name: String) async throws
}
```

- `list`: chạy `emulator -list-avds`; dùng `avdHome` đã inject; đọc `<avdHome>/<name>.avd/config.ini` để lấy `image.sysdir.1`, `abi.type`, `tag.id`, `hw.device.name`. Parse `image.sysdir.1` thành package: bỏ trailing `/`, tách `/`, ghép `;`; `apiLevel` lấy từ `android-<số>`. State từ `adb devices -l` + process table; serial map qua `adb -s <serial> emu avd name`, không đoán.
- `create`: validate `name`/`systemImage` bằng `AndroidIdentifier`; preflight `emulator -list-avds`; nếu name tồn tại trả `device_name_conflict`, không gọi `avdmanager`. Chạy `avdmanager create avd -n <name> -k <systemImage> -d <deviceType>` với `stdin = Data("no\n".utf8)` để trả lời prompt hardware profile; không `--force`. Exit 0 thì đọc trực tiếp `<avdHome>/<name>.avd/config.ini` và trả `AndroidAVD`, không phụ thuộc output `-list-avds` cũ. Image thiếu → `android_image_unavailable`.
- `startBoot`: `EmulatorPortAllocator.freeGRPCPort()` cấp một port tự do; **không truyền `-port`** để emulator tự chọn console/adb even trong 5554–5682. `launchArguments` trả `-avd <name> -grpc <port> -grpc-use-token -no-snapshot-save -no-boot-anim` (+ `-no-window` nếu headless). Dùng `start`; lưu handle/PID và trả `AndroidAVD` state `.booting` ngay, serial/ports có thể nil. Nếu process exit ngay vì port bận, retry tối đa 3 lần với port mới; vẫn fail trả `emulator_failed`.
- `waitForBoot`: chờ `EmulatorDiscovery.wait(avdHome:pid:)` đọc `grpc.port` + `grpc.token` (0600), rồi lấy serial từ discovery hoặc `adb devices -l` + `adb -s <serial> emu avd name` khớp AVD; suy ra `consolePort` và `adbPort = consolePort + 1`. Chờ `sys.boot_completed == 1` tối đa 120 giây; probe `getStatus`; chỉ set `grpcReady` khi token có và probe thành công. Token thiếu/flag không hỗ trợ → `grpcReady = false`, adb fallback, không mở gRPC trần; boot vẫn thành công nếu `sys.boot_completed == 1`.
- `boot`: convenience `startBoot` + `waitForBoot`; dùng cho `android_avd_boot` và integration test. Adapter `DeviceControlling.boot(wait: false)` chỉ gọi `startBoot`, không gọi `boot`.
- `shutdown`: `adb -s <serial> emu kill`; fallback terminate handle; chờ process exit; release port reservation.
- `erase`: nếu `state` là running/booting trả `device_busy` (không shutdown trước). Nếu stopped: launch `launchArguments(wipeData: true)` với `-no-window`, chờ boot, `adb -s <serial> emu kill`, chờ exit; giữ `config.ini`; timeout 120 giây, fail thì terminate và trả `emulator_failed`.
- `delete`: validate name; chặn nếu running/in-use; `avdmanager delete avd -n <name>`; xác nhận đã biến mất khỏi `-list-avds`.

Discovery và port allocator (cùng Task 2):

```swift
public struct EmulatorDiscovery: Sendable, Equatable {
    public let pid: Int32
    public let grpcPort: Int
    public let token: String
    public let consolePort: Int?
    public let avdName: String?
    public static func read(avdHome: URL, pid: Int32, fileManager: FileManager = .default) throws -> EmulatorDiscovery
    public static func wait(avdHome: URL, pid: Int32, timeout: Duration = .seconds(30)) async throws -> EmulatorDiscovery
}

public struct EmulatorPortAllocator: EmulatorPortAllocating {
    public init()
    public func freeGRPCPort() throws -> Int
}
```

`EmulatorDiscovery` đọc `<avdHome>/running/pid_<pid>.ini`, parse `key=value`; bắt buộc có `grpc.port` và `grpc.token`; `consolePort` lấy từ `port`/`adb.port` nếu có. Kiểm tra file `0600` (owner read/write, không group/other); token không được đưa vào error/log. `wait` poll mỗi 100 ms đến timeout. `freeGRPCPort` bind `127.0.0.1:0`, đọc port, đóng socket, retry 5 lần; chỉ dùng cho gRPC, không dùng cho `-port`.

`AndroidDeviceService.listDevices()` map **tất cả** AVD (kể cả đã tắt) thành `Device`; AVD đang chạy được enrich serial/grpc port, AVD đã tắt vẫn phải xuất hiện để `device_boot`/New Simulator chọn được. State: `shutdown` khi process không chạy, `booting` khi process sống nhưng `sys.boot_completed != 1`, `booted` khi cả hai đều true. AVD home lấy từ `ANDROID_AVD_HOME`, `ANDROID_USER_HOME/avd`, rồi `~/.android/avd`; không hardcode path. Mapping:

```swift
Device(
    id: DeviceID(rawValue: "android:\(avd.name)"),
    name: avd.name,
    platform: .android,
    deviceType: avd.deviceType,
    runtime: RuntimeID(rawValue: avd.systemImage),
    state: switch avd.state {
    case .running: .booted
    case .booting: .booting
    case .stopped: .shutdown
    },
    isAvailable: true,
    dataPath: avd.dataPath,
    lastBootedAt: avd.lastBootedAt
)
```

Test bắt buộc: `create` cùng tên trả `device_name_conflict` và không gọi `avdmanager`; `create` gửi stdin `no\n`; `boot` không có `-port`; erase khi running trả `device_busy` (integration test); teardown không xoá AVD không do test tạo.

- [ ] **Step 3: Chạy test xanh + integration skip**

```bash
swift test --filter OpenSimAndroidTests.AndroidAVDTests
OPENSIM_INTEGRATION=1 swift test --filter AndroidIntegrationTests
```

Expected: unit PASS; integration SKIP với `BLOCKED: no Android AVD` nếu máy chưa có AVD.

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenSimAndroid/AndroidAVDService.swift Sources/OpenSimAndroid/AndroidDeviceService.swift Sources/OpenSimAndroid/EmulatorDiscovery.swift Sources/OpenSimAndroid/EmulatorPortAllocator.swift Tests/OpenSimAndroidTests/AndroidAVDTests.swift
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
import XCTest
import OpenSimCore
@testable import OpenSimAndroid

final class AndroidAdbTests: XCTestCase {
    private final class RecordingRunner: AndroidCommandRunning, @unchecked Sendable {
        var last: AndroidCommand?
        func run(_ command: AndroidCommand) async throws -> CommandOutput {
            last = command
            return CommandOutput(exitCode: 0, stdout: Data(), stderr: "")
        }
        func start(_ command: AndroidCommand) async throws -> AndroidProcessHandle {
            throw OpenSimError(code: .internalError, message: "not used")
        }
    }

    func testInstallUsesArgumentArray() async throws {
        let runner = RecordingRunner()
        let service = AndroidAppService(adb: URL(fileURLWithPath: "/tmp/adb"), runner: runner)
        _ = try await service.install(serial: "emulator-5554", apkPath: "/tmp/app.apk", reinstall: true)
        XCTAssertEqual(runner.last?.arguments, ["-s", "emulator-5554", "install", "-r", "/tmp/app.apk"])
    }
}
```

- [ ] **Step 2: Implement**

- `list`: `adb -s <serial> shell pm list packages -3`; map package name.
- `install`: `adb -s <serial> install -r <path>`; reject non-`.apk` path via allowlist.
- `uninstall`: `adb -s <serial> uninstall <bundleID>`.
- `launch`: `adb -s <serial> shell am start -n <package>/<activity>`; resolve activity qua `cmd package resolve-activity --brief`.
- `terminate`: `adb -s <serial> shell am force-stop <package>`.
- `info`: `adb shell dumpsys package <package>` parse versionName/versionCode/label.
- `log`: dùng `start` cho `adb -s <serial> logcat -v threadtime` stream; tail dùng `-t <limit>` và cursor timestamp. Stream cancel phải terminate handle.
- Không dùng `Runtime.exec`/shell string; không chạy logcat qua `run` (process không exit).

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
- Create: `Sources/OpenSimAndroid/AndroidScreenService.swift`, `AndroidInputService.swift`, `AndroidImageProcessor.swift`, `AndroidKeyMap.swift`, `AndroidInputText.swift`
- Test: `Tests/OpenSimAndroidTests/AndroidInputTests.swift`

**Interfaces:**
- Consumes: `ScreenControlling`, `InputControlling`, `ScreenInfo`, `Screenshot`, `Point`, `Key`, `KeyModifiers`, `HardwareButton`.
- Produces: `AndroidScreenService.screenshot`, `.screenInfo`; `AndroidInputService.tap/swipe/longPress/drag/scroll/type/key/button`; `AndroidImageProcessor.process(png:format:scale:quality:)`; `AndroidKeyMap.keyCode(for:)`, `.keyEvent(for:)`, `.rotationCommand`; `AndroidInputText.escape(_:)`, `.asciiOnly(_:)`.

- [ ] **Step 1: Test screenshot, text và key**

```swift
import XCTest
import ImageIO
import UniformTypeIdentifiers
import OpenSimCore
@testable import OpenSimAndroid

final class AndroidInputTests: XCTestCase {
    private final class RecordingRunner: AndroidCommandRunning, @unchecked Sendable {
        var stdout = Data()
        var last: AndroidCommand?
        func run(_ command: AndroidCommand) async throws -> CommandOutput {
            last = command
            return CommandOutput(exitCode: 0, stdout: stdout, stderr: "")
        }
        func start(_ command: AndroidCommand) async throws -> AndroidProcessHandle {
            throw OpenSimError(code: .internalError, message: "not used")
        }
    }

    func testDefaultScreenshotIsJPEGAtHalfScale() throws {
        let source = try makePNG(width: 4, height: 2)
        let output = try AndroidImageProcessor.process(png: source, format: .jpeg, scale: 0.5, quality: 80)
        XCTAssertEqual(output.format, .jpeg)
        XCTAssertEqual(output.width, 2)
        XCTAssertEqual(output.height, 1)
        let bytes = try XCTUnwrap(output.data)
        XCTAssertEqual(Array(bytes.prefix(2)), [0xFF, 0xD8])
    }

    func testScreenshotUsesExecOutPNGThenConverts() async throws {
        let runner = RecordingRunner()
        runner.stdout = try makePNG(width: 4, height: 2)
        let service = AndroidScreenService(adb: URL(fileURLWithPath: "/tmp/adb"), runner: runner, serialProvider: { _ in "emulator-5554" })
        _ = try await service.screenshot(on: DeviceID(rawValue: "android:Pixel_9_API_36"), format: .jpeg, scale: 0.5, quality: 80)
        XCTAssertEqual(runner.last?.arguments, ["-s", "emulator-5554", "exec-out", "screencap", "-p"])
    }

    func testTextEscapingAndUnicodeFallback() throws {
        XCTAssertEqual(AndroidInputText.escape("hello world"), "hello%sworld")
        XCTAssertEqual(AndroidInputText.escape("a'b"), "a'\\''b")
        XCTAssertThrowsError(try AndroidInputText.asciiOnly("xin chào")) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, ErrorCode.capabilityUnavailable.rawValue)
        }
    }

    func testAndroidKeyMapUsesKeyNamesNotAppleHID() throws {
        XCTAssertEqual(AndroidKeyMap.keyEvent(for: .back), 4)
        XCTAssertEqual(AndroidKeyMap.keyEvent(for: .overview), 187)
        XCTAssertEqual(AndroidKeyMap.keyEvent(for: .power), 26)
        XCTAssertEqual(AndroidKeyMap.keyEvent(for: .home), 3)
        XCTAssertEqual(AndroidKeyMap.keyCode(for: Key(name: "return", keyCode: 40)), 66)
        XCTAssertEqual(AndroidKeyMap.keyCode(for: Key(name: "a", keyCode: nil)), 29)
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
```

- [ ] **Step 2: Implement**

- Serial resolve: `Android:<avdName>` → running emulator serial từ `AndroidAVDService`/adb; `AndroidScreenService(adb:runner:serialProvider:)` và `AndroidInputService(adb:runner:serialProvider:)` inject provider để test, không đoán `emulator-5554`.
- Screen: `adb -s <serial> exec-out screencap -p`; trả PNG data; nếu gRPC có `getScreenshot`, dùng nó trước. `AndroidImageProcessor` dùng ImageIO: decode PNG, resize theo `scale` (0.1...1.0), encode `.png` hoặc `.jpeg` với `quality ?? 80`; default MCP JPEG 80 scale 0.5 phải chạy, không reject. `screenInfo.width/height` là pixel từ `wm size`; `scale = density / 160`; input dùng pixel, không dùng `scale` để map touch.
- Tap/swipe/long-press/drag: `adb shell input tap x y`, `swipe x1 y1 x2 y2 durationMs`; long press dùng swipe cùng điểm với duration; drag dùng swipe duration dài. `tap(on:at:settle:)` honor `settle` và trả `capability_unavailable` cho pinch/rotate nếu gRPC chưa có.
- Type: ASCII dùng `adb shell input text <escaped>` với `AndroidInputText.escape` (space → `%s`, escape `'` cho remote shell); `AndroidInputText.asciiOnly` ném `capability_unavailable` nếu chuỗi có ký tự non-ASCII. Unicode dùng gRPC `sendText` nếu có, nếu không trả `capability_unavailable` với recovery "dùng ASCII hoặc bật gRPC". Không gửi Unicode qua `input text`.
- Key/button: `AndroidKeyMap` map `Key.name` (return/escape/tab/delete/space/arrow*/chữ/số) sang Android keycode; bỏ qua `Key.keyCode` Apple HID. `HardwareButton`: home 3, back 4, overview 187, power 26, volumeUp 24, volumeDown 25; `.rotate` chạy `adb -s <serial> emu rotate`; `.lock`/`.side`/AppleTV trả `capability_unavailable`.
- Scroll: `input swipe` trong vùng screen.
- Multi-touch/pinch/rotate: adb fallback trả `capability_unavailable("android-grpc")`; gRPC Task 6 hỗ trợ.
- Screenshot polling fallback dùng Task 9 `AndroidScreenHost`; tần suất thấp, doctor ghi rõ.

- [ ] **Step 3: Chạy test xanh**

```bash
swift test --filter OpenSimAndroidTests.AndroidInputTests
```

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenSimAndroid/AndroidScreenService.swift Sources/OpenSimAndroid/AndroidInputService.swift Sources/OpenSimAndroid/AndroidImageProcessor.swift Sources/OpenSimAndroid/AndroidKeyMap.swift Sources/OpenSimAndroid/AndroidInputText.swift Tests/OpenSimAndroidTests/AndroidInputTests.swift
git commit -m "feat(android): add adb screen and input fallback"
```
---

### Task 5: Accessibility tree từ uiautomator

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidAccessibilityService.swift`, `Sources/OpenSimAndroid/AndroidUIAutomatorXML.swift`
- Test: `Tests/OpenSimAndroidTests/AndroidAccessibilityTests.swift`, fixture XML.

**Interfaces:**
- Consumes: `AccessibilityReading.find`, `UIElement`, `ElementSelector`.
- Produces: `AndroidAccessibilityService.find(on:selector:)`, `.tree(on:maxDepth:maxNodes:)`.

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
import XCTest
import OpenSimCore
@testable import OpenSimAndroid

final class AndroidAccessibilityTests: XCTestCase {
    private let fixture = """
    <hierarchy rotation="0">
      <node index="0" text="" resource-id="" class="android.widget.FrameLayout" package="dev.opensim.fixture" content-desc="" clickable="false" bounds="[0,0][1080,2400]">
        <node index="0" text="Login" resource-id="dev.opensim.fixture:id/login" class="android.widget.Button" package="dev.opensim.fixture" content-desc="login-button" clickable="true" bounds="[40,200][400,280]" />
      </node>
    </hierarchy>
    """

    func testParsesBoundsAndIdentifiers() throws {
        let tree = try AndroidUIAutomatorXML.parse(Data(fixture.utf8))
        let button = try XCTUnwrap(tree.first { $0.identifier == "dev.opensim.fixture:id/login" })
        XCTAssertEqual(button.label, "Login")
        XCTAssertEqual(button.frame, Rect(x: 40, y: 200, width: 360, height: 80))
        XCTAssertTrue(button.enabled)
    }
}
```

- [ ] **Step 2: Implement**

- `AndroidAccessibilityService(adb:runner:serialProvider:)` inject serial resolver cho test. Chạy `adb -s <serial> shell uiautomator dump /dev/tty`; nếu output có preamble, cắt từ `<hierarchy`.
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
- Create: `Sources/OpenSimAndroid/EmulatorGRPCClient.swift`, `Sources/OpenSimAndroid/AndroidFrame.swift`, `Sources/OpenSimAndroid/Generated/` (checked-in stubs)
- Modify: `Package.swift` (grpc-swift-2/nio-transport/protobuf), `AndroidScreenService.swift`, `AndroidInputService.swift`
- Test: `Tests/OpenSimAndroidTests/AndroidGRPCTests.swift`

**Interfaces:**
- Consumes: `emulator_controller.proto` service `android.emulation.control.EmulatorController`, methods `getScreenshot`, `streamScreenshot`, `sendTouch`, `sendKey`, `getStatus`; `EmulatorDiscovery` từ Task 2.
- Produces: `EmulatorGRPCClient.connect(port:token:)`, `.frameStream()`, `.sendTouch(_:)`, `.sendKey(_:)`, `.status()`; `AndroidFrame`; `EmulatorGRPCAuth.authorizationHeader(token:)`. Không conform `DisplaySurface`; app target tự dựng view host.

```swift
public struct AndroidFrame: Sendable, Equatable {
    public let data: Data
    public let width: Int
    public let height: Int
    public let capturedAt: Date
}

public enum EmulatorGRPCAuth {
    public static func authorizationHeader(token: String) -> String { "Bearer \(token)" }
}

public enum AndroidTouchAction: Sendable { case down, move, up, cancel }

public struct AndroidTouchPoint: Sendable, Equatable {
    public let id: Int
    public let x: Int
    public let y: Int
}

public struct AndroidTouchEvent: Sendable, Equatable {
    public let points: [AndroidTouchPoint]
    public let action: AndroidTouchAction
}
```

- [ ] **Step 1: Package và generated stubs**

`Package.swift` thêm đúng ba package (pin version trong `Package.resolved`):

```swift
.package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.0.0"),
.package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.0.0"),
.package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.0.0"),
```

Giữ product/target/test target đã tạo ở Task 1; chỉ thay dependencies của target `OpenSimAndroid` thành `OpenSimCore` + 3 product gRPC; **không** phụ thuộc `OpenSimBridge`, `OpenSimBridgeUI`, `OpenSimDaemon`:

```swift
.target(
    name: "OpenSimAndroid",
    dependencies: [
        "OpenSimCore",
        .product(name: "GRPCCore", package: "grpc-swift-2"),
        .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
        .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf")
    ]
),
.testTarget(name: "OpenSimAndroidTests", dependencies: ["OpenSimAndroid", "OpenSimCore"])
```

Use the proto from the installed emulator (`$ANDROID_SDK/emulator/lib/emulator_controller.proto`) or Google's prebuilt mirror. Generate Swift/protobuf/gRPC stubs with the pinned `protoc`/plugins, commit under `Sources/OpenSimAndroid/Generated/`. Do not generate during normal build; users need no protoc.

- [ ] **Step 2: Test discovery auth và touch payload**

```swift
import XCTest
import OpenSimCore
@testable import OpenSimAndroid

final class AndroidGRPCTests: XCTestCase {
    func testReadsDiscoveryTokenAndRejectsLoosePermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let running = root.appendingPathComponent("running", isDirectory: true)
        try FileManager.default.createDirectory(at: running, withIntermediateDirectories: true)
        let file = running.appendingPathComponent("pid_4242.ini")
        try "grpc.port=8554\ngrpc.token=secret-token\navd.name=Pixel_9_API_36\n"
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)

        let discovery = try EmulatorDiscovery.read(avdHome: root, pid: 4242)
        XCTAssertEqual(discovery.grpcPort, 8554)
        XCTAssertEqual(discovery.token, "secret-token")
        XCTAssertEqual(discovery.avdName, "Pixel_9_API_36")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertThrowsError(try EmulatorDiscovery.read(avdHome: root, pid: 4242)) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, ErrorCode.grpcUnavailable.rawValue)
        }
    }

    func testAuthorizationUsesBearerToken() {
        XCTAssertEqual(EmulatorGRPCAuth.authorizationHeader(token: "secret-token"), "Bearer secret-token")
    }

    func testTouchPayloadContainsAllPointers() throws {
        let event = AndroidTouchEvent(points: [
            AndroidTouchPoint(id: 0, x: 100, y: 200),
            AndroidTouchPoint(id: 1, x: 300, y: 400)
        ], action: .down)
        XCTAssertEqual(event.points.count, 2)
    }
}
```

- [ ] **Step 3: Implement client**

- Boot emulator với `-grpc <port> -grpc-use-token` (Task 2). **Không** tự sinh token, không dùng `-grpc-use-jwt` trong Plan 10. Sau khi process lên, đọc `EmulatorDiscovery` theo PID; token chỉ nằm trong memory/discovery path, không log. Bind/probe `127.0.0.1`; token sai/thiếu → `grpc_unavailable`, không retry vô hạn.
- `frameStream`: consume `streamScreenshot`; decode image; phát `AndroidFrame` qua `AsyncStream` với `.bufferingNewest(1)`; consumer chậm thì drop frame cũ, không buffer vô hạn. `AndroidScreenHost` (Task 9) là nơi render; `OpenSimAndroid` không import AppKit/OpenSimBridge.
- `sendTouch`: map `SimulatorGesture` touch points to `TouchEvent`; multi-touch supported; `sendKey`/`sendText` (nếu proto có) cho keyboard.
- Fallback: nếu discovery/token/probe fail hoặc emulator không hỗ trợ `-grpc-use-token`, set `grpcReady = false`, dùng adb screen/input fallback; UI/doctor hiện notice. Không mở gRPC không auth; không tự tạo token giả.
- Probe `getStatus` sau boot; chỉ đánh dấu `grpcReady` khi thành công. Test bắt buộc: `testPortCollisionRetriesWithNewGRPCPort` (fake allocator trả 8554 rồi 8556, process đầu exit bind error), `testTwoAVDsUseDistinctPortsAndSerials`, `testDaemonRestartRediscoverFromDiscoveryFile`, `testBadTokenReturnsGRPCUnavailable`; real emulator test `XCTSkip` khi không có AVD.

- [ ] **Step 4: Test + skip**

```bash
swift test --filter OpenSimAndroidTests.AndroidGRPCTests
```

Expected: parser/auth/touch tests PASS; real emulator gRPC test SKIP when no AVD.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Package.resolved Sources/OpenSimAndroid/EmulatorGRPCClient.swift Sources/OpenSimAndroid/AndroidFrame.swift Sources/OpenSimAndroid/Generated Tests/OpenSimAndroidTests/AndroidGRPCTests.swift
git commit -m "feat(android): add emulator gRPC screen and touch"
```
---

### Task 7: System image management

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidSystemImageService.swift`, `Sources/OpenSimCore/Domain/Android.swift`
- Test: `Tests/OpenSimAndroidTests/AndroidSystemImageTests.swift`

**Interfaces:**
- Consumes: `sdkmanager --list`, `sdkmanager --install`, `sdkmanager --uninstall`, license files; `AndroidIdentifier`.
- Produces: `AndroidSystemImage`; `AndroidSystemImageService.list()`, `.install(packagePath:acceptLicense:progress:)`, `.uninstall(packagePath:)` (progress có default no-op).

```swift
public struct AndroidSystemImage: Codable, Sendable, Equatable, Identifiable {
    public var id: String { packagePath }
    public let packagePath: String
    public let apiLevel: Int
    public let tag: String
    public let abi: String
    public let installed: Bool
    public let licenseAccepted: Bool
    public let displayName: String
    public let sizeBytes: Int64?

    public init(
        packagePath: String,
        apiLevel: Int,
        tag: String,
        abi: String,
        installed: Bool,
        licenseAccepted: Bool,
        displayName: String,
        sizeBytes: Int64? = nil
    ) {
        self.packagePath = packagePath
        self.apiLevel = apiLevel
        self.tag = tag
        self.abi = abi
        self.installed = installed
        self.licenseAccepted = licenseAccepted
        self.displayName = displayName
        self.sizeBytes = sizeBytes
    }
}
```

- [ ] **Step 1: Test package parsing**

```swift
import XCTest
import OpenSimCore
@testable import OpenSimAndroid

final class AndroidSystemImageTests: XCTestCase {
    private final class FakeRunner: AndroidCommandRunning, @unchecked Sendable {
        var commands: [AndroidCommand] = []
        func run(_ command: AndroidCommand) async throws -> CommandOutput {
            commands.append(command)
            return CommandOutput(exitCode: 0, stdout: Data(), stderr: "")
        }
        func start(_ command: AndroidCommand) async throws -> AndroidProcessHandle {
            throw OpenSimError(code: .internalError, message: "not used")
        }
    }

    private func makeFakeSDK() throws -> AndroidSDK {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let adb = root.appendingPathComponent("platform-tools/adb")
        let emulator = root.appendingPathComponent("emulator/emulator")
        let avdmanager = root.appendingPathComponent("cmdline-tools/latest/bin/avdmanager")
        let sdkmanager = root.appendingPathComponent("cmdline-tools/latest/bin/sdkmanager")
        for executable in [adb, emulator, avdmanager, sdkmanager] {
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
        return AndroidSDK(root: root, adb: adb, emulator: emulator, avdmanager: avdmanager, sdkmanager: sdkmanager, java: nil)
    }

    func testParsesInstalledAndAvailableSystemImages() throws {
        let output = """
        Installed packages:
          system-images;android-36;google_apis;arm64-v8a | 36 | Google APIs ARM 64 v8a
        Available Packages:
          system-images;android-35;google_apis;arm64-v8a | 35 | Google APIs ARM 64 v8a
        """
        let images = try AndroidSystemImageService.parse(output: output)
        XCTAssertTrue(images.contains {
            $0.packagePath == "system-images;android-36;google_apis;arm64-v8a" && $0.installed
        })
        XCTAssertEqual(images.first { $0.packagePath.contains("android-36") }?.apiLevel, 36)
    }

    func testInstallRequiresExplicitLicenseConsent() async throws {
        let runner = FakeRunner()
        let service = AndroidSystemImageService(sdk: try makeFakeSDK(), runner: runner)
        do {
            try await service.install(packagePath: "system-images;android-36;google_apis;arm64-v8a", acceptLicense: false)
            XCTFail("Must require consent")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, ErrorCode.licenseRequired.rawValue)
        }
        XCTAssertTrue(runner.commands.isEmpty)
    }
}
```

- [ ] **Step 2: Implement**

- `list`: `sdkmanager --list`; parse only exact package lines matching `AndroidIdentifier.validateSystemImagePackage`; map `packagePath`, API level (from `android-<n>`), tag, ABI, installed; `licenseAccepted` đọc license file/hash của SDK.
- `install`: validate package; require `acceptLicense == true` và đã hiển thị license text/hash; kiểm tra dung lượng trống (tối thiểu 8 GB) trước khi chạy. Dùng `start` `sdkmanager --install <package>`; đọc stdout/stderr, mỗi lần thấy prompt `[y/N]` ghi `y\n` (tối đa 20 prompt), không dùng `yes` shell, không auto-accept. `progress` nhận dòng tiến độ; Task cancellation hoặc lỗi phải `terminate()` handle và trả `cancelled`/`android_image_unavailable`. Không chạy nền.
- `uninstall`: validate package; chặn nếu bất kỳ AVD nào reference `packagePath`; `sdkmanager --uninstall <package>` sau confirm; không xoá thư mục trực tiếp.
- `AndroidSystemImage` nằm trong Core để daemon/UI dùng chung; `OpenSimAndroid` chỉ parse và trả type này.
- Test bắt buộc: `testMultipleLicensePromptsAreAnswered` (fake process phát 2 prompt `[y/N]`, assert 2 lần ghi `y\n`), `testCancellationTerminatesSdkmanager`, `testPartialInstallFailureDoesNotReportInstalled`.

- [ ] **Step 3: Test/commit**

```bash
swift test --filter OpenSimAndroidTests.AndroidSystemImageTests
git add Sources/OpenSimAndroid/AndroidSystemImageService.swift Sources/OpenSimCore/Domain/Android.swift Tests/OpenSimAndroidTests/AndroidSystemImageTests.swift
git commit -m "feat(android): add system image management"
```
---

### Task 8: Platform adapter, daemon routing, CLI và MCP

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidPlatformAdapter.swift`, `Sources/OpenSimCore/Catalog/AndroidOperations.swift`, `Sources/OpenSimDaemon/Platforms/PlatformRouter.swift`
- Modify: `Package.swift`, `Sources/OpenSimDaemon/Runtime/DaemonRunner.swift`, `Sources/OpenSimCore/Catalog/OpenSimCatalog.swift` (`openSim()`), `Sources/OpenSimDaemon/Operations/OperationDispatcher.swift`, `Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift`, `Sources/OpenSimCore/Validation/DeviceResolver.swift`, `Sources/OpenSimCLI/OpenSimCommand.swift` (`android` subcommand), `Sources/OpenSimMCP` catalog adapter tests.

**Interfaces:**
- Consumes: all Android services, `OperationCatalog`, `OperationDispatcher`, `DeviceResolver`.
- Produces: `AndroidPlatformAdapter` conforms to device/runtime/app/log/screen/input/accessibility protocols; `PlatformRouter` selects Apple/Android by `Device.platform`; `android_avd_*`/`android_system_image_*` operations.

Files bổ sung: `Sources/OpenSimCore/Validation/DeviceResolver.swift` (exact-ID branch), `Sources/OpenSimDaemon/Operations/OperationDispatcher.swift`, `Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift` (routing injection), `Sources/OpenSimCore/Catalog/OpenSimCatalog.swift`.

Operation table:

| Operation | Lease | Destructive | Parameters |
|---|---|---|---|
| `android_avd_list` | no | no | `sdkPath?` |
| `android_avd_create` | no | no | `name`, `deviceType`, `systemImage`; lỗi nếu tên tồn tại |
| `android_avd_boot` | device control | no | `name`, `headless?` |
| `android_avd_shutdown` | device control | no | `name` |
| `android_avd_erase` | device control | yes | `name`, `confirm` |
| `android_avd_delete` | device control | yes | `name`, `confirm` |
| `android_system_image_list` | no | no | `sdkPath?` |
| `android_system_image_install` | no | no | `package`, `acceptLicense` |
| `android_system_image_uninstall` | no | yes | `package`, `confirm` |

Global AVD/image operations require a valid session and audit; boot/shutdown/erase/delete use the device control lease on `android:<name>`. Generic `device_boot`/`device_shutdown` vẫn dùng `device`; Android adapter tự cấp port bên trong, không thêm tham số port vào protocol chung.

Protocol conformance map:

| Protocol method | Android implementation |
|---|---|
| `tree(on:maxDepth:maxNodes:)` | uiautomator XML; cap nodes and return `truncated` |
| `find(on:selector:)` | same parser; selector `id/label/text/role` |
| `tap(on:at:settle:)` | gRPC touch if available, else adb; honor `settle` |
| `swipe/longPress/drag/scroll` | gRPC/adb; unsupported multi-touch returns `capability_unavailable` |
| `pinch/rotate` | gRPC only; adb fallback returns `capability_unavailable` |
| `button` | `AndroidKeyMap`: home/back/overview/power/volume; rotate qua `adb emu rotate`; case Apple/không hỗ trợ trả `capability_unavailable` |
| `screenshot(on:format:scale:quality:)` | screencap/gRPC PNG → ImageIO; hỗ trợ PNG/JPEG, scale 0.1...1.0, quality 0...100; default JPEG 80 scale 0.5 chạy được |
| `screens(for:)` | `wm size` (pixel) + `wm density` (scale = density/160); one Android display |
| `recording start/stop` | `adb shell screenrecord` to app-owned path; cancel stops process |
| `containerPath` | `adb shell pm path <bundleID>`; data path from `run-as` only when debuggable |
| `clone/rename/pair` | `capability_unavailable` in Plan 10 |
| `listRuntimes` | map installed `AndroidSystemImage` → `Runtime` (id = packagePath, platform `.android`, source `.file`, deviceCount) |
| `downloadRuntime(platform:version:)` | `capability_unavailable`; recovery dùng `android_system_image_install` với `package` + `acceptLicense` |
| `installRuntime(at:)` | `capability_unavailable`; Android không nhận `.dmg`, chỉ nhận package system image |
| `deleteRuntime(_:)` | validate package; chặn nếu AVD dùng; gọi `AndroidSystemImageService.uninstall(packagePath:)` |
| `verifyRuntime(_:)` | kiểm tra package installed + thư mục `system-images/...` tồn tại |

`AndroidPlatformAdapter` conform `DeviceControlling`: `boot(_ id:wait:)` với `wait == true` gọi `AndroidAVDService.boot(name:headless: true)` và trả `Device`; `wait == false` gọi `AndroidAVDService.startBoot(name:headless: true)` và trả `Device` state `.booting` ngay; `shutdown/erase/delete` map theo `name`. `android_avd_boot` operation gọi `AndroidAVDService.boot(name:headless:)` trực tiếp để nhận đầy đủ ports/token path. Không đổi signature `DeviceControlling`.

- [ ] **Step 1: Test catalog and routing**

```swift
import XCTest
import OpenSimCore
@testable import OpenSimDaemon

final class AndroidCatalogRoutingTests: XCTestCase {
func testAndroidOperationsAreInUnifiedCatalog() {
    let names = Set(OperationCatalog.openSim().mcpOperations().map(\.mcpName))
    XCTAssertTrue(names.isSuperset(of: ["android_avd_list", "android_avd_create", "android_system_image_list"]))
    XCTAssertTrue(names.contains("ui_tap"))
    XCTAssertTrue(names.contains("storage_scan"))
    XCTAssertTrue(names.contains("perf_devices"))
}

func testRouterSelectsAndroidByDeviceID() {
    XCTAssertEqual(PlatformRouter.platform(for: DeviceID(rawValue: "android:Pixel_9")), .android)
    XCTAssertEqual(PlatformRouter.platform(for: DeviceID(rawValue: "95B3747B-7065-447E-AB1E-53065142C3FC")), .iOS)
}

private final class FakeAndroidRuntime: RuntimeControlling {
    func listRuntimes() async throws -> [Runtime] {
        [Runtime(
            id: RuntimeID(rawValue: "system-images;android-36;google_apis;arm64-v8a"),
            name: "Android 36 · google_apis · arm64-v8a",
            platform: .android,
            version: "36",
            build: "google_apis;arm64-v8a",
            isAvailable: true,
            path: "/tmp/system-images/android-36/google_apis/arm64-v8a",
            sizeBytes: nil,
            source: .file,
            deviceCount: 0
        )]
    }
    func downloadRuntime(platform: Platform, version: String) async throws -> Runtime {
        throw OpenSimError(code: "capability_unavailable", message: "Use android_system_image_install", recovery: "Pass a system-image package and acceptLicense", retryable: false)
    }
    func installRuntime(at path: String) async throws -> Runtime {
        throw OpenSimError(code: "capability_unavailable", message: "Android does not accept .dmg", recovery: "Use android_system_image_install", retryable: false)
    }
    func deleteRuntime(_ id: RuntimeID) async throws {}
    func verifyRuntime(_ id: RuntimeID) async throws {}
}

func testAndroidRuntimeAPIUsesPackagesAndCapabilityErrors() async throws {
    let runtime = FakeAndroidRuntime()
    let images = try await runtime.listRuntimes()
    XCTAssertEqual(images.first?.id.rawValue, "system-images;android-36;google_apis;arm64-v8a")
    do {
        _ = try await runtime.downloadRuntime(platform: .android, version: "36")
        XCTFail("Android download must be capability_unavailable")
    } catch let error as OpenSimError {
        XCTAssertEqual(error.code, ErrorCode.capabilityUnavailable.rawValue)
    }
    do {
        _ = try await runtime.installRuntime(at: "/tmp/runtime.dmg")
        XCTFail("Android install(.dmg) must be capability_unavailable")
    } catch let error as OpenSimError {
        XCTAssertEqual(error.code, ErrorCode.capabilityUnavailable.rawValue)
    }
}
}
```

- [ ] **Step 2: Implement routing**

- Package graph: `OpenSimDaemon` thêm dependency `OpenSimAndroid` (adapter/router), `IntegrationTests` thêm `OpenSimAndroid`, `OpenSimAndroidTests` là test target riêng; `OpenSimCLI`/`OpenSimMCP` chỉ dùng Core/Daemon client, không import trực tiếp adapter. App product thêm ở Task 9. Không tạo target thứ hai cho Android.

Thêm `OpenSimAndroid` vào danh sách dependencies hiện có của target `OpenSimDaemon` và `IntegrationTests`; giữ nguyên các dependency cũ, không thay thế danh sách.
- `OperationCatalog.openSim()` là factory duy nhất. Sửa `Sources/OpenSimCore/Catalog/OpenSimCatalog.swift` để gọi `registerAndroidOperations()`; nếu Plan 9 đã có, giữ `registerPhysicalOperations()`. Không tạo `plan10()`/catalog thứ hai.
- Android operations metadata nằm trong `OpenSimCore`, không import `OpenSimAndroid` từ Core; adapter chỉ implement handler/service.
- `PlatformRouter` gets platform from device prefix (`android:`) or explicit `platform` parameter; Apple IDs remain UUID. Thêm static pure `PlatformRouter.platform(for: DeviceID) -> Platform` để test không cần fake bridge. `DeviceResolver` exact-ID branch phải nhận `android:<avdName>` trước UUID validation; AVD name không bị ép thành UUID.
- `OperationDispatcher`/`BridgeOperationExecutor` route device-scoped ops to the adapter; global `android_*` ops go to `AndroidPlatformAdapter`.
- `AndroidPlatformAdapter` conform `DeviceControlling`: `boot(_:wait:)` với `wait == true` gọi `AndroidAVDService.boot(name:headless: true)`; `wait == false` gọi `AndroidAVDService.startBoot(name:headless: true)` và trả `Device` state `.booting` ngay, không chờ. Các method `shutdown/erase/delete` map theo `name`; adapter tự cấp port, không thêm tham số vào protocol chung.
- `AndroidPlatformAdapter` conform `RuntimeControlling`: `listRuntimes` map `AndroidSystemImage` → `Runtime`; `downloadRuntime`/`installRuntime(at:)` trả `capability_unavailable`; `deleteRuntime`/`verifyRuntime` map package và chặn AVD đang dùng.
- `sdkPath`: `AndroidSDK.detect(sdkPath:)` là nguồn duy nhất; adapter resolve `sdkPath` cho global ops `android_avd_list`/`android_system_image_list`, device ops dùng SDK đã cấu hình. Nếu `sdkPath` khác SDK của device đang chạy, trả `invalid_argument` thay vì âm thầm đổi.
- Lease/audit unchanged: `session_acquire` on Android device ID; control lease per AVD; delete/erase destructive confirm. Erase/delete recheck running/in-use ngay trước khi chạy.
- CLI: `opensim --sdk <path> android avd list/create/boot/shutdown/erase/delete`, `opensim --sdk <path> android system-image list/install/uninstall`; device/runtime/app/ui commands accept `--platform android` or Android device name. JSON dùng `name` cho `android_avd_*`.
- MCP: same operation names/schema; no `android_*` tool duplicates for device/ui/app/log; thêm golden test cho `name` và thiếu `device`.
- Error codes: `android_sdk_not_found`, `avd_not_found`, `device_name_conflict`, `device_busy`, `emulator_failed`, `adb_failed`, `android_image_unavailable`, `license_required`, `grpc_unavailable`, `capability_unavailable`, `storage_in_use`, `stale_plan`.

- [ ] **Step 3: Test/commit**

```bash
swift test --filter OpenSimAndroidTests
swift test --filter OpenSimMCPTests
git add Package.swift Sources/OpenSimAndroid/AndroidPlatformAdapter.swift Sources/OpenSimCore/Catalog/AndroidOperations.swift Sources/OpenSimCore/Catalog/OpenSimCatalog.swift Sources/OpenSimCore/Validation/DeviceResolver.swift Sources/OpenSimDaemon/Platforms Sources/OpenSimDaemon/Operations/OperationDispatcher.swift Sources/OpenSimDaemon/Runtime/DaemonRunner.swift Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift Sources/OpenSimCLI/OpenSimCommand.swift Sources/OpenSimMCP Tests/OpenSimMCPTests
git commit -m "feat(android): route daemon cli and mcp operations"
```
---

### Task 9: macOS app platform support

**Files:**
- Create: `App/Sources/OpenSimApp/Windows/AndroidScreenHost.swift`
- Modify: `App/project.yml` (thêm product `OpenSimAndroid`), `App/Sources/OpenSimApp/App/AppEnvironment.swift`, `App/Sources/OpenSimApp/App/BridgeHandles.swift`, `App/Sources/OpenSimApp/Sidebar/DeviceCatalogModel.swift`, `App/Sources/OpenSimApp/Devices/DevicesView.swift`, `App/Sources/OpenSimApp/Devices/NewDeviceModel.swift`, `App/Sources/OpenSimApp/Runtimes/RuntimeModel.swift`, `App/Sources/OpenSimApp/Runtimes/RuntimesView.swift`, `App/Sources/OpenSimApp/Windows/DeviceWindowModel.swift`, `App/Sources/OpenSimApp/Windows/DeviceWindowRoot.swift`, `App/Sources/OpenSimApp/Windows/SimulatorScreenContainerView.swift`, `App/Sources/OpenSimApp/Windows/DeviceToolbar.swift`, `App/Sources/OpenSimApp/Settings/DaemonSettingsView.swift`, `App/Sources/OpenSimApp/Settings/CapabilitiesSettingsView.swift`
- Test: `Tests/OpenSimAppUITests/AndroidUITests.swift`

**Interfaces:**
- Consumes: `Platform.android`, Android doctor/runtime/device metadata, `AndroidFrame`, `AndroidPlatformAdapter`.
- Produces: project dependency `OpenSimAndroid`; platform filter, Android device type/runtime picker, Android rows in Runtimes, Android SDK settings/doctor, Android device window controls.

- [ ] **Step 1: UI test**

```swift
import XCTest

final class AndroidUITests: XCTestCase {
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
}
```

- [ ] **Step 2: Implement**

Thêm dependency app target (XcodeGen sẽ regenerate project):

```yaml
# App/project.yml, dưới dependencies của target OpenSim
- package: OpenSimPackage
  product: OpenSimAndroid
```

- `DeviceCatalogModel` (trong `Sidebar/`) exposes `platformFilter`; `DevicesView` Picker All/Apple/Android; Android row icon `smartphone` (SF Symbol).
- New Simulator adds platform Picker (Apple/Android), device type Picker (Pixel 9/Pixel 9 Pro/Tablet), system image Picker; Android Create disabled if SDK/AVD image missing; note links to Runtimes/Doctor.
- Runtimes adds Android system-image rows (`API 36 · google_apis · arm64-v8a`, installed/not, size, AVD count); Install requires license consent.
- `BridgeHandles` thêm `android: AndroidPlatformAdapter?`; `AppEnvironment` khởi tạo adapter khi SDK detect được. `DeviceWindowModel` chọn `AndroidScreenHost` khi `device.platform == .android`, không dùng `SimulatorScreenView`/`displayBridge` Apple cho Android.
- `AndroidScreenHost` là `NSView` trong app target, consume `AndroidFrame`/`frameStream` và render bằng Core Animation; không conform `DisplaySurface`, không import `OpenSimBridge`. Nếu gRPC unavailable, screenshot polling với capability note rõ ràng.
- Input Android đi qua `AndroidPlatformAdapter` **sau** `requireControlLease()`; không bypass lease/audit. Toolbar Back/Home/Overview/Power/Rotate dùng `HardwareButton` case mới; keyboard/paste qua adb/gRPC.
- Settings > Daemon: Android SDK path, adb/emulator/avdmanager/Java status, Choose path; Capabilities > Doctor: Android rows `androidSdk`, `adb`, `avdmanager`, `emulatorGrpc`, `androidA11y` + missing-SDK/gRPC recovery.
- Screenshot Android dùng default JPEG 80 scale 0.5; UI preview không gọi raw PNG trừ khi cần.
- No new visual system; use existing native Table/List/Form/Gauge/Chart.

- [ ] **Step 3: Build + test/commit**

```bash
(cd App && xcodegen generate)
xcodebuild build -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS'
xcodebuild test -project App/OpenSim.xcodeproj -scheme OpenSim -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OpenSimAppUITests/AndroidUITests
git add App/project.yml App/OpenSim.xcodeproj App/Sources/OpenSimApp Tests/OpenSimAppUITests/AndroidUITests.swift
git commit -m "feat(app): add android platform surfaces"
```
---

### Task 10: Android storage và metrics

**Files:**
- Create: `Sources/OpenSimAndroid/AndroidStorageService.swift`, `AndroidMetricsService.swift`, `Sources/OpenSimDaemon/Storage/AndroidStorageSource.swift`, `Sources/OpenSimCore/Storage/AndroidStorageExecuting.swift`, `Sources/OpenSimDaemon/Storage/AndroidCleanValidator.swift`
- Modify: `Sources/OpenSimCore/Domain/Storage.swift` (enum), `Sources/OpenSimCore/Storage/StorageCategoryMetadata.swift`, `Sources/OpenSimCore/Storage/StorageSafety.swift`, `Sources/OpenSimDaemon/Storage/StorageRoots.swift`, `Sources/OpenSimDaemon/Storage/CleanPlanStore.swift`, `Sources/OpenSimDaemon/Storage/CleanExecutor.swift`, `Sources/OpenSimDaemon/Storage/StorageService.swift`, `Sources/OpenSimDaemon/Metrics/MetricsSampler.swift`, Plan 4 storage UI.
- Test: `Tests/OpenSimDaemonTests/AndroidStorageTests.swift`

**Interfaces:**
- Consumes: AVD data paths, SDK system images, host process table, adb, lease/session state.
- Produces: `AndroidStorageExecuting` (Core), `AndroidCleanValidator` (Daemon), storage categories `.androidAVD`, `.androidSystemImage`; metrics samples for running AVDs.

```swift
public protocol AndroidStorageExecuting: Sendable {
    func avdFingerprint(name: String) async throws -> String
    func isAVDRunning(name: String) async throws -> Bool
    func deleteAVD(name: String, expectedFingerprint: String) async throws
    func isSystemImageReferenced(packagePath: String) async throws -> Bool
    func uninstallSystemImage(packagePath: String) async throws
}

public enum AndroidCleanValidator {
    /// Recheck target + fingerprint + running/reference ngay trước khi xoá; fail closed.
    public static func validate(snapshot: CleanPlanItemSnapshot, storage: any AndroidStorageExecuting) async throws
}
```

`CleanPlanItemSnapshot` thêm các field optional, **có default `nil` ở cuối init** để không phá call site Plan 5:

```swift
public var androidAVDName: String?
public var androidSystemImagePackage: String?
public var androidAVDDataPath: String?
public var androidAVDFingerprint: String?
```

- [ ] **Step 1: Test safety**

```swift
import XCTest
@testable import OpenSimCore
@testable import OpenSimDaemon

final class AndroidStorageTests: XCTestCase {
    private final class FakeAndroidStorage: AndroidStorageExecuting, @unchecked Sendable {
        var fingerprint = "new"
        var running = false
        var referenced = false
        func avdFingerprint(name: String) async throws -> String { fingerprint }
        func isAVDRunning(name: String) async throws -> Bool { running }
        func deleteAVD(name: String, expectedFingerprint: String) async throws {}
        func isSystemImageReferenced(packagePath: String) async throws -> Bool { referenced }
        func uninstallSystemImage(packagePath: String) async throws {}
    }

    private func avdSnapshot(fingerprint: String) -> CleanPlanItemSnapshot {
        CleanPlanItemSnapshot(
            itemID: "avd-1",
            category: .androidAVD,
            path: "/tmp/Pixel_9.avd",
            sizeBytes: 1_024,
            modificationTime: Date(),
            action: .androidAVDDelete,
            simulatorUDID: nil,
            bundleID: nil,
            runtimeIdentifier: nil,
            androidAVDName: "Pixel_9",
            androidSystemImagePackage: nil,
            androidAVDDataPath: "/tmp/Pixel_9.avd",
            androidAVDFingerprint: fingerprint
        )
    }

    func testRecreatedAVDIsStaleAndNotDeleted() async throws {
        let storage = FakeAndroidStorage()
        storage.fingerprint = "new"
        do {
            try await AndroidCleanValidator.validate(snapshot: avdSnapshot(fingerprint: "old"), storage: storage)
            XCTFail("Must reject recreated AVD")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, ErrorCode.stalePlan.rawValue)
        }
    }

    func testRunningOrReferencedTargetIsStorageInUse() async throws {
        let storage = FakeAndroidStorage()
        storage.fingerprint = "old"
        storage.running = true
        do {
            try await AndroidCleanValidator.validate(snapshot: avdSnapshot(fingerprint: "old"), storage: storage)
            XCTFail("Running AVD must fail")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, ErrorCode.storageInUse.rawValue)
        }

        let image = CleanPlanItemSnapshot(
            itemID: "image-1", category: .androidSystemImage, path: "/sdk/system-images",
            sizeBytes: 1, modificationTime: Date(), action: .androidSystemImageUninstall,
            simulatorUDID: nil, bundleID: nil, runtimeIdentifier: nil,
            androidAVDName: nil,
            androidSystemImagePackage: "system-images;android-36;google_apis;arm64-v8a",
            androidAVDDataPath: nil, androidAVDFingerprint: nil
        )
        storage.referenced = true
        do {
            try await AndroidCleanValidator.validate(snapshot: image, storage: storage)
            XCTFail("Referenced image must fail")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, ErrorCode.storageInUse.rawValue)
        }
    }

    func testMissingTargetFailsBeforeCommand() async throws {
        let storage = FakeAndroidStorage()
        let bad = CleanPlanItemSnapshot(
            itemID: "bad", category: .androidAVD, path: "/tmp/x",
            sizeBytes: 1, modificationTime: Date(), action: .androidAVDDelete,
            simulatorUDID: nil, bundleID: nil, runtimeIdentifier: nil,
            androidAVDName: nil, androidSystemImagePackage: nil,
            androidAVDDataPath: nil, androidAVDFingerprint: nil
        )
        do {
            try await AndroidCleanValidator.validate(snapshot: bad, storage: storage)
            XCTFail("Missing target must fail")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, ErrorCode.invalidArgument.rawValue)
        }
    }
}
```

Test bổ sung (không cần AVD thật): SDK root thiếu `platform-tools/adb`/`emulator/emulator` → từ chối scan; package ngoài regex → `invalid_argument`; inventory lỗi → `inventory_unavailable`, không xoá; AVD stopped nhưng có lease → `storage_in_use`.

- [ ] **Step 2: Implement**

- AVD data lấy từ `ANDROID_AVD_HOME` hoặc `ANDROID_USER_HOME/avd` hoặc `~/.android/avd`; system image `$ANDROID_SDK/system-images/...`; scan allocated size; no auto-clean.
- Thêm case không associated value `androidAVDDelete`, `androidSystemImageUninstall` vào `StorageCleanAction` (enum `String, Codable`). `CleanPlanItemSnapshot` fields optional/default nil như trên; `CleanPlanStore` lưu fingerprint/dataPath vào snapshot.
- `CleanExecutor` thêm dependency optional `android: (any AndroidStorageExecuting)?` (default nil) vào init; case Android gọi `AndroidCleanValidator.validate` rồi `deleteAVD`/`uninstallSystemImage`; thiếu dependency/target trả `invalid_argument`/`internal_error`; không `trashItem` trực tiếp.
- `AndroidStorageExecuting` định nghĩa trong Core để `CleanExecutor` (Daemon) và `AndroidStorageService` (OpenSimAndroid) không tạo dependency vòng.
- `StorageService.verdict(forSnapshot:)` recheck running/lease/reference ngay trước apply; inventory lỗi trả `inventory_unavailable`, không coi là safe. `StorageRoots` canonical hoá SDK/AVD root, resolve symlink, chỉ chấp nhận SDK có `platform-tools/adb` + `emulator/emulator`; package đúng regex `system-images;`.
- Cập nhật mọi switch exhaustive: `StorageCategoryMetadata` (`.androidAVD`, `.androidSystemImage`), `StorageSafety.evaluate` (dùng `isAndroidAVDRunning`/`isAndroidAVDInUse`/`isAndroidSystemImageReferenced`), `CleanPlanStore.confirmationPhrase`, `StorageService.verdict`/`verdict(forSnapshot:)`, `StorageRoots`, storage UI; không thêm `default`.
- Metrics: map `emulator`/`qemu-system-*` theo `-avd <name>` trong argv, dedupe process tree; CPU/RAM; supplement `adb shell dumpsys meminfo`/`top` có cache; unknown group for unmapped.
- UI: Storage rows use category "Android AVD / System images"; Performance table includes Android devices; no separate tab.

- [ ] **Step 3: Commit**

```bash
git add Sources/OpenSimAndroid/AndroidStorageService.swift Sources/OpenSimAndroid/AndroidMetricsService.swift Sources/OpenSimCore/Domain/Storage.swift Sources/OpenSimCore/Storage Sources/OpenSimDaemon/Storage Sources/OpenSimDaemon/Metrics Tests/OpenSimDaemonTests/AndroidStorageTests.swift
git commit -m "feat(android): add storage and metrics"
```
---

### Task 11: Integration fixture, AVD smoke và release gate

**Files:**
- Create: `Fixtures/AndroidFixture/` (Gradle app + prebuilt debug APK), `Tests/IntegrationTests/AndroidIntegrationTests.swift`, `Scripts/android/create-test-avd.sh`
- Modify: `Package.swift` (thêm `OpenSimAndroid` vào deps `IntegrationTests`), `Tests/Release/run-release-gate.sh`, docs.

**Interfaces:**
- Consumes: owner-provided Android SDK/system image/AVD.
- Produces: reproducible smoke test; release gate opt-in for Android.

- [ ] **Step 1: Fixture**

- Minimal Android app with a button (`resource-id` `dev.opensim.fixture:id/primary`), text field, counter label; build debug APK with Gradle; commit the APK or build in CI with JDK 17.
- `create-test-avd.sh` checks `system-images;...` installed; if not, prints exact `sdkmanager` command and exits 2; never downloads.
- Integration AVD name `OpenSim_Test_<UUID>`; teardown chỉ delete khi test đã tạo thành công. Không dùng tên cố định và không ghi đè AVD có sẵn. Script `create-test-avd.sh` preflight tên/image và dừng nếu đã tồn tại.

- [ ] **Step 2: Integration test**

```swift
import XCTest
import OpenSimCore
@testable import OpenSimAndroid

final class AndroidIntegrationTests: XCTestCase {
    private var avdService: AndroidAVDService!
    private var appService: AndroidAppService!
    private var input: AndroidInputService!
    private var accessibility: AndroidAccessibilityService!
    private var createdAVDName: String?

    private var systemImage: String {
        ProcessInfo.processInfo.environment["OPENSIM_ANDROID_SYSTEM_IMAGE"]
            ?? "system-images;android-36;google_apis;arm64-v8a"
    }

    private var fixtureAPK: URL? {
        if let path = ProcessInfo.processInfo.environment["OPENSIM_ANDROID_FIXTURE_APK"] {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "Fixtures/AndroidFixture/app/build/outputs/apk/debug/app-debug.apk")
    }

    override func setUp() async throws {
        try requireAndroid()
        let sdk = try AndroidSDK.detect()
        let runner = AndroidCommandRunner()
        let avd = AndroidAVDService(sdk: sdk, avdHome: AndroidSDK.avdHome(), runner: runner)
        avdService = avd
        appService = AndroidAppService(adb: sdk.adb, runner: runner)
        input = AndroidInputService(adb: sdk.adb, runner: runner, serialProvider: { id in
            try await avd.list().first(where: { $0.deviceID == id })?.serial
        })
        accessibility = AndroidAccessibilityService(adb: sdk.adb, runner: runner, serialProvider: { id in
            try await avd.list().first(where: { $0.deviceID == id })?.serial
        })
    }

    override func tearDown() async throws {
        if let name = createdAVDName {
            try? await avdService.shutdown(name: name)
            try? await avdService.delete(name: name)
        }
        createdAVDName = nil
    }

    func testAndroidLifecycleAndUIActions() async throws {
        let avdName = "OpenSim_Test_\(UUID().uuidString)"
        _ = try await avdService.create(name: avdName, deviceType: "pixel_9", systemImage: systemImage)
        createdAVDName = avdName

        let booted = try await avdService.boot(name: avdName, headless: true)
        let serial = try XCTUnwrap(booted.serial, "Emulator did not expose a serial")
        let apk = try XCTUnwrap(fixtureAPK, "Fixture APK not found")

        try await appService.install(serial: serial, apkPath: apk.path, reinstall: true)
        try await appService.launch(serial: serial, bundleID: "dev.opensim.fixture", activity: ".MainActivity")
        let matches = try await accessibility.find(
            on: booted.deviceID,
            selector: ElementSelector(role: nil, label: nil, identifier: "dev.opensim.fixture:id/primary", text: nil)
        )
        let primary = try XCTUnwrap(matches.first)
        XCTAssertGreaterThan(primary.frame.width, 0)
        let center = Point(
            x: primary.frame.x + primary.frame.width / 2,
            y: primary.frame.y + primary.frame.height / 2
        )
        try await input.tap(on: booted.deviceID, at: center, settle: true)
        let matched = try await waitForLabel("1", on: booted.deviceID, timeout: 5)
        XCTAssertTrue(matched)
    }

    private func waitForLabel(_ label: String, on deviceID: DeviceID, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let matches = try await accessibility.find(
                on: deviceID,
                selector: ElementSelector(role: nil, label: label, identifier: nil, text: nil)
            )
            if !matches.isEmpty { return true }
            try await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    private func requireAndroid() throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_ANDROID"] == "1" else {
            throw XCTSkip("BLOCKED: OPENSIM_ANDROID is not set")
        }
        let sdk: AndroidSDK
        do {
            sdk = try AndroidSDK.detect()
        } catch {
            throw XCTSkip("BLOCKED: Android SDK not found: \(error)")
        }
        guard sdk.avdmanager != nil, sdk.sdkmanager != nil else {
            throw XCTSkip("BLOCKED: avdmanager/sdkmanager missing")
        }
        let imagePath = sdk.root
            .appendingPathComponent("system-images")
            .appendingPathComponent(systemImage.replacingOccurrences(of: ";", with: "/"))
        guard FileManager.default.fileExists(atPath: imagePath.path) else {
            throw XCTSkip("BLOCKED: system image \(systemImage) not installed")
        }
    }
}
```

- [ ] **Step 3: Release gate**

- Apple release Plan 7 does not require Android. If Android is in the release, gate runs `OPENSIM_ANDROID=1` and fails when SDK/AVD missing.
- `doctor --json` includes Android fields; README/plan link updated.
- Release gate path là `Tests/Release/run-release-gate.sh` (không phải `Scripts/release/...`).

- [ ] **Step 4: Run + commit**

```bash
OPENSIM_INTEGRATION=1 OPENSIM_ANDROID=1 swift test --filter AndroidIntegrationTests
git add Package.swift Fixtures/AndroidFixture Tests/IntegrationTests/AndroidIntegrationTests.swift Scripts/android Tests/Release/run-release-gate.sh
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
- `AndroidSDK.detect(sdkPath:)` tìm đúng SDK/adb/emulator/avdmanager/sdkmanager; explicit path sai trả `android_sdk_not_found` với recovery.
- AVD list/create/boot/shutdown/erase/delete hoạt động; delete/erase bị chặn khi AVD running/in-use; erase stopped dùng `-wipe-data` có `-no-window`, chờ boot rồi kill, không leak process.
- Boot không truyền `-port`; emulator tự chọn console/adb; đọc serial/console/grpc từ discovery; hai AVD boot song song không tranh port.
- gRPC dùng `-grpc-use-token`, token đọc từ `running/pid_<PID>.ini` quyền `0600`, bind loopback; không tự sinh token, không mở gRPC trần; fail thì adb fallback và doctor ghi rõ.
- App install/launch/terminate/log hoạt động qua adb; screenshot default JPEG 80 scale 0.5 chạy; gRPC live screen/multi-touch hoạt động khi bật, fallback adb rõ ràng.
- uiautomator tree parse đúng identifier/text/bounds; selector `id=`, `label=`, `text=` tap đúng element.
- System image list/install/uninstall hoạt động; không auto-download/không nhận license thay owner; uninstall bị chặn khi có AVD dùng; install trả progress/cancel và dọn process khi lỗi.
- Operation catalog `openSim()` gồm Android ops + `ui_*`/`storage_*`/`perf_*`; `android_avd_*` dùng `name`; lease/audit dùng chung; MCP `tools/list` thấy Android tools.
- Android runtime API: `listRuntimes` map package; `downloadRuntime`/`installRuntime(.dmg)` trả `capability_unavailable`; `deleteRuntime`/`verifyRuntime` map system image.
- UI: platform filter, New Simulator Android, Runtimes system image, Settings/Doctor Android; device window Android screen/input; app target build được với product `OpenSimAndroid`.
- Storage scan thấy AVD/system image; in-use guard; fingerprint chống AVD tạo lại cùng tên; inventory lỗi fail closed; metrics có Android sample hoặc `Unknown` rõ ràng.
- Integration test Android pass khi có SDK/AVD, hoặc `BLOCKED: no Android AVD` với hướng dẫn; Apple release không bị chặn nếu owner không đưa Android vào release.
- Không thay đổi hành vi Apple ngoài additive `HardwareButton` cases/platform routing; không có shell string, không auto-download, không xoá ngoài allowlist.
- AVD name/package validate canonical: `..`, leading `-`, path separator, symlink escape bị từ chối trước khi chạy command.
