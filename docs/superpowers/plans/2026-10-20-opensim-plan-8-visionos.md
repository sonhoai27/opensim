# OpenSim Plan 8 — visionOS Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm adapter visionOS sau release simulator: dò runtime và device type, chặn tải runtime khi chưa có owner chấp thuận, render/screenshot/input qua đường phù hợp, fixture riêng và test matrix có skip/fail rõ ràng.

**Architecture:** Không đổi tên hoặc kiểu của type/protocol lõi. Plan này thêm các adapter trong `OpenSimBridge/Platforms/VisionOS` tuân theo `ScreenControlling`, `InputControlling`, `AccessibilityReading` đã có, cộng một router chọn adapter theo `Device.platform`. Runtime gate là hàm thuần trả quyết định và một kế hoạch tải runtime; không tiến trình nào được chạy nếu thiếu `OPENSIM_APPROVE_VISIONOS_DOWNLOAD=1`. App dùng screenshot polling khi `SimDisplayView` không khả dụng cho visionOS.

**Tech Stack:** Swift 6, SwiftPM, XCTest, XcodeGen, visionOS 27 SDK, SwiftUI, `simctl`, `xcodebuild`, `jq`, `zsh`.

**Spec:** `docs/superpowers/specs/2026-10-19-open-simulator-design.md`

## Global Constraints

- Chỉ bắt đầu sau khi Plan 7 đạt exit criteria: `docs/superpowers/plans/2026-10-20-opensim-plan-7-release.md`.
- Không đổi tên, kiểu, hay field của type/protocol trong `docs/superpowers/plans/2026-10-20-plan-map-and-interfaces.md`; chỉ thêm adapter và type mới trong module Bridge hoặc BridgeUI.
- Không tự tải runtime. Lệnh duy nhất được phép là `xcodebuild -downloadPlatform visionOS`; chỉ chạy khi owner đặt `OPENSIM_APPROVE_VISIONOS_DOWNLOAD=1` và đã đọc `docs/visionos.md`.
- Không hardcode device type identifier chưa xác minh; resolve từ `xcrun simctl list devicetypes -j` theo tên `Apple Vision Pro`.
- Mọi thao tác path/process tuân theo Global Constraints của Plan 7: argument array, không shell string, không telemetry.
- Integration test chỉ chạy khi `OPENSIM_INTEGRATION=1` và `OPENSIM_VISIONOS=1`; thiếu runtime thì skip, trừ khi `OPENSIM_VISIONOS_REQUIRED=1` thì fail.
- Tính năng không hỗ trợ phải trả `input_failed` hoặc `a11y_unavailable` kèm recovery, không crash và không giả lập thành công.
- Không thêm command CLI mới ngoài catalog; dùng `device`, `runtime`, `app`, `ui`, `doctor` hiện có.
- Mỗi task kết thúc bằng commit; plan author không chạy commit, không tải runtime, không chạy lệnh destructive.
- Văn xuôi tiếng Việt; code, identifier, command tiếng Anh; không ký tự CJK; không dùng Chrome.

---

## File Structure

| File | Trách nhiệm | Task |
|---|---|---|
| `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSRuntimeGate.swift` | Inventory, readiness, download plan có approval | 1 |
| `Tests/OpenSimBridgeTests/VisionOSRuntimeGateTests.swift` | Test matrix runtime/Xcode và approval | 1 |
| `Scripts/visionos/print-runtime-command.sh` | In đúng lệnh tải, exit 7 nếu chưa approval | 1 |
| `Tests/Release/test-visionos-runtime-gate.sh` | Test script approval | 1 |
| `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSDeviceTypeResolver.swift` | Chọn device type từ danh sách simctl | 2 |
| `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSDeviceProvisioner.swift` | Tạo device qua `DeviceControlling` | 2 |
| `Tests/OpenSimBridgeTests/VisionOSDeviceProvisionerTests.swift` | Test resolve và create | 2 |
| `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSScreenAdapter.swift` | Delegate `ScreenControlling` | 3 |
| `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSRenderPolicy.swift` | Chọn displayView hoặc screenshot polling | 3 |
| `Tests/OpenSimBridgeTests/VisionOSScreenAdapterTests.swift` | Test delegate và policy | 3 |
| `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSInputAdapter.swift` | Delegate input hỗ trợ, chặn gesture không hỗ trợ | 4 |
| `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSInputMapping.swift` | Clamp tọa độ theo screen | 4 |
| `Tests/OpenSimBridgeTests/VisionOSInputAdapterTests.swift` | Test tap/swipe/type và lỗi | 4 |
| `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSSupportReport.swift` | Báo cáo capability visionOS | 5 |
| `Tests/OpenSimBridgeTests/VisionOSSupportReportTests.swift` | Test report theo runtime/Xcode | 5 |
| `Tests/SecurityTests/DoctorVisionOSTests.swift` | Doctor có block `platforms.visionOS` | 5 |
| `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSPlatformRouter.swift` | Router screen/input/a11y theo platform | 6 |
| `Tests/OpenSimBridgeTests/VisionOSPlatformRouterTests.swift` | Test iOS không đổi, visionOS đi adapter | 6 |
| `Fixtures/OpenSimFixtureVision/project.yml` | XcodeGen cho fixture visionOS | 7 |
| `Fixtures/OpenSimFixtureVision/Sources/OpenSimFixtureVisionApp.swift` | App fixture có identifier ổn định | 7 |
| `Fixtures/OpenSimFixtureVision/build.sh` | Build fixture cho visionOS Simulator | 7 |
| `Sources/OpenSimBridgeUI/VisionOSScreenModel.swift` | Model polling không chồng request | 8 |
| `Sources/OpenSimBridgeUI/VisionOSScreenView.swift` | SwiftUI view cho screenshot polling | 8 |
| `Tests/OpenSimBridgeUITests/VisionOSScreenModelTests.swift` | Test refresh, lỗi, không chồng | 8 |
| `Tests/IntegrationTests/VisionOSIntegrationTests.swift` | Boot/render/screenshot/tap, skip/fail | 9 |
| `Tests/Release/test-visionos.sh` | Chạy matrix có/không runtime | 9 |
| `App/Sources/OpenSimApp/Windows/DeviceWindow.swift` | Chọn view visionOS polling | 10 |
| `docs/visionos.md` | Runbook, approval, giới hạn | 10 |
| `docs/compatibility.md` | Thêm dòng visionOS post-release | 10 |
| `README.md` | Ghi visionOS là post-release | 10 |

---

### Task 1: Runtime inventory và approval gate

**Files:**
- Create: `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSRuntimeGate.swift`
- Create: `Tests/OpenSimBridgeTests/VisionOSRuntimeGateTests.swift`
- Create: `Scripts/visionos/print-runtime-command.sh`
- Create: `Tests/Release/test-visionos-runtime-gate.sh`

**Interfaces:**
- Consumes: `Runtime`, `CompatibilityMatrix`, `CompatibilityMode` từ Core; `OpenSimError` nếu cần.
- Produces: `VisionOSRuntimeInventory.preferred(from:)`; `VisionOSRuntimeGate.readiness(runtimes:xcodeVersion:matrix:) -> VisionOSReadiness`; `VisionOSRuntimeGate.downloadPlan(ownerApproved:) throws -> VisionOSDownloadPlan`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeTests/VisionOSRuntimeGateTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class VisionOSRuntimeGateTests: XCTestCase {
    private func runtime(
        identifier: String = "com.apple.CoreSimulator.SimRuntime.visionOS-27-0",
        version: String = "27.0",
        available: Bool = true
    ) -> Runtime {
        Runtime(
            id: RuntimeID(rawValue: identifier),
            name: "visionOS \(version)",
            platform: .visionOS,
            version: version,
            build: "24A434",
            isAvailable: available,
            path: "/Library/Developer/CoreSimulator/Volumes/visionOS_27"
        )
    }

    private func iOSRuntime() -> Runtime {
        Runtime(
            id: RuntimeID(rawValue: "com.apple.CoreSimulator.SimRuntime.iOS-27-0"),
            name: "iOS 27.0",
            platform: .iOS,
            version: "27.0",
            build: "24A434",
            isAvailable: true,
            path: nil
        )
    }

    func testInventoryFiltersVisionOS() {
        let inventory = VisionOSRuntimeInventory()
        let result = inventory.installedRuntimes(from: [iOSRuntime(), runtime()])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.platform, .visionOS)
    }

    func testInventoryIgnoresUnavailableRuntime() {
        let inventory = VisionOSRuntimeInventory()
        XCTAssertTrue(inventory.installedRuntimes(from: [runtime(available: false)]).isEmpty)
    }

    func testPreferredPicksNewestVersion() {
        let older = runtime(identifier: "com.apple.CoreSimulator.SimRuntime.visionOS-26-4", version: "26.4")
        let newer = runtime(identifier: "com.apple.CoreSimulator.SimRuntime.visionOS-27-1", version: "27.1")
        XCTAssertEqual(VisionOSRuntimeInventory().preferred(from: [older, newer])?.version, "27.1")
    }

    func testReadyWhenRuntimeAndXcodeAreSupported() {
        let gate = VisionOSRuntimeGate()
        let readiness = gate.readiness(
            runtimes: [runtime()],
            xcodeVersion: "27.1",
            matrix: .release
        )
        guard case .ready(let selected) = readiness else {
            return XCTFail("expected ready, got \(readiness)")
        }
        XCTAssertEqual(selected.platform, .visionOS)
    }

    func testRuntimeMissing() {
        let gate = VisionOSRuntimeGate()
        guard case .runtimeMissing = gate.readiness(
            runtimes: [iOSRuntime()],
            xcodeVersion: "27.1",
            matrix: .release
        ) else {
            return XCTFail("expected runtimeMissing")
        }
    }

    func testXcodeBestEffortIsRejectedForVisionOS() {
        let gate = VisionOSRuntimeGate()
        guard case .xcodeUnsupported(let version) = gate.readiness(
            runtimes: [runtime()],
            xcodeVersion: "27.0",
            matrix: .release
        ) else {
            return XCTFail("expected xcodeUnsupported")
        }
        XCTAssertEqual(version, "27.0")
    }

    func testDownloadPlanRequiresOwnerApproval() {
        let gate = VisionOSRuntimeGate()
        XCTAssertThrowsError(try gate.downloadPlan(ownerApproved: false)) { error in
            XCTAssertEqual(error as? VisionOSGateError, .ownerApprovalRequired)
        }
    }

    func testDownloadPlanUsesExactCommand() throws {
        let plan = try VisionOSRuntimeGate().downloadPlan(ownerApproved: true)
        XCTAssertEqual(plan.executable, "/usr/bin/xcodebuild")
        XCTAssertEqual(plan.arguments, ["-downloadPlatform", "visionOS"])
        XCTAssertTrue(plan.requiresOwnerApproval)
    }
}
```

Create `Tests/Release/test-visionos-runtime-gate.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
set +e
OUT="$("$ROOT/Scripts/visionos/print-runtime-command.sh" 2>&1)"
STATUS=$?
set -e
if [[ "$STATUS" -ne 7 ]]; then
  print -u2 "expected exit 7 without approval, got $STATUS"
  exit 1
fi
if ! print -r -- "$OUT" | grep -q "Owner approval required"; then
  print -u2 "missing approval message"
  exit 1
fi

OUT="$(OPENSIM_APPROVE_VISIONOS_DOWNLOAD=1 "$ROOT/Scripts/visionos/print-runtime-command.sh")"
if [[ "$OUT" != "xcodebuild -downloadPlatform visionOS" ]]; then
  print -u2 "unexpected command: $OUT"
  exit 1
fi
print "OK visionos runtime gate"
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter VisionOSRuntimeGateTests
chmod +x Tests/Release/test-visionos-runtime-gate.sh
Tests/Release/test-visionos-runtime-gate.sh
```

Expected: FAIL vì `VisionOSRuntimeGate` và script chưa tồn tại.

- [ ] **Step 3: Implement gate và script**

Create `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSRuntimeGate.swift`:

```swift
import Foundation
import OpenSimCore

public struct VisionOSRuntimeInventory: Sendable {
    public init() {}

    public func installedRuntimes(from runtimes: [Runtime]) -> [Runtime] {
        runtimes.filter { $0.platform == .visionOS && $0.isAvailable }
    }

    public func preferred(from runtimes: [Runtime]) -> Runtime? {
        installedRuntimes(from: runtimes).sorted {
            $0.version.compare($1.version, options: .numeric) == .orderedDescending
        }.first
    }
}

public enum VisionOSReadiness: Sendable {
    case ready(Runtime)
    case runtimeMissing
    case xcodeUnsupported(String)
}

public struct VisionOSDownloadPlan: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var requiresOwnerApproval: Bool
}

public enum VisionOSGateError: Error, Equatable {
    case ownerApprovalRequired
}

public struct VisionOSRuntimeGate: Sendable {
    public static let downloadCommand = ["xcodebuild", "-downloadPlatform", "visionOS"]

    public init() {}

    public func readiness(
        runtimes: [Runtime],
        xcodeVersion: String,
        matrix: CompatibilityMatrix
    ) -> VisionOSReadiness {
        guard matrix.mode(forXcodeVersion: xcodeVersion) == .supported else {
            return .xcodeUnsupported(xcodeVersion)
        }
        guard let runtime = VisionOSRuntimeInventory().preferred(from: runtimes) else {
            return .runtimeMissing
        }
        return .ready(runtime)
    }

    public func downloadPlan(ownerApproved: Bool) throws -> VisionOSDownloadPlan {
        guard ownerApproved else {
            throw VisionOSGateError.ownerApprovalRequired
        }
        return VisionOSDownloadPlan(
            executable: "/usr/bin/xcodebuild",
            arguments: ["-downloadPlatform", "visionOS"],
            requiresOwnerApproval: true
        )
    }
}
```

Create `Scripts/visionos/print-runtime-command.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
if [[ "${OPENSIM_APPROVE_VISIONOS_DOWNLOAD:-0}" != "1" ]]; then
  print -u2 "Owner approval required. Read docs/visionos.md, then set OPENSIM_APPROVE_VISIONOS_DOWNLOAD=1."
  exit 7
fi
print "xcodebuild -downloadPlatform visionOS"
```

Script này chỉ in lệnh; không chạy `xcodebuild`.

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
chmod +x Scripts/visionos/print-runtime-command.sh
swift test --filter VisionOSRuntimeGateTests
Tests/Release/test-visionos-runtime-gate.sh
```

Expected: `Executed 8 tests, with 0 failures`; `OK visionos runtime gate`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Platforms/VisionOS/VisionOSRuntimeGate.swift Tests/OpenSimBridgeTests/VisionOSRuntimeGateTests.swift Scripts/visionos Tests/Release/test-visionos-runtime-gate.sh
git commit -m "feat(visionos): gate runtime install behind owner approval"
```

---

### Task 2: Device type và provisioning

**Files:**
- Create: `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSDeviceTypeResolver.swift`
- Create: `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSDeviceProvisioner.swift`
- Create: `Tests/OpenSimBridgeTests/VisionOSDeviceProvisionerTests.swift`

**Interfaces:**
- Consumes: `DeviceControlling.createDevice(name:deviceType:runtime:)`; `Runtime`.
- Produces: `VisionOSDeviceType`; `VisionOSDeviceTypeResolver.resolve(from:) throws -> VisionOSDeviceType`; `VisionOSDeviceProvisioner.create(devices:deviceTypes:runtime:name:) async throws -> Device`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeTests/VisionOSDeviceProvisionerTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class VisionOSDeviceProvisionerTests: XCTestCase {
    private let visionRuntime = Runtime(
        id: RuntimeID(rawValue: "com.apple.CoreSimulator.SimRuntime.visionOS-27-0"),
        name: "visionOS 27.0",
        platform: .visionOS,
        version: "27.0",
        build: "24A434",
        isAvailable: true,
        path: nil
    )

    func testResolverPrefersExactName() throws {
        let types = [
            VisionOSDeviceType(
                identifier: "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro-2",
                name: "Apple Vision Pro (2nd generation)"
            ),
            VisionOSDeviceType(
                identifier: "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro",
                name: "Apple Vision Pro"
            )
        ]
        let resolved = try VisionOSDeviceTypeResolver().resolve(from: types)
        XCTAssertEqual(resolved.identifier, "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro")
    }

    func testResolverAcceptsGenerationNameWhenExactMissing() throws {
        let types = [
            VisionOSDeviceType(
                identifier: "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro-2",
                name: "Apple Vision Pro (2nd generation)"
            )
        ]
        XCTAssertEqual(
            try VisionOSDeviceTypeResolver().resolve(from: types).identifier,
            "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro-2"
        )
    }

    func testResolverFailsWithoutVisionProType() {
        let types = [VisionOSDeviceType(identifier: "iphone", name: "iPhone 17")]
        XCTAssertThrowsError(try VisionOSDeviceTypeResolver().resolve(from: types)) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, "device_not_found")
        }
    }

    func testProvisionerCreatesWithResolvedTypeAndRuntime() async throws {
        let devices = StubDevices()
        let types = [
            VisionOSDeviceType(
                identifier: "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro",
                name: "Apple Vision Pro"
            )
        ]
        let device = try await VisionOSDeviceProvisioner().create(
            devices: devices,
            deviceTypes: types,
            runtime: visionRuntime,
            name: "OpenSim Vision"
        )
        let recorded = await devices.recordedCreate()
        XCTAssertEqual(recorded?.name, "OpenSim Vision")
        XCTAssertEqual(recorded?.deviceType, "com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro")
        XCTAssertEqual(recorded?.runtime, visionRuntime.id)
        XCTAssertEqual(device.platform, .visionOS)
    }
}

private actor StubDevices: DeviceControlling {
    struct CreateCall: Sendable {
        var name: String
        var deviceType: String
        var runtime: RuntimeID?
    }

    private var createCall: CreateCall?

    func recordedCreate() -> CreateCall? {
        createCall
    }

    func listDevices() async throws -> [Device] { [] }

    func device(_ id: DeviceID) async throws -> Device {
        throw OpenSimError(
            code: "device_not_found",
            message: "missing",
            details: [:],
            recovery: nil,
            retryable: false
        )
    }

    func createDevice(name: String, deviceType: String, runtime: RuntimeID?) async throws -> Device {
        createCall = CreateCall(name: name, deviceType: deviceType, runtime: runtime)
        return Device(
            id: DeviceID(rawValue: "11111111-1111-1111-1111-111111111111"),
            name: name,
            platform: .visionOS,
            deviceType: deviceType,
            runtime: runtime ?? RuntimeID(rawValue: "unknown"),
            state: .shutdown,
            isAvailable: true,
            dataPath: nil,
            lastBootedAt: nil
        )
    }

    func cloneDevice(_ id: DeviceID, name: String) async throws -> Device {
        throw OpenSimError(code: "internal", message: "unsupported", details: [:], recovery: nil, retryable: false)
    }

    func boot(_ id: DeviceID, wait: Bool) async throws -> Device {
        throw OpenSimError(code: "internal", message: "unsupported", details: [:], recovery: nil, retryable: false)
    }

    func shutdown(_ id: DeviceID, wait: Bool) async throws -> Device {
        throw OpenSimError(code: "internal", message: "unsupported", details: [:], recovery: nil, retryable: false)
    }

    func erase(_ id: DeviceID) async throws -> Device {
        throw OpenSimError(code: "internal", message: "unsupported", details: [:], recovery: nil, retryable: false)
    }

    func delete(_ id: DeviceID) async throws {
        throw OpenSimError(code: "internal", message: "unsupported", details: [:], recovery: nil, retryable: false)
    }

    func rename(_ id: DeviceID, to name: String) async throws -> Device {
        throw OpenSimError(code: "internal", message: "unsupported", details: [:], recovery: nil, retryable: false)
    }

    func pair(watch: DeviceID, phone: DeviceID) async throws {
        throw OpenSimError(code: "internal", message: "unsupported", details: [:], recovery: nil, retryable: false)
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter VisionOSDeviceProvisionerTests
```

Expected: FAIL vì resolver và provisioner chưa tồn tại.

- [ ] **Step 3: Implement**

Create `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSDeviceTypeResolver.swift`:

```swift
import Foundation
import OpenSimCore

public struct VisionOSDeviceType: Codable, Sendable, Equatable {
    public var identifier: String
    public var name: String

    public init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }
}

public struct VisionOSDeviceTypeResolver: Sendable {
    public init() {}

    public func resolve(from deviceTypes: [VisionOSDeviceType]) throws -> VisionOSDeviceType {
        if let exact = deviceTypes.first(where: { $0.name == "Apple Vision Pro" }) {
            return exact
        }
        if let prefix = deviceTypes.first(where: { $0.name.hasPrefix("Apple Vision Pro") }) {
            return prefix
        }
        throw OpenSimError(
            code: "device_not_found",
            message: "No Apple Vision Pro device type is installed",
            details: ["platform": "visionOS"],
            recovery: "Install the visionOS 27.0 runtime in Xcode Settings, then retry",
            retryable: false
        )
    }
}
```

Create `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSDeviceProvisioner.swift`:

```swift
import Foundation
import OpenSimCore

public struct VisionOSDeviceProvisioner: Sendable {
    public init() {}

    public func create(
        devices: any DeviceControlling,
        deviceTypes: [VisionOSDeviceType],
        runtime: Runtime,
        name: String
    ) async throws -> Device {
        let deviceType = try VisionOSDeviceTypeResolver().resolve(from: deviceTypes)
        return try await devices.createDevice(
            name: name,
            deviceType: deviceType.identifier,
            runtime: runtime.id
        )
    }
}
```

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
swift test --filter VisionOSDeviceProvisionerTests
```

Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Platforms/VisionOS Tests/OpenSimBridgeTests/VisionOSDeviceProvisionerTests.swift
git commit -m "feat(visionos): resolve device types and create devices"
```

---

### Task 3: Screen adapter và render policy

**Files:**
- Create: `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSScreenAdapter.swift`
- Create: `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSRenderPolicy.swift`
- Create: `Tests/OpenSimBridgeTests/VisionOSScreenAdapterTests.swift`

**Interfaces:**
- Consumes: `ScreenControlling` từ contract mục 5.
- Produces: `VisionOSScreenAdapter(base:)` conform `ScreenControlling`; `VisionOSRenderMode`; `VisionOSRenderPolicy.mode(displayViewAvailable:)`; `VisionOSRenderPolicy.pollingIntervalMilliseconds`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeTests/VisionOSScreenAdapterTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class VisionOSScreenAdapterTests: XCTestCase {
    func testScreensDelegatesToBase() async throws {
        let base = RecordingScreen()
        let adapter = VisionOSScreenAdapter(base: base)
        let screens = try await adapter.screens(for: DeviceID(rawValue: "vision-device"))
        XCTAssertEqual(screens.count, 1)
        let screenCalls = await base.screenCalls
        XCTAssertEqual(screenCalls, 1)
    }

    func testScreenshotDelegatesFormatAndScale() async throws {
        let base = RecordingScreen()
        let adapter = VisionOSScreenAdapter(base: base)
        let screenshot = try await adapter.screenshot(
            on: DeviceID(rawValue: "vision-device"),
            format: .jpeg,
            scale: 0.5,
            quality: 80
        )
        XCTAssertEqual(screenshot.format, .jpeg)
        XCTAssertEqual(screenshot.scale, 0.5)
        let call = await base.lastScreenshotCall
        XCTAssertEqual(call?.format, .jpeg)
        XCTAssertEqual(call?.scale, 0.5)
        XCTAssertEqual(call?.quality, 80)
    }

    func testRecordingDelegates() async throws {
        let base = RecordingScreen()
        let adapter = VisionOSScreenAdapter(base: base)
        let id = try await adapter.startRecording(
            on: DeviceID(rawValue: "vision-device"),
            to: "/tmp/vision.mov",
            codec: .hevc
        )
        XCTAssertEqual(id.rawValue, "recording-1")
        let stopped = try await adapter.stopRecording(id)
        XCTAssertEqual(stopped, "/tmp/vision.mov")
    }

    func testRenderPolicyPrefersDisplayViewWhenAvailable() {
        XCTAssertEqual(VisionOSRenderPolicy.mode(displayViewAvailable: true), .displayView)
        XCTAssertEqual(VisionOSRenderPolicy.mode(displayViewAvailable: false), .screenshotPolling)
        XCTAssertEqual(VisionOSRenderPolicy.pollingIntervalMilliseconds, 100)
    }
}

private actor RecordingScreen: ScreenControlling {
    struct ScreenshotCall: Sendable {
        var format: ScreenshotFormat
        var scale: Double
        var quality: Int?
    }

    private(set) var screenCalls = 0
    private(set) var lastScreenshotCall: ScreenshotCall?

    func screens(for device: DeviceID) async throws -> [ScreenInfo] {
        screenCalls += 1
        return [ScreenInfo(id: 1, width: 1920, height: 1080, scale: 1, rotation: 0, displayClass: 0)]
    }

    func screenshot(
        on device: DeviceID,
        format: ScreenshotFormat,
        scale: Double,
        quality: Int?
    ) async throws -> Screenshot {
        lastScreenshotCall = ScreenshotCall(format: format, scale: scale, quality: quality)
        return Screenshot(
            path: "/tmp/vision.jpg",
            data: nil,
            format: format,
            width: 960,
            height: 540,
            scale: scale,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func startRecording(on device: DeviceID, to path: String?, codec: VideoCodec) async throws -> RecordingID {
        RecordingID(rawValue: "recording-1")
    }

    func stopRecording(_ id: RecordingID) async throws -> String {
        "/tmp/vision.mov"
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter VisionOSScreenAdapterTests
```

Expected: FAIL vì adapter và policy chưa tồn tại.

- [ ] **Step 3: Implement**

Create `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSRenderPolicy.swift`:

```swift
import Foundation

public enum VisionOSRenderMode: String, Codable, Sendable, Equatable {
    case displayView
    case screenshotPolling
}

public struct VisionOSRenderPolicy: Sendable {
    public static let pollingIntervalMilliseconds = 100

    public init() {}

    public static func mode(displayViewAvailable: Bool) -> VisionOSRenderMode {
        displayViewAvailable ? .displayView : .screenshotPolling
    }
}
```

Create `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSScreenAdapter.swift`:

```swift
import Foundation
import OpenSimCore

public struct VisionOSScreenAdapter: ScreenControlling {
    private let base: any ScreenControlling

    public init(base: any ScreenControlling) {
        self.base = base
    }

    public func screens(for device: DeviceID) async throws -> [ScreenInfo] {
        try await base.screens(for: device)
    }

    public func screenshot(
        on device: DeviceID,
        format: ScreenshotFormat,
        scale: Double,
        quality: Int?
    ) async throws -> Screenshot {
        try await base.screenshot(on: device, format: format, scale: scale, quality: quality)
    }

    public func startRecording(
        on device: DeviceID,
        to path: String?,
        codec: VideoCodec
    ) async throws -> RecordingID {
        try await base.startRecording(on: device, to: path, codec: codec)
    }

    public func stopRecording(_ id: RecordingID) async throws -> String {
        try await base.stopRecording(id)
    }
}
```

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
swift test --filter VisionOSScreenAdapterTests
```

Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Platforms/VisionOS Tests/OpenSimBridgeTests/VisionOSScreenAdapterTests.swift
git commit -m "feat(visionos): add screen adapter and render policy"
```

---

### Task 4: Input adapter và gesture không hỗ trợ

**Files:**
- Create: `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSInputMapping.swift`
- Create: `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSInputAdapter.swift`
- Create: `Tests/OpenSimBridgeTests/VisionOSInputAdapterTests.swift`

**Interfaces:**
- Consumes: `InputControlling`, `ScreenControlling`, `Point`, `ScreenInfo`.
- Produces: `VisionOSInputMapping.clamp(_:to:) -> Point`; `VisionOSInputAdapter(input:screens:)` conform `InputControlling`; lỗi `input_failed` cho `pinch`, `rotate`, `scroll`, `button`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeTests/VisionOSInputAdapterTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class VisionOSInputAdapterTests: XCTestCase {
    func testTapClampsPointIntoScreen() async throws {
        let input = RecordingInput()
        let adapter = VisionOSInputAdapter(input: input, screens: RecordingScreens())
        try await adapter.tap(
            on: DeviceID(rawValue: "vision-device"),
            at: Point(x: -20, y: 2000),
            settle: true
        )
        let point = await input.lastTapPoint
        XCTAssertEqual(point?.x, 0)
        XCTAssertEqual(point?.y, 1080)
    }

    func testSwipeClampsBothPoints() async throws {
        let input = RecordingInput()
        let adapter = VisionOSInputAdapter(input: input, screens: RecordingScreens())
        try await adapter.swipe(
            on: DeviceID(rawValue: "vision-device"),
            from: Point(x: -1, y: -1),
            to: Point(x: 5000, y: 5000),
            durationMs: 300
        )
        let swipe = await input.lastSwipe
        XCTAssertEqual(swipe?.from.x, 0)
        XCTAssertEqual(swipe?.to.x, 1920)
        XCTAssertEqual(swipe?.to.y, 1080)
        XCTAssertEqual(swipe?.durationMs, 300)
    }

    func testTypeAndKeyDelegate() async throws {
        let input = RecordingInput()
        let adapter = VisionOSInputAdapter(input: input, screens: RecordingScreens())
        try await adapter.typeText(on: DeviceID(rawValue: "vision-device"), text: "hello")
        try await adapter.key(
            on: DeviceID(rawValue: "vision-device"),
            key: Key(name: "return", keyCode: 36),
            modifiers: KeyModifiers(command: false, shift: false, option: false, control: false)
        )
        let text = await input.lastText
        let key = await input.lastKey
        XCTAssertEqual(text, "hello")
        XCTAssertEqual(key?.name, "return")
    }

    func testPinchIsRejected() async {
        let adapter = VisionOSInputAdapter(input: RecordingInput(), screens: RecordingScreens())
        do {
            try await adapter.pinch(
                on: DeviceID(rawValue: "vision-device"),
                center: Point(x: 100, y: 100),
                scale: 2,
                durationMs: 200
            )
            XCTFail("pinch must fail")
        } catch {
            XCTAssertEqual((error as? OpenSimError)?.code, "input_failed")
        }
    }

    func testRotateScrollAndButtonAreRejected() async {
        let adapter = VisionOSInputAdapter(input: RecordingInput(), screens: RecordingScreens())
        await assertInputFailed {
            try await adapter.rotate(
                on: DeviceID(rawValue: "vision-device"),
                center: Point(x: 100, y: 100),
                angle: 90,
                durationMs: 200
            )
        }
        await assertInputFailed {
            try await adapter.scroll(
                on: DeviceID(rawValue: "vision-device"),
                deltaX: 0,
                deltaY: 100,
                at: nil
            )
        }
        await assertInputFailed {
            try await adapter.button(on: DeviceID(rawValue: "vision-device"), button: .home)
        }
    }

    private func assertInputFailed(_ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("operation must fail")
        } catch {
            XCTAssertEqual((error as? OpenSimError)?.code, "input_failed")
        }
    }
}

private actor RecordingScreens: ScreenControlling {
    func screens(for device: DeviceID) async throws -> [ScreenInfo] {
        [ScreenInfo(id: 1, width: 1920, height: 1080, scale: 1, rotation: 0, displayClass: 0)]
    }

    func screenshot(
        on device: DeviceID,
        format: ScreenshotFormat,
        scale: Double,
        quality: Int?
    ) async throws -> Screenshot {
        Screenshot(
            path: nil,
            data: nil,
            format: format,
            width: 1920,
            height: 1080,
            scale: scale,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func startRecording(on device: DeviceID, to path: String?, codec: VideoCodec) async throws -> RecordingID {
        RecordingID(rawValue: "recording")
    }

    func stopRecording(_ id: RecordingID) async throws -> String {
        "/tmp/vision.mov"
    }
}

private actor RecordingInput: InputControlling {
    struct Swipe: Sendable {
        var from: Point
        var to: Point
        var durationMs: Int
    }

    private(set) var lastTapPoint: Point?
    private(set) var lastSwipe: Swipe?
    private(set) var lastText: String?
    private(set) var lastKey: Key?

    func tap(on device: DeviceID, at point: Point, settle: Bool) async throws {
        lastTapPoint = point
    }

    func swipe(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {
        lastSwipe = Swipe(from: from, to: to, durationMs: durationMs)
    }

    func longPress(on device: DeviceID, at point: Point, durationMs: Int) async throws {}
    func drag(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {}
    func pinch(on device: DeviceID, center: Point, scale: Double, durationMs: Int) async throws {}
    func rotate(on device: DeviceID, center: Point, angle: Double, durationMs: Int) async throws {}
    func scroll(on device: DeviceID, deltaX: Double, deltaY: Double, at point: Point?) async throws {}

    func typeText(on device: DeviceID, text: String) async throws {
        lastText = text
    }

    func key(on device: DeviceID, key: Key, modifiers: KeyModifiers) async throws {
        lastKey = key
    }

    func button(on device: DeviceID, button: HardwareButton) async throws {}
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter VisionOSInputAdapterTests
```

Expected: FAIL vì `VisionOSInputAdapter` và `VisionOSInputMapping` chưa tồn tại.

- [ ] **Step 3: Implement**

Create `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSInputMapping.swift`:

```swift
import Foundation
import OpenSimCore

public struct VisionOSInputMapping: Sendable {
    public init() {}

    public func clamp(_ point: Point, to screen: ScreenInfo) -> Point {
        Point(
            x: min(max(point.x, 0), Double(screen.width)),
            y: min(max(point.y, 0), Double(screen.height))
        )
    }
}
```

Create `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSInputAdapter.swift`:

```swift
import Foundation
import OpenSimCore

public struct VisionOSInputAdapter: InputControlling {
    private let input: any InputControlling
    private let screens: any ScreenControlling
    private let mapping = VisionOSInputMapping()

    public init(input: any InputControlling, screens: any ScreenControlling) {
        self.input = input
        self.screens = screens
    }

    public func tap(on device: DeviceID, at point: Point, settle: Bool) async throws {
        try await input.tap(on: device, at: try await map(point, on: device), settle: settle)
    }

    public func swipe(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {
        try await input.swipe(
            on: device,
            from: try await map(from, on: device),
            to: try await map(to, on: device),
            durationMs: durationMs
        )
    }

    public func longPress(on device: DeviceID, at point: Point, durationMs: Int) async throws {
        try await input.longPress(on: device, at: try await map(point, on: device), durationMs: durationMs)
    }

    public func drag(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {
        try await input.drag(
            on: device,
            from: try await map(from, on: device),
            to: try await map(to, on: device),
            durationMs: durationMs
        )
    }

    public func pinch(on device: DeviceID, center: Point, scale: Double, durationMs: Int) async throws {
        throw unsupported("pinch")
    }

    public func rotate(on device: DeviceID, center: Point, angle: Double, durationMs: Int) async throws {
        throw unsupported("rotate")
    }

    public func scroll(on device: DeviceID, deltaX: Double, deltaY: Double, at point: Point?) async throws {
        throw unsupported("scroll")
    }

    public func typeText(on device: DeviceID, text: String) async throws {
        try await input.typeText(on: device, text: text)
    }

    public func key(on device: DeviceID, key: Key, modifiers: KeyModifiers) async throws {
        try await input.key(on: device, key: key, modifiers: modifiers)
    }

    public func button(on device: DeviceID, button: HardwareButton) async throws {
        throw unsupported("button")
    }

    private func map(_ point: Point, on device: DeviceID) async throws -> Point {
        guard let screen = try await screens.screens(for: device).first else {
            return point
        }
        return mapping.clamp(point, to: screen)
    }

    private func unsupported(_ feature: String) -> OpenSimError {
        OpenSimError(
            code: "input_failed",
            message: "\(feature) is not supported on visionOS",
            details: ["platform": "visionOS", "feature": feature],
            recovery: "Use tap, swipe, long-press, drag, type or key",
            retryable: false
        )
    }
}
```

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
swift test --filter VisionOSInputAdapterTests
```

Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Platforms/VisionOS Tests/OpenSimBridgeTests/VisionOSInputAdapterTests.swift
git commit -m "feat(visionos): map supported input and reject gestures"
```

---

### Task 5: Capability report và doctor

**Files:**
- Create: `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSSupportReport.swift`
- Create: `Tests/OpenSimBridgeTests/VisionOSSupportReportTests.swift`
- Create: `Tests/SecurityTests/DoctorVisionOSTests.swift`
- Modify: `Sources/OpenSimCLI/Commands/DoctorCommand.swift`

**Interfaces:**
- Consumes: `VisionOSRuntimeGate`, `VisionOSRenderPolicy`, `CompatibilityMatrix`; `Capability`.
- Produces: `VisionOSSupportReport` (Codable); `VisionOSSupportBuilder.make(runtimes:xcodeVersion:matrix:displayViewAvailable:)`; doctor JSON `data.platforms.visionOS`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeTests/VisionOSSupportReportTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class VisionOSSupportReportTests: XCTestCase {
    private let runtime = Runtime(
        id: RuntimeID(rawValue: "com.apple.CoreSimulator.SimRuntime.visionOS-27-0"),
        name: "visionOS 27.0",
        platform: .visionOS,
        version: "27.0",
        build: "24A434",
        isAvailable: true,
        path: nil
    )

    func testReadyReportExposesRuntimeAndPolling() {
        let report = VisionOSSupportBuilder().make(
            runtimes: [runtime],
            xcodeVersion: "27.1",
            matrix: .release,
            displayViewAvailable: false
        )
        XCTAssertTrue(report.runtimeInstalled)
        XCTAssertEqual(report.runtimeIdentifier, runtime.id.rawValue)
        XCTAssertEqual(report.readiness, "ready")
        XCTAssertEqual(report.renderMode, .screenshotPolling)
        XCTAssertEqual(report.accessibility.rawValue, "unavailable")
        XCTAssertTrue(report.unsupportedInputs.contains("pinch"))
        XCTAssertTrue(report.unsupportedInputs.contains("rotate"))
        XCTAssertTrue(report.unsupportedInputs.contains("scroll"))
        XCTAssertTrue(report.unsupportedInputs.contains("button"))
        XCTAssertEqual(report.accessibility.rawValue, "unavailable")
    }

    func testRuntimeMissingReport() {
        let report = VisionOSSupportBuilder().make(
            runtimes: [],
            xcodeVersion: "27.1",
            matrix: .release,
            displayViewAvailable: false
        )
        XCTAssertFalse(report.runtimeInstalled)
        XCTAssertNil(report.runtimeIdentifier)
        XCTAssertEqual(report.readiness, "runtimeMissing")
        XCTAssertEqual(report.accessibility.rawValue, "unavailable")
    }

    func testXcodeUnsupportedReport() {
        let report = VisionOSSupportBuilder().make(
            runtimes: [runtime],
            xcodeVersion: "27.0",
            matrix: .release,
            displayViewAvailable: true
        )
        XCTAssertEqual(report.readiness, "xcodeUnsupported")
        XCTAssertEqual(report.renderMode, .displayView)
    }
}
```

Create `Tests/SecurityTests/DoctorVisionOSTests.swift`:

```swift
import XCTest

final class DoctorVisionOSTests: XCTestCase {
    func testDoctorAlwaysReportsVisionOSSection() throws {
        let binary = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/opensim")
        let result = try VisionProcessRunner.run(binary.path, ["doctor", "--json"])
        XCTAssertEqual(result.status, 0, result.stderr)
        let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as! [String: Any]
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let platforms = try XCTUnwrap(data["platforms"] as? [String: Any])
        let vision = try XCTUnwrap(platforms["visionOS"] as? [String: Any])
        let readiness = try XCTUnwrap(vision["readiness"] as? String)
        XCTAssertTrue(["ready", "runtimeMissing", "xcodeUnsupported"].contains(readiness))
        XCTAssertNotNil(vision["runtimeInstalled"])
        XCTAssertNotNil(vision["renderMode"])
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter VisionOSSupportReportTests
swift test --filter DoctorVisionOSTests
```

Expected: FAIL vì report chưa tồn tại và doctor chưa có block `platforms.visionOS`.

- [ ] **Step 3: Implement report**

Create `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSSupportReport.swift`:

```swift
import Foundation
import OpenSimCore

public struct VisionOSSupportReport: Codable, Sendable {
    public var runtimeInstalled: Bool
    public var runtimeIdentifier: String?
    public var readiness: String
    public var renderMode: VisionOSRenderMode
    public var supportedInputs: [String]
    public var unsupportedInputs: [String]
    public var accessibility: Capability
    public var xcodeVersion: String
}

public struct VisionOSSupportBuilder: Sendable {
    public init() {}

    public func make(
        runtimes: [Runtime],
        xcodeVersion: String,
        matrix: CompatibilityMatrix,
        displayViewAvailable: Bool
    ) -> VisionOSSupportReport {
        let readiness = VisionOSRuntimeGate().readiness(
            runtimes: runtimes,
            xcodeVersion: xcodeVersion,
            matrix: matrix
        )
        let runtime: Runtime?
        let readinessValue: String
        switch readiness {
        case .ready(let selected):
            runtime = selected
            readinessValue = "ready"
        case .runtimeMissing:
            runtime = nil
            readinessValue = "runtimeMissing"
        case .xcodeUnsupported:
            runtime = nil
            readinessValue = "xcodeUnsupported"
        }
        return VisionOSSupportReport(
            runtimeInstalled: runtime != nil,
            runtimeIdentifier: runtime?.id.rawValue,
            readiness: readinessValue,
            renderMode: VisionOSRenderPolicy.mode(displayViewAvailable: displayViewAvailable),
            supportedInputs: ["tap", "swipe", "longPress", "drag", "type", "key"],
            unsupportedInputs: ["pinch", "rotate", "scroll", "button"],
            accessibility: .unavailable,
            xcodeVersion: xcodeVersion
        )
    }
}
```

`VisionOSSupportReport` có memberwise initializer nội bộ; thêm public initializer cùng file:

```swift
public extension VisionOSSupportReport {
    init(
        runtimeInstalled: Bool,
        runtimeIdentifier: String?,
        readiness: String,
        renderMode: VisionOSRenderMode,
        supportedInputs: [String],
        unsupportedInputs: [String],
        accessibility: Capability,
        xcodeVersion: String
    ) {
        self.runtimeInstalled = runtimeInstalled
        self.runtimeIdentifier = runtimeIdentifier
        self.readiness = readiness
        self.renderMode = renderMode
        self.supportedInputs = supportedInputs
        self.unsupportedInputs = unsupportedInputs
        self.accessibility = accessibility
        self.xcodeVersion = xcodeVersion
    }
}
```

Trong `Sources/OpenSimCLI/Commands/DoctorCommand.swift`, lấy danh sách runtime và thêm:

```swift
let visionReport = VisionOSSupportBuilder().make(
    runtimes: runtimes,
    xcodeVersion: xcodeVersion,
    matrix: .release,
    displayViewAvailable: capabilities.render == .available
)
```

Ghi vào JSON:

```swift
"platforms": [
    "visionOS": [
        "runtimeInstalled": visionReport.runtimeInstalled,
        "runtimeIdentifier": visionReport.runtimeIdentifier ?? "",
        "readiness": visionReport.readiness,
        "renderMode": visionReport.renderMode.rawValue,
        "supportedInputs": visionReport.supportedInputs,
        "unsupportedInputs": visionReport.unsupportedInputs,
        "accessibility": visionReport.accessibility.rawValue
    ]
]
```

Nếu `runtimes` chưa có trong scope của `DoctorCommand`, gọi `bridge.runtimes.listRuntimes()` trước khi dựng report.

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
swift test --filter VisionOSSupportReportTests
swift build --product opensim
swift test --filter DoctorVisionOSTests
```

Expected: `Executed 3 tests, with 0 failures`; `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Platforms/VisionOS Sources/OpenSimCLI/Commands/DoctorCommand.swift Tests/OpenSimBridgeTests/VisionOSSupportReportTests.swift Tests/SecurityTests/DoctorVisionOSTests.swift
git commit -m "feat(visionos): report readiness in doctor"
```

---

### Task 6: Router theo platform và ghép vào Bridge

**Files:**
- Create: `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSPlatformRouter.swift`
- Create: `Tests/OpenSimBridgeTests/VisionOSPlatformRouterTests.swift`
- Modify: `Sources/OpenSimBridge/Services/SimulatorBridgeImpl.swift` (bọc screen/input/accessibility)

**Interfaces:**
- Consumes: `DeviceControlling.device(_:)`, `ScreenControlling`, `InputControlling`, `AccessibilityReading`.
- Produces: `VisionOSRoutingScreen(devices:standard:vision:)`, `VisionOSRoutingInput(devices:standard:vision:)`, `VisionOSRoutingAccessibility(devices:standard:)`; iOS đi đường cũ, visionOS đi adapter hoặc trả `a11y_unavailable`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeTests/VisionOSPlatformRouterTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class VisionOSPlatformRouterTests: XCTestCase {
    func testIOSScreenUsesStandardPath() async throws {
        let devices = PlatformDevices(platform: .iOS)
        let standard = WidthScreen(width: 111)
        let vision = WidthScreen(width: 222)
        let router = VisionOSRoutingScreen(devices: devices, standard: standard, vision: vision)
        let screens = try await router.screens(for: DeviceID(rawValue: "device-1"))
        XCTAssertEqual(screens.first?.width, 111)
    }

    func testVisionOSScreenUsesVisionPath() async throws {
        let devices = PlatformDevices(platform: .visionOS)
        let standard = WidthScreen(width: 111)
        let vision = WidthScreen(width: 222)
        let router = VisionOSRoutingScreen(devices: devices, standard: standard, vision: vision)
        let screens = try await router.screens(for: DeviceID(rawValue: "device-1"))
        XCTAssertEqual(screens.first?.width, 222)
    }

    func testIOSInputUsesStandardPath() async throws {
        let devices = PlatformDevices(platform: .iOS)
        let standard = TagInput(tag: "standard")
        let vision = TagInput(tag: "vision")
        let router = VisionOSRoutingInput(devices: devices, standard: standard, vision: vision)
        try await router.tap(on: DeviceID(rawValue: "device-1"), at: Point(x: 1, y: 2), settle: false)
        let tag = await standard.lastTag
        XCTAssertEqual(tag, "standard")
    }

    func testVisionOSInputUsesVisionPath() async throws {
        let devices = PlatformDevices(platform: .visionOS)
        let standard = TagInput(tag: "standard")
        let vision = TagInput(tag: "vision")
        let router = VisionOSRoutingInput(devices: devices, standard: standard, vision: vision)
        try await router.tap(on: DeviceID(rawValue: "device-1"), at: Point(x: 1, y: 2), settle: false)
        let tag = await vision.lastTag
        XCTAssertEqual(tag, "vision")
    }

    func testVisionOSAccessibilityIsUnavailable() async {
        let router = VisionOSRoutingAccessibility(
            devices: PlatformDevices(platform: .visionOS),
            standard: EmptyAccessibility()
        )
        do {
            _ = try await router.tree(on: DeviceID(rawValue: "device-1"), maxDepth: 30, maxNodes: 1500)
            XCTFail("visionOS accessibility must throw")
        } catch {
            XCTAssertEqual((error as? OpenSimError)?.code, "a11y_unavailable")
        }
    }

    func testIOSAccessibilityUsesStandardPath() async throws {
        let router = VisionOSRoutingAccessibility(
            devices: PlatformDevices(platform: .iOS),
            standard: EmptyAccessibility()
        )
        let tree = try await router.tree(on: DeviceID(rawValue: "device-1"), maxDepth: 30, maxNodes: 1500)
        XCTAssertEqual(tree.root.id, "root")
    }
}

private struct PlatformDevices: DeviceControlling {
    var platform: Platform

    func listDevices() async throws -> [Device] { [] }

    func device(_ id: DeviceID) async throws -> Device {
        Device(
            id: id,
            name: "Device",
            platform: platform,
            deviceType: "type",
            runtime: RuntimeID(rawValue: "runtime"),
            state: .booted,
            isAvailable: true,
            dataPath: nil,
            lastBootedAt: nil
        )
    }

    func createDevice(name: String, deviceType: String, runtime: RuntimeID?) async throws -> Device {
        try await device(DeviceID(rawValue: "device-1"))
    }

    func cloneDevice(_ id: DeviceID, name: String) async throws -> Device {
        try await device(id)
    }

    func boot(_ id: DeviceID, wait: Bool) async throws -> Device {
        try await device(id)
    }

    func shutdown(_ id: DeviceID, wait: Bool) async throws -> Device {
        try await device(id)
    }

    func erase(_ id: DeviceID) async throws -> Device {
        try await device(id)
    }

    func delete(_ id: DeviceID) async throws {}

    func rename(_ id: DeviceID, to name: String) async throws -> Device {
        try await device(id)
    }

    func pair(watch: DeviceID, phone: DeviceID) async throws {}
}

private struct WidthScreen: ScreenControlling {
    var width: Int

    func screens(for device: DeviceID) async throws -> [ScreenInfo] {
        [ScreenInfo(id: 1, width: width, height: 1080, scale: 1, rotation: 0, displayClass: 0)]
    }

    func screenshot(
        on device: DeviceID,
        format: ScreenshotFormat,
        scale: Double,
        quality: Int?
    ) async throws -> Screenshot {
        Screenshot(
            path: nil,
            data: nil,
            format: format,
            width: width,
            height: 1080,
            scale: scale,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func startRecording(on device: DeviceID, to path: String?, codec: VideoCodec) async throws -> RecordingID {
        RecordingID(rawValue: "recording")
    }

    func stopRecording(_ id: RecordingID) async throws -> String {
        "/tmp/vision.mov"
    }
}

private actor TagInput: InputControlling {
    let tag: String
    private(set) var lastTag: String?

    init(tag: String) {
        self.tag = tag
    }

    func tap(on device: DeviceID, at point: Point, settle: Bool) async throws {
        lastTag = tag
    }

    func swipe(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {
        lastTag = tag
    }

    func longPress(on device: DeviceID, at point: Point, durationMs: Int) async throws {
        lastTag = tag
    }

    func drag(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {
        lastTag = tag
    }

    func pinch(on device: DeviceID, center: Point, scale: Double, durationMs: Int) async throws {
        lastTag = tag
    }

    func rotate(on device: DeviceID, center: Point, angle: Double, durationMs: Int) async throws {
        lastTag = tag
    }

    func scroll(on device: DeviceID, deltaX: Double, deltaY: Double, at point: Point?) async throws {
        lastTag = tag
    }

    func typeText(on device: DeviceID, text: String) async throws {
        lastTag = tag
    }

    func key(on device: DeviceID, key: Key, modifiers: KeyModifiers) async throws {
        lastTag = tag
    }

    func button(on device: DeviceID, button: HardwareButton) async throws {
        lastTag = tag
    }
}

private struct EmptyAccessibility: AccessibilityReading {
    func tree(on device: DeviceID, maxDepth: Int, maxNodes: Int) async throws -> UITree {
        UITree(
            root: UIElement(
                id: "root",
                role: "window",
                label: nil,
                identifier: "root",
                value: nil,
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                enabled: true,
                selected: false,
                children: []
            ),
            nodeCount: 1,
            truncated: false
        )
    }

    func find(on device: DeviceID, selector: ElementSelector) async throws -> [UIElement] {
        []
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter VisionOSPlatformRouterTests
```

Expected: FAIL vì router chưa tồn tại.

- [ ] **Step 3: Implement router**

Create `Sources/OpenSimBridge/Platforms/VisionOS/VisionOSPlatformRouter.swift`:

```swift
import Foundation
import OpenSimCore

public struct VisionOSRoutingScreen: ScreenControlling {
    private let devices: any DeviceControlling
    private let standard: any ScreenControlling
    private let vision: any ScreenControlling

    public init(
        devices: any DeviceControlling,
        standard: any ScreenControlling,
        vision: any ScreenControlling
    ) {
        self.devices = devices
        self.standard = standard
        self.vision = vision
    }

    public func screens(for device: DeviceID) async throws -> [ScreenInfo] {
        try await target(device).screens(for: device)
    }

    public func screenshot(
        on device: DeviceID,
        format: ScreenshotFormat,
        scale: Double,
        quality: Int?
    ) async throws -> Screenshot {
        try await target(device).screenshot(on: device, format: format, scale: scale, quality: quality)
    }

    public func startRecording(
        on device: DeviceID,
        to path: String?,
        codec: VideoCodec
    ) async throws -> RecordingID {
        try await target(device).startRecording(on: device, to: path, codec: codec)
    }

    public func stopRecording(_ id: RecordingID) async throws -> String {
        try await standard.stopRecording(id)
    }

    private func target(_ device: DeviceID) async throws -> any ScreenControlling {
        let model = try await devices.device(device)
        return model.platform == .visionOS ? vision : standard
    }
}

public struct VisionOSRoutingInput: InputControlling {
    private let devices: any DeviceControlling
    private let standard: any InputControlling
    private let vision: any InputControlling

    public init(
        devices: any DeviceControlling,
        standard: any InputControlling,
        vision: any InputControlling
    ) {
        self.devices = devices
        self.standard = standard
        self.vision = vision
    }

    public func tap(on device: DeviceID, at point: Point, settle: Bool) async throws {
        try await target(device).tap(on: device, at: point, settle: settle)
    }

    public func swipe(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {
        try await target(device).swipe(on: device, from: from, to: to, durationMs: durationMs)
    }

    public func longPress(on device: DeviceID, at point: Point, durationMs: Int) async throws {
        try await target(device).longPress(on: device, at: point, durationMs: durationMs)
    }

    public func drag(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {
        try await target(device).drag(on: device, from: from, to: to, durationMs: durationMs)
    }

    public func pinch(on device: DeviceID, center: Point, scale: Double, durationMs: Int) async throws {
        try await target(device).pinch(on: device, center: center, scale: scale, durationMs: durationMs)
    }

    public func rotate(on device: DeviceID, center: Point, angle: Double, durationMs: Int) async throws {
        try await target(device).rotate(on: device, center: center, angle: angle, durationMs: durationMs)
    }

    public func scroll(on device: DeviceID, deltaX: Double, deltaY: Double, at point: Point?) async throws {
        try await target(device).scroll(on: device, deltaX: deltaX, deltaY: deltaY, at: point)
    }

    public func typeText(on device: DeviceID, text: String) async throws {
        try await target(device).typeText(on: device, text: text)
    }

    public func key(on device: DeviceID, key: Key, modifiers: KeyModifiers) async throws {
        try await target(device).key(on: device, key: key, modifiers: modifiers)
    }

    public func button(on device: DeviceID, button: HardwareButton) async throws {
        try await target(device).button(on: device, button: button)
    }

    private func target(_ device: DeviceID) async throws -> any InputControlling {
        let model = try await devices.device(device)
        return model.platform == .visionOS ? vision : standard
    }
}

public struct VisionOSRoutingAccessibility: AccessibilityReading {
    private let devices: any DeviceControlling
    private let standard: any AccessibilityReading

    public init(devices: any DeviceControlling, standard: any AccessibilityReading) {
        self.devices = devices
        self.standard = standard
    }

    public func tree(on device: DeviceID, maxDepth: Int, maxNodes: Int) async throws -> UITree {
        try await ensureStandard(device)
        return try await standard.tree(on: device, maxDepth: maxDepth, maxNodes: maxNodes)
    }

    public func find(on device: DeviceID, selector: ElementSelector) async throws -> [UIElement] {
        try await ensureStandard(device)
        return try await standard.find(on: device, selector: selector)
    }

    private func ensureStandard(_ device: DeviceID) async throws {
        let model = try await devices.device(device)
        guard model.platform != .visionOS else {
            throw OpenSimError(
                code: "a11y_unavailable",
                message: "Accessibility tree is not available for visionOS",
                details: ["platform": "visionOS"],
                recovery: "Use screenshot and tap by coordinates",
                retryable: false
            )
        }
    }
}
```

Trong `Sources/OpenSimBridge/Services/SimulatorBridgeImpl.swift`, sau khi có `screenService` và `inputService`:

```swift
let visionScreen = VisionOSScreenAdapter(base: screenService)
let visionInput = VisionOSInputAdapter(input: inputService, screens: screenService)
self.screen = VisionOSRoutingScreen(
    devices: devices,
    standard: screenService,
    vision: visionScreen
)
self.input = VisionOSRoutingInput(
    devices: devices,
    standard: inputService,
    vision: visionInput
)
self.accessibility = VisionOSRoutingAccessibility(
    devices: devices,
    standard: accessibilityService
)
```

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
swift test --filter VisionOSPlatformRouterTests
swift test --filter IntegrationTests
```

Expected: `Executed 6 tests, with 0 failures`; test iOS hiện có vẫn pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Platforms/VisionOS/VisionOSPlatformRouter.swift Sources/OpenSimBridge/Services/SimulatorBridgeImpl.swift Tests/OpenSimBridgeTests/VisionOSPlatformRouterTests.swift
git commit -m "feat(visionos): route screen and input by platform"
```

---

### Task 7: Fixture app visionOS

**Files:**
- Create: `Fixtures/OpenSimFixtureVision/project.yml`
- Create: `Fixtures/OpenSimFixtureVision/Sources/OpenSimFixtureVisionApp.swift`
- Create: `Fixtures/OpenSimFixtureVision/build.sh`

**Interfaces:**
- Produces: bundle `dev.opensim.fixture.vision`, element identifier `login-button`, `email-field`, `tap-count`, `email-value`; script in `OK vision fixture` hoặc `BUILD SUCCEEDED`.

- [ ] **Step 1: Viết project và app**

Create `Fixtures/OpenSimFixtureVision/project.yml`:

```yaml
name: OpenSimFixtureVision
options:
  bundleIdPrefix: dev.opensim
  deploymentTarget:
    visionOS: "27.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
targets:
  OpenSimFixtureVision:
    type: application
    platform: visionOS
    sources:
      - path: Sources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.opensim.fixture.vision
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
schemes:
  OpenSimFixtureVision:
    build:
      targets:
        OpenSimFixtureVision: all
```

Create `Fixtures/OpenSimFixtureVision/Sources/OpenSimFixtureVisionApp.swift`:

```swift
import SwiftUI

@main
struct OpenSimFixtureVisionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var tapCount = 0
    @State private var email = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("OpenSim visionOS Fixture")
                .font(.title2)
                .accessibilityIdentifier("fixture-title")

            Text("Taps: \(tapCount)")
                .accessibilityIdentifier("tap-count")

            Button("Login") {
                tapCount += 1
            }
            .accessibilityIdentifier("login-button")

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("email-field")

            Text(email.isEmpty ? "No email" : email)
                .accessibilityIdentifier("email-value")
        }
        .padding(32)
        .frame(minWidth: 700, minHeight: 500)
    }
}
```

Create `Fixtures/OpenSimFixtureVision/build.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
cd "$ROOT"
xcodegen generate --spec project.yml
xcodebuild \
  -project OpenSimFixtureVision.xcodeproj \
  -scheme OpenSimFixtureVision \
  -configuration Debug \
  -sdk xrsimulator \
  -destination "generic/platform=visionOS Simulator" \
  -derivedDataPath build \
  build
print "OK vision fixture"
```

- [ ] **Step 2: Build fixture**

Run:

```bash
chmod +x Fixtures/OpenSimFixtureVision/build.sh
Fixtures/OpenSimFixtureVision/build.sh
```

Expected trước khi tạo file: FAIL `project.yml not found`. Sau khi tạo: `** BUILD SUCCEEDED **`; `OK vision fixture`.

- [ ] **Step 3: Kiểm tra identifier trong binary**

Run:

```bash
APP="$(find Fixtures/OpenSimFixtureVision/build/Build/Products -name 'OpenSimFixtureVision.app' -maxdepth 3 | head -1)"
test -n "$APP"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist"
strings "$APP/OpenSimFixtureVision" | grep -q "login-button"
```

Expected: `dev.opensim.fixture.vision`; lệnh `grep` trả `0`.

- [ ] **Step 4: Commit**

```bash
git add Fixtures/OpenSimFixtureVision
git commit -m "test(visionos): add vision fixture app"
```

---

### Task 8: Screenshot polling trong BridgeUI

**Files:**
- Create: `Sources/OpenSimBridgeUI/VisionOSScreenModel.swift`
- Create: `Sources/OpenSimBridgeUI/VisionOSScreenView.swift`
- Create: `Tests/OpenSimBridgeUITests/VisionOSScreenModelTests.swift`
- Modify: `Package.swift` (thêm test target `OpenSimBridgeUITests`)

**Interfaces:**
- Consumes: `Screenshot`, `VisionOSRenderPolicy.pollingIntervalMilliseconds`.
- Produces: `VisionOSScreenModel(capture:)` với `image: NSImage?`, `refresh() async`; `VisionOSScreenView(capture:)` polling 100 ms, không chồng request.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimBridgeUITests/VisionOSScreenModelTests.swift`:

```swift
import Foundation
import XCTest
@testable import OpenSimBridgeUI
@testable import OpenSimCore

private let visionFixturePNG = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l6J3WQAAAABJRU5ErkJggg=="
)!

@MainActor
final class VisionOSScreenModelTests: XCTestCase {
    func testRefreshSetsImage() async {
        let model = VisionOSScreenModel { [png = visionFixturePNG] in
            Screenshot(
                path: nil,
                data: png,
                format: .png,
                width: 1,
                height: 1,
                scale: 1,
                capturedAt: Date(timeIntervalSince1970: 0)
            )
        }
        await model.refresh()
        XCTAssertNotNil(model.image)
    }

    func testFailureKeepsImageNil() async {
        let model = VisionOSScreenModel {
            throw OpenSimError(
                code: "simctl_failed",
                message: "capture failed",
                details: [:],
                recovery: "Retry",
                retryable: true
            )
        }
        await model.refresh()
        XCTAssertNil(model.image)
    }

    func testConcurrentRefreshDoesNotOverlap() async throws {
        let counter = Counter()
        let gate = Gate()
        let model = VisionOSScreenModel {
            await counter.increment()
            await gate.wait()
            return Screenshot(
                path: nil,
                data: visionFixturePNG,
                format: .png,
                width: 1,
                height: 1,
                scale: 1,
                capturedAt: Date(timeIntervalSince1970: 0)
            )
        }
        let first = Task { await model.refresh() }
        try await Task.sleep(nanoseconds: 50_000_000)
        await model.refresh()
        let during = await counter.value
        XCTAssertEqual(during, 1)
        await gate.release()
        await first.value
        let after = await counter.value
        XCTAssertEqual(after, 1)
    }
}

private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if open {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        open = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter VisionOSScreenModelTests
```

Expected: FAIL vì `VisionOSScreenModel` chưa tồn tại.

- [ ] **Step 3: Implement model và view**

Create `Sources/OpenSimBridgeUI/VisionOSScreenModel.swift`:

```swift
import AppKit
import Combine
import Foundation
import OpenSimCore

@MainActor
public final class VisionOSScreenModel: ObservableObject {
    @Published public private(set) var image: NSImage?

    private let capture: @Sendable () async throws -> Screenshot
    private var inFlight = false

    public init(capture: @escaping @Sendable () async throws -> Screenshot) {
        self.capture = capture
    }

    public func refresh() async {
        guard !inFlight else {
            return
        }
        inFlight = true
        defer { inFlight = false }
        guard let screenshot = try? await capture(),
              let data = screenshot.data,
              let image = NSImage(data: data) else {
            return
        }
        self.image = image
    }
}
```

Create `Sources/OpenSimBridgeUI/VisionOSScreenView.swift`:

```swift
import AppKit
import OpenSimCore
import SwiftUI

@MainActor
public struct VisionOSScreenView: View {
    @StateObject private var model: VisionOSScreenModel

    public init(capture: @escaping @Sendable () async throws -> Screenshot) {
        _model = StateObject(wrappedValue: VisionOSScreenModel(capture: capture))
    }

    public var body: some View {
        Group {
            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView("Waiting for visionOS frame")
                    .frame(minWidth: 480, minHeight: 320)
            }
        }
        .background(Color.black)
        .task {
            while !Task.isCancelled {
                await model.refresh()
                let interval = UInt64(VisionOSRenderPolicy.pollingIntervalMilliseconds) * 1_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }
}
```

Thêm test target vào `Package.swift`:

```swift
.testTarget(
    name: "OpenSimBridgeUITests",
    dependencies: ["OpenSimBridgeUI", "OpenSimCore"],
    path: "Tests/OpenSimBridgeUITests"
),
```

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
swift test --filter VisionOSScreenModelTests
```

Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridgeUI Tests/OpenSimBridgeUITests Package.swift
git commit -m "feat(visionos): add screenshot polling view"
```

---

### Task 9: Integration matrix cho visionOS

**Files:**
- Create: `Tests/IntegrationTests/VisionOSIntegrationTests.swift`
- Create: `Tests/Release/test-visionos.sh`

**Interfaces:**
- Consumes: CLI `.build/debug/opensim`, doctor JSON `data.platforms.visionOS`, fixture `dev.opensim.fixture.vision`.
- Produces: test skip khi thiếu `OPENSIM_VISIONOS=1` hoặc runtime; fail khi `OPENSIM_VISIONOS_REQUIRED=1`; script `test-visionos.sh` xác nhận cả hai hành vi.

- [ ] **Step 1: Viết test tích hợp**

Create `Tests/IntegrationTests/VisionOSIntegrationTests.swift`:

```swift
import Foundation
import XCTest

final class VisionOSIntegrationTests: XCTestCase {
    private var cli: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/opensim")
    }

    private var required: Bool {
        ProcessInfo.processInfo.environment["OPENSIM_VISIONOS_REQUIRED"] == "1"
    }

    func testReadinessMatrix() throws {
        try requireEnabled()
        let readiness = try visionReadiness()
        switch readiness {
        case "ready":
            XCTAssertTrue(true)
        case "runtimeMissing", "xcodeUnsupported":
            if required {
                XCTFail("visionOS is \(readiness) but OPENSIM_VISIONOS_REQUIRED=1")
            } else {
                throw XCTSkip("visionOS is \(readiness)")
            }
        default:
            XCTFail("unknown readiness: \(readiness)")
        }
    }

    func testBootRenderScreenshotTapAndType() throws {
        try requireEnabled()
        let readiness = try visionReadiness()
        guard readiness == "ready" else {
            if required {
                XCTFail("visionOS is \(readiness) but OPENSIM_VISIONOS_REQUIRED=1")
                return
            }
            throw XCTSkip("visionOS is \(readiness)")
        }

        let fixture = try fixtureURL()
        let deviceType = try firstVisionDeviceType()
        let runtime = try visionRuntimeIdentifier()
        let created = try runJSON([
            "device", "create", "OpenSim Vision Integration",
            "--type", deviceType,
            "--runtime", runtime,
            "--json"
        ])
        let data = try XCTUnwrap(created["data"] as? [String: Any])
        let udid = try XCTUnwrap(data["id"] as? String)

        defer { cleanup(udid: udid) }
        _ = try run(["device", "boot", "--device", udid, "--wait", "--json"])
        _ = try run(["app", "install", fixture.path, "--device", udid, "--json"])
        _ = try run(["app", "launch", "dev.opensim.fixture.vision", "--device", udid, "--json"])

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-vision-\(udid)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let before = directory.appendingPathComponent("before.png")
        let afterTap = directory.appendingPathComponent("after-tap.png")
        let afterType = directory.appendingPathComponent("after-type.png")

        _ = try run(["ui", "screenshot", "--device", udid, "--out", before.path])
        XCTAssertGreaterThan(try fileSize(before), 1_000)
        _ = try run(["ui", "tap", "--on", "id=login-button", "--device", udid, "--json"])
        Thread.sleep(forTimeInterval: 1)
        _ = try run(["ui", "screenshot", "--device", udid, "--out", afterTap.path])
        XCTAssertNotEqual(try Data(contentsOf: before), try Data(contentsOf: afterTap))

        _ = try run(["ui", "tap", "--on", "id=email-field", "--device", udid, "--json"])
        _ = try run(["ui", "type", "agent@opensim.dev", "--device", udid, "--json"])
        Thread.sleep(forTimeInterval: 1)
        _ = try run(["ui", "screenshot", "--device", udid, "--out", afterType.path])
        XCTAssertNotEqual(try Data(contentsOf: afterTap), try Data(contentsOf: afterType))

        let tree = try runAllowingFailure(["ui", "tree", "--device", udid, "--json"])
        XCTAssertNotEqual(tree.status, 0)
        XCTAssertTrue(tree.stdout.contains("a11y_unavailable") || tree.stderr.contains("a11y_unavailable"))
    }

    private func requireEnabled() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENSIM_INTEGRATION"] == "1" else {
            throw XCTSkip("OPENSIM_INTEGRATION is not 1")
        }
        guard environment["OPENSIM_VISIONOS"] == "1" else {
            throw XCTSkip("OPENSIM_VISIONOS is not 1")
        }
    }

    private func visionReadiness() throws -> String {
        let report = try runJSON(["doctor", "--json"])
        let data = try XCTUnwrap(report["data"] as? [String: Any])
        let platforms = try XCTUnwrap(data["platforms"] as? [String: Any])
        let vision = try XCTUnwrap(platforms["visionOS"] as? [String: Any])
        return try XCTUnwrap(vision["readiness"] as? String)
    }

    private func visionRuntimeIdentifier() throws -> String {
        let report = try runJSON(["doctor", "--json"])
        let data = try XCTUnwrap(report["data"] as? [String: Any])
        let platforms = try XCTUnwrap(data["platforms"] as? [String: Any])
        let vision = try XCTUnwrap(platforms["visionOS"] as? [String: Any])
        return try XCTUnwrap(vision["runtimeIdentifier"] as? String)
    }

    private func firstVisionDeviceType() throws -> String {
        let result = try VisionProcessRunner.run(
            "/usr/bin/xcrun",
            ["simctl", "list", "devicetypes", "-j"]
        )
        let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as! [String: Any]
        let types = try XCTUnwrap(object["devicetypes"] as? [[String: Any]])
        let match = try XCTUnwrap(types.first { ($0["name"] as? String)?.hasPrefix("Apple Vision Pro") == true })
        return try XCTUnwrap(match["identifier"] as? String)
    }

    private func fixtureURL() throws -> URL {
        if let path = ProcessInfo.processInfo.environment["OPENSIM_VISION_FIXTURE"] {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Fixtures/OpenSimFixtureVision/build/Build/Products/Debug-xrsimulator/OpenSimFixtureVision.app")
    }

    private func fileSize(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    private func cleanup(udid: String) {
        _ = try? run(["app", "terminate", "dev.opensim.fixture.vision", "--device", udid, "--json"])
        _ = try? run(["device", "shutdown", "--device", udid, "--json"])
        _ = try? run(["device", "delete", "--device", udid, "--yes", "--json"])
    }

    @discardableResult
    private func run(_ arguments: [String]) throws -> String {
        let result = try runAllowingFailure(arguments)
        guard result.status == 0 else {
            throw OpenSimIntegrationError.failed(arguments, result.status, result.stdout, result.stderr)
        }
        return result.stdout
    }

    private func runJSON(_ arguments: [String]) throws -> [String: Any] {
        let output = try run(arguments)
        return try JSONSerialization.jsonObject(with: Data(output.utf8)) as! [String: Any]
    }

    private func runAllowingFailure(_ arguments: [String]) throws -> VisionProcessResult {
        try VisionProcessRunner.run(cli.path, arguments)
    }
}

enum OpenSimIntegrationError: Error {
    case failed([String], Int32, String, String)
}

struct VisionProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum VisionProcessRunner {
    static func run(_ executable: String, _ arguments: [String]) throws -> VisionProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return VisionProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
```

- [ ] **Step 2: Viết script matrix**

Create `Tests/Release/test-visionos.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
cd "$ROOT"
PRESENT="$(xcrun simctl list runtimes -j | jq '[.runtimes[] | select((.identifier | contains("visionOS")) or (.name | contains("visionOS")))] | length')"

if [[ "$PRESENT" -eq 0 ]]; then
  OPENSIM_INTEGRATION=1 OPENSIM_VISIONOS=1 OPENSIM_VISIONOS_REQUIRED=0 \
    swift test --filter VisionOSIntegrationTests
  print "OK visionos skip without runtime"

  set +e
  OPENSIM_INTEGRATION=1 OPENSIM_VISIONOS=1 OPENSIM_VISIONOS_REQUIRED=1 \
    swift test --filter VisionOSIntegrationTests > /tmp/opensim-vision-required.log 2>&1
  STATUS=$?
  set -e
  if [[ "$STATUS" -eq 0 ]]; then
    print -u2 "required mode must fail without a visionOS runtime"
    exit 1
  fi
  print "OK visionos fail when required"
else
  OPENSIM_INTEGRATION=1 OPENSIM_VISIONOS=1 OPENSIM_VISIONOS_REQUIRED=1 \
    swift test --filter VisionOSIntegrationTests
  print "OK visionos matrix"
fi
```

- [ ] **Step 3: Chạy test để thấy fail**

Run:

```bash
chmod +x Tests/Release/test-visionos.sh
Tests/Release/test-visionos.sh
```

Expected trên máy chưa có runtime: test skip và in `OK visionos skip without runtime`, sau đó `OK visionos fail when required`. Trên máy có runtime: chạy đầy đủ và in `OK visionos matrix`. Nếu chưa có fixture: FAIL với `fixture not found`.

- [ ] **Step 4: Commit**

```bash
git add Tests/IntegrationTests/VisionOSIntegrationTests.swift Tests/Release/test-visionos.sh
git commit -m "test(visionos): add integration matrix and skip policy"
```

---

### Task 10: App/CLI integration và tài liệu visionOS

**Files:**
- Modify: `App/Sources/OpenSimApp/Windows/DeviceWindow.swift` (chọn `VisionOSScreenView`)
- Create: `docs/visionos.md`
- Modify: `docs/compatibility.md` (thêm dòng visionOS)
- Modify: `README.md` (ghi visionOS post-release)
- Modify: `docs/release-checklist.md` (đổi bước visionOS từ skip sang chạy matrix khi runtime có)

**Interfaces:**
- Consumes: `VisionOSScreenView`, `VisionOSRenderPolicy`, `opensim doctor` block `platforms.visionOS`, `opensim ui` đã route qua Task 6.
- Produces: app hiển thị frame visionOS bằng polling khi không có `SimDisplayView`; tài liệu runbook có approval và giới hạn.

- [ ] **Step 1: Sửa app chọn đường render**

Trong `App/Sources/OpenSimApp/Windows/DeviceWindow.swift`, thay chỗ dựng `SimulatorScreenView` bằng nhánh sau (dùng đúng bridge đã inject trong view):

```swift
if device.platform == .visionOS {
    if let screen = bridge.screen {
        VisionOSScreenView {
            try await screen.screenshot(
                on: device.id,
                format: .jpeg,
                scale: 0.5,
                quality: 80
            )
        }
    } else {
        ContentUnavailableView(
            "visionOS screen unavailable",
            systemImage: "visionpro",
            description: Text("Run opensim doctor --json and check platforms.visionOS.")
        )
    }
} else {
    SimulatorScreenView(device: device)
}
```

Thêm import:

```swift
import OpenSimBridgeUI
```

- [ ] **Step 2: Viết tài liệu runbook**

Create `docs/visionos.md`:

```markdown
# visionOS Support

visionOS là phạm vi post-release của Plan 8, sau khi Plan 7 phát hành bản simulator. Không có tính năng visionOS nào trong release 0.1.0.

## Yêu cầu

- macOS 27.0 trở lên, arm64.
- Xcode 27.1 với visionOS 27.0 SDK.
- Runtime visionOS 27.0 trong Xcode Settings > Components.
- Một device type có tên bắt đầu `Apple Vision Pro`.

## Owner approval để tải runtime

OpenSim không tự tải runtime. Quy trình:

1. Owner đọc tài liệu này và xác nhận dung lượng đĩa trống tối thiểu 30 GB.
2. Owner đặt biến môi trường:
   `export OPENSIM_APPROVE_VISIONOS_DOWNLOAD=1`
3. Chạy đúng một lệnh:
   `xcodebuild -downloadPlatform visionOS`
4. Kiểm tra:
   `xcrun simctl list runtimes -j | jq -r '.runtimes[] | select(.identifier | contains("visionOS")) | .identifier'`
5. Chạy:
   `opensim doctor --json | jq '.data.platforms.visionOS'`

Không có script, daemon, CI, hay app nào tự chạy lệnh tải. `Scripts/visionos/print-runtime-command.sh` chỉ in lệnh và exit 7 nếu chưa có approval.

## Device

- Device type resolve từ `xcrun simctl list devicetypes -j`, ưu tiên tên chính xác `Apple Vision Pro`, sau đó tên bắt đầu `Apple Vision Pro`.
- Tạo biến:
  `VISION_TYPE="$(xcrun simctl list devicetypes -j | jq -r '[.devicetypes[] | select(.name | startswith("Apple Vision Pro"))][0].identifier')"`
  `VISION_RUNTIME="$(xcrun simctl list runtimes -j | jq -r '[.runtimes[] | select(.identifier | contains("visionOS"))][0].identifier')"`
- Tạo device:
  `opensim device create "Vision Test" --type "$VISION_TYPE" --runtime "$VISION_RUNTIME" --json`
- Boot:
  `opensim device boot "Vision Test" --wait`

## Render và screenshot

- Nếu `SimDisplayView` kết nối được với device visionOS, app dùng live view.
- Nếu không, app dùng screenshot polling mỗi 100 ms; frame cuối được giữ khi capture lỗi.
- CLI screenshot và record dùng `simctl io`; không phụ thuộc private render.

## Input

Hỗ trợ:

- `tap`, `swipe`, `long-press`, `drag`: qua digitizer, tọa độ clamp theo screen.
- `type`, `key`: qua keyboard HID.

Không hỗ trợ, trả `input_failed`:

- `pinch`, `rotate`, `scroll`: visionOS không có gesture tương ứng trên simulator.
- `button`: không có Home/Lock/Side tương ứng.

## Accessibility

`ui tree` và `ui find` trả `a11y_unavailable` cho visionOS. Dùng screenshot và tap theo tọa độ đã đọc từ ảnh.

## Test

- Unit: `swift test --filter VisionOS`
- Fixture: `Fixtures/OpenSimFixtureVision/build.sh`
- Integration có runtime:
  `OPENSIM_INTEGRATION=1 OPENSIM_VISIONOS=1 OPENSIM_VISIONOS_REQUIRED=1 swift test --filter VisionOSIntegrationTests`
- Integration không runtime: đặt `OPENSIM_VISIONOS_REQUIRED=0`; test skip.
- Matrix script: `Tests/Release/test-visionos.sh`

## Giới hạn đã biết

- Không hỗ trợ eye tracking, hand pinch, immersive space, spatial audio.
- Không hỗ trợ nhiều cửa sổ visionOS trong một scene; mỗi device là một cửa sổ app.
- Không có accessibility tree; không có VoiceOver introspection từ simulator.
- Chưa đo fps/latency chính thức cho visionOS; polling có thể thấp hơn 60 fps.
- Chỉ chạy với runtime visionOS 27.0 trên Xcode 27.1; runtime khác trả `xcodeUnsupported` hoặc `runtimeMissing`.
```

- [ ] **Step 3: Cập nhật compatibility và README**

Thêm dòng vào bảng trong `docs/compatibility.md` sau dòng Xcode 27.1:

```markdown
| 27.1 | supported | visionOS 27.0 (post-release Plan 8) | Adapter riêng; accessibility tree unavailable; screenshot polling fallback |
```

Thêm vào mục Yêu cầu của `README.md`:

```markdown
- visionOS 27.0 là post-release, ngoài phạm vi 0.1.0; xem `docs/visionos.md` trước khi tải runtime.
```

Trong `docs/release-checklist.md`, thay dòng:

```markdown
- [ ] `Tests/Release/test-visionos.sh` skip hợp lệ vì visionOS ngoài phạm vi release này.
```

bằng:

```markdown
- [ ] `Tests/Release/test-visionos.sh` in `OK visionos skip without runtime` cho release 0.1.0; với bản có visionOS, in `OK visionos matrix`.
```

- [ ] **Step 4: Build app và kiểm tra tài liệu**

Run:

```bash
xcodegen generate --spec App/project.yml
xcodebuild \
  -project App/OpenSim.xcodeproj \
  -scheme OpenSim \
  -configuration Debug \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build
grep -q "xcodebuild -downloadPlatform visionOS" docs/visionos.md
grep -q 'OPENSIM_APPROVE_VISIONOS_DOWNLOAD=1' docs/visionos.md
grep -q "visionOS 27.0 (post-release Plan 8)" docs/compatibility.md
```

Expected: `** BUILD SUCCEEDED **`; ba lệnh `grep` trả `0`.

- [ ] **Step 5: Chạy lại toàn bộ test visionOS**

Run:

```bash
swift test --filter VisionOS
Tests/Release/test-visionos-runtime-gate.sh
Tests/Release/test-visionos.sh
```

Expected: tất cả unit visionOS pass; `OK visionos runtime gate`; `OK visionos skip without runtime` và `OK visionos fail when required` khi máy chưa có runtime, hoặc `OK visionos matrix` khi có runtime.

- [ ] **Step 6: Commit**

```bash
git add App/Sources/OpenSimApp/Windows/DeviceWindow.swift docs/visionos.md docs/compatibility.md docs/release-checklist.md README.md
git commit -m "feat(visionos): integrate polling view and document support"
```

---

## Spec coverage

| Mục spec | Nội dung | Task |
|---|---|---|
| 2 mục 6 | Hỗ trợ iOS/iPadOS/watchOS/tvOS; visionOS là plan riêng | 1, 10 |
| 3 | visionOS ngoài phạm vi release đầu | 1, 10 |
| 5.4 | Private API chỉ trong Bridge; capability gate và fallback | 3, 4, 6 |
| 5.5 | Luồng boot, agent thao tác, screenshot | 9 |
| 5.6 | Tương thích Xcode/runtime, compat mode | 1, 5 |
| 7.2 | `device create/boot`, `runtime list`, `ui` trên visionOS | 2, 6, 9 |
| 8.2 | Tool `device_create`, `screen_screenshot`, `ui_tap`, `doctor_report` | 5, 6, 9 |
| 9.2 | Cửa sổ device render trực tiếp hoặc fallback | 3, 8, 10 |
| 9.3 | Capability thiếu thì banner/disable, không crash | 5, 8, 10 |
| 14.2 | Integration boot/render/screenshot/tap, skip/fail | 9 |
| 17.1 mục 12 | Mở rộng acceptance watch/tv sang visionOS | 9 |
| 18 | Rủi ro private API, fallback screenshot polling | 1, 3, 5 |
| 19 | Release simulator không gồm visionOS; Plan 8 post-release | 1, 10 |
| 16 Plan 8 | Platform adapter, fixture, render/input, test | 1-10 |

## Exit criteria

1. `Sources/OpenSimCore` không thay đổi tên type/protocol; `git diff --name-only` cho Plan 8 không có file trong `Sources/OpenSimCore`.
2. `swift test --filter VisionOSRuntimeGateTests` pass 8 test; `Tests/Release/test-visionos-runtime-gate.sh` in `OK visionos runtime gate`; không có lệnh tải runtime nào được chạy tự động.
3. `swift test --filter VisionOSDeviceProvisionerTests` pass 4 test; resolver chọn `Apple Vision Pro` và provisioner gọi đúng `deviceType`/`runtime`.
4. `swift test --filter VisionOSScreenAdapterTests` pass 4 test; `swift test --filter VisionOSInputAdapterTests` pass 5 test; `pinch`, `rotate`, `scroll`, `button` trả `input_failed`.
5. `swift test --filter VisionOSSupportReportTests` pass 3 test; `opensim doctor --json` có `data.platforms.visionOS.readiness`.
6. `swift test --filter VisionOSPlatformRouterTests` pass 6 test; iOS đi đường cũ, visionOS đi adapter.
7. `Fixtures/OpenSimFixtureVision/build.sh` in `OK vision fixture`; bundle ID `dev.opensim.fixture.vision`.
8. `swift test --filter VisionOSScreenModelTests` pass 3 test; polling không chồng request.
9. `Tests/Release/test-visionos.sh` in `OK visionos skip without runtime` và `OK visionos fail when required` trên máy không có runtime; với runtime có sẵn, in `OK visionos matrix` và test boot/render/screenshot/tap/type pass.
10. `docs/visionos.md` chứa đúng `xcodebuild -downloadPlatform visionOS`, approval `OPENSIM_APPROVE_VISIONOS_DOWNLOAD=1`, danh sách tính năng không hỗ trợ; app build success với nhánh `VisionOSScreenView`.