# OpenSim Plan 9 — Thiết bị thật qua CoreDevice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm hỗ trợ iPhone/iPad thật sau release simulator: discovery CoreDevice có hard gate, pairing/trust, kiểm tra signing, install/launch/terminate, screenshot, HID nếu có, log, device info, app container, CLI/MCP/UI, security và audit. Phần không xác minh được trả unsupported rõ ràng, không giả lập thành công.

**Architecture:** `OpenSimBridge/Physical` chứa adapter tuân theo `DeviceControlling`, `AppControlling`, `LogControlling`, `ScreenControlling`, `InputControlling`, `AccessibilityReading` đã có. `CompositeSimulatorBridge` route theo prefix `physical:` của `DeviceID`, nên daemon, CLI, MCP và app dùng lại đường hiện có mà không đổi type/protocol lõi. `devicectl` của Apple là bề mặt chính; command/selector chưa xác minh nằm trong manifest do Task 1 tạo, không hardcode. Write physical chỉ qua daemon để có lease và audit.

**Tech Stack:** Swift 6, SwiftPM, XCTest, Foundation `Process`, `dlopen` chỉ trong script probe, `devicectl` của Xcode 27.1, `codesign`, `security cms -D`, SwiftUI, `jq`, `zsh`.

**Spec:** `docs/superpowers/specs/2026-10-19-open-simulator-design.md`

**Plan phụ thuộc:** `docs/superpowers/plans/2026-10-20-opensim-plan-3-daemon-session-mcp.md`, `docs/superpowers/plans/2026-10-20-opensim-plan-7-release.md`.

## Global Constraints

- Chỉ bắt đầu sau khi Plan 7 đạt exit criteria. Plan 9 là post-release, không chặn release simulator.
- Không đổi tên, kiểu, field hay signature của type/protocol trong `docs/superpowers/plans/2026-10-20-plan-map-and-interfaces.md`. Chỉ thêm adapter/type trong `OpenSimBridge/Physical`, một file catalog mới trong `OpenSimCore/Catalog`, và một nhánh exact-ID trong `DeviceResolver`.
- Task 1 là hard gate. `gate.list` fail: dừng plan, chỉ ghi report + manifest `deferred`. Pair/install/launch/terminate fail: chuyển `readOnly`. Screenshot/HID/log fail: capability tương ứng `unavailable`.
- Không bịa selector, class, command, flag, JSON key hay error code. Mọi thứ chưa xác minh nằm trong `CoreDeviceManifest.json` với default `deferred`/`false`/rỗng; Task 1 chỉ điền từ output thật.
- Chỉ chạy `devicectl` qua `/usr/bin/xcrun` với argument array. Không shell string, không `bash -c`, không `zsh -c`, không `PATH` lookup.
- Không lưu credential, không ghi keychain, không chạy `codesign --sign`, không cài provisioning profile, không dùng tài khoản Apple trong OpenSim.
- Trust prompt chỉ trên thiết bị. Không tự bấm Trust, không treo UI vô hạn, không retry im lặng.
- Write physical bắt buộc qua daemon để có session/lease/audit. `--direct` từ chối write physical với `daemon_unavailable`.
- Validate UDID theo `PhysicalDeviceID`, bundle ID theo `IdentifierValidation.validateBundleID`, path theo `PathPolicy`/`PathAllowlist` của Plan 7.
- Integration chỉ chạy khi `OPENSIM_PHYSICAL_DEVICE_UDID` được đặt; thiếu thì skip. CI không bao giờ yêu cầu hardware.
- Mọi task có check đỏ, implement, check xanh, commit. Plan author không chạy commit.
- Văn xuôi tiếng Việt; code, type, identifier, command tiếng Anh; không ký tự CJK; không Chrome, không download, không lệnh destructive.

---

## File Structure

| File | Trách nhiệm | Task |
|---|---|---|
| `Scripts/physical/check-coredevice.sh` | Validate report + manifest trước implement | 1 |
| `Scripts/physical/probe-coredevice.swift` | Probe class/selector đã thấy trong binary | 1 |
| `docs/spikes/2026-10-20-coredevice-discovery.md` | Bằng chứng command, JSON key, gate, decision | 1 |
| `Fixtures/CoreDevice/devicectl-list-devices.json` | Fixture list, ghi rõ captured hay synthetic | 1 |
| `Sources/OpenSimBridge/Physical/CoreDeviceManifest.json` | Mode, gates, keyMap, recipes, classes | 1 |
| `Sources/OpenSimBridge/Physical/PhysicalDeviceID.swift` | Grammar `physical:<udid>` | 2 |
| `Sources/OpenSimBridge/Physical/PhysicalModels.swift` | Transport, pairing, status, capability set | 2 |
| `Sources/OpenSimBridge/Physical/PhysicalError.swift` | Map lỗi sang `OpenSimError` hiện có | 2 |
| `Sources/OpenSimBridge/Physical/CoreDeviceManifest.swift` | Decode manifest, default deferred | 2 |
| `Sources/OpenSimBridge/Physical/CoreDeviceProcessRunning.swift` | Process runner, timeout, env sanitize | 3 |
| `Sources/OpenSimBridge/Physical/DevicectlClient.swift` | Gọi `xcrun devicectl` | 3 |
| `Sources/OpenSimBridge/Physical/DevicectlJSON.swift` | Traverse JSON theo keyMap | 3 |
| `Sources/OpenSimBridge/Physical/PhysicalDeviceService.swift` | List/status/cache/single-flight | 3 |
| `Sources/OpenSimBridge/Physical/PhysicalPairingService.swift` | Pair/unpair, poll trust, Developer Mode | 4 |
| `Sources/OpenSimBridge/Physical/PhysicalSigningInspector.swift` | codesign, profile, UDID check | 4 |
| `Sources/OpenSimBridge/Physical/PhysicalAppService.swift` | List/install/launch/terminate/info | 5 |
| `Sources/OpenSimBridge/Physical/PhysicalContainerService.swift` | App/data/group container | 5 |
| `Sources/OpenSimBridge/Physical/CoreDeviceRecipeRunner.swift` | Chạy recipe `${placeholder}` | 6 |
| `Sources/OpenSimBridge/Physical/PhysicalScreenService.swift` | Screenshot qua recipe | 6 |
| `Sources/OpenSimBridge/Physical/PhysicalInputService.swift` | HID qua recipe, validate tọa độ | 6 |
| `Sources/OpenSimBridge/Physical/PhysicalLogService.swift` | Log tail, cursor, filter | 6 |
| `Sources/OpenSimBridge/Physical/PhysicalRuntimeService.swift` | Runtime simulator-only | 7 |
| `Sources/OpenSimBridge/Physical/PhysicalAccessibilityService.swift` | `a11y_unavailable` | 7 |
| `Sources/OpenSimBridge/Physical/PhysicalBridge.swift` | Aggregate + factory | 7 |
| `Sources/OpenSimBridge/Physical/PhysicalAdminService.swift` | Pair/unpair/status/check-signing cho operation physical | 7 |
| `Sources/OpenSimBridge/Physical/CompositeSimulatorBridge.swift` | Route simulator/physical | 7 |
| `Sources/OpenSimBridge/Physical/PhysicalPresentation.swift` | Badge, unsupported reasons | 7 |
| `Sources/OpenSimCore/Catalog/PhysicalOperations.swift` | Bốn operation physical | 8 |
| `Sources/OpenSimCore/Catalog/OpenSimCatalog.swift` | `OperationCatalog.openSim()` | 8 |
| `Sources/OpenSimBridge/Physical/PhysicalAuditPolicy.swift` | Action `physical.*` | 8 |
| `Sources/OpenSimCore/Validation/DeviceResolver.swift` | Exact-ID branch cho `physical:` | 8 |
| `Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift` | Route operation physical | 8 |
| `Sources/OpenSimDaemon/Runtime/DaemonRunner.swift` | Compose composite bridge | 8 |
| `Sources/OpenSimDaemon/Operations/OperationDispatcher.swift` | Physical handlers, audit | 8 |
| `Sources/OpenSimDaemon/Server/DaemonServer.swift` | Catalog `openSim()` | 8 |
| `Sources/OpenSimCLI/Commands/PhysicalCommand.swift` | CLI physical | 9 |
| `Sources/OpenSimCLI/Commands/DeviceCommands.swift` | Cột Source | 9 |
| `Sources/OpenSimCLI/Commands/OpenSimCommand.swift` | Nhóm physical | 9 |
| `Sources/OpenSimCLI/Commands/OpenSimCommandCatalog.swift` | Catalog `openSim()` | 9 |
| `Sources/OpenSimCLI/Commands/MCPCommand.swift` | Catalog `openSim()` | 9 |
| `Sources/OpenSimCLI/Commands/DoctorCommand.swift` | Block `physical` | 9 |
| `Sources/OpenSimMCP/Tools/PhysicalToolPresenter.swift` | Text summary physical | 9 |
| `Sources/OpenSimMCP/Server/MCPHandler.swift` | Dùng presenter | 9 |
| `App/Sources/OpenSimApp/Windows/PhysicalDeviceBadge.swift` | Badge Physical + transport | 10 |
| `App/Sources/OpenSimApp/Windows/PhysicalDeviceNotice.swift` | Unsupported notice | 10 |
| `App/Sources/OpenSimApp/Windows/PhysicalTrustBanner.swift` | Trust/Developer Mode | 10 |
| `App/Sources/OpenSimApp/Windows/PhysicalSigningSheet.swift` | Preflight trước install | 10 |
| `App/Sources/OpenSimApp/Windows/DeviceWindow.swift` | Không dùng live view cho physical | 10 |
| `App/Sources/OpenSimApp/Windows/DeviceWindowToolbar.swift` | Badge + disable control | 10 |
| `App/Sources/OpenSimApp/App/AppShell.swift` | Badge trong row | 10 |
| `App/Sources/OpenSimApp/App/DaemonClient.swift` | `physicalStatus(deviceID:)` | 10 |
| `Tests/OpenSimBridgeTests/Physical/PhysicalTestSupport.swift` | Stub/fixture dùng chung cho test physical | 2 |
| `Tests/OpenSimBridgeTests/Physical/*Tests.swift` | Unit/contract với fake | 2-7 |
| `Tests/OpenSimCoreTests/PhysicalOperationsTests.swift` | Catalog metadata | 8 |
| `Tests/OpenSimDaemonTests/PhysicalRoutingTests.swift` | Audit policy | 8 |
| `Tests/OpenSimCLITests/PhysicalCommandTests.swift` | Parse/exit code | 9 |
| `Tests/OpenSimMCPTests/PhysicalToolTests.swift` | Tools/list, presenter | 9 |
| `Tests/OpenSimAppUITests/PhysicalDeviceUITests.swift` | Badge/notice fixture | 10 |
| `Tests/SecurityTests/PhysicalSecurityTests.swift` | Direct write, path, trust | 11 |
| `Scripts/security/check-physical-no-credentials.sh` | Cấm credential/keychain | 11 |
| `Scripts/security/check-physical-no-shell.sh` | Cấm shell string | 11 |
| `Tests/IntegrationTests/PhysicalDeviceIntegrationTests.swift` | Env-gated hardware test | 12 |
| `Tests/Release/test-physical.sh` | Unit + skip integration | 12 |
| `.github/workflows/physical.yml` | `workflow_dispatch`, không bắt buộc | 12 |
| `docs/physical-device-checklist.md` | Checklist trust/pairing/signing | 12 |
| `docs/physical-devices.md` | Runbook, matrix, security | 13 |
| `README.md`, `docs/compatibility.md`, `docs/release-checklist.md` | Ghi post-release | 13 |

---

### Task 1: Discovery CoreDevice và hard gate

**Files:**
- Create: `Scripts/physical/check-coredevice.sh`
- Create: `Scripts/physical/probe-coredevice.swift`
- Create: `docs/spikes/2026-10-20-coredevice-discovery.md`
- Create: `Fixtures/CoreDevice/devicectl-list-devices.json`
- Create: `Sources/OpenSimBridge/Physical/CoreDeviceManifest.json`

**Interfaces:**
- Consumes: `xcrun devicectl`, `CoreDevice.framework`, `jq`, `plutil`, `nm`, `strings`.
- Produces: report có `## devicectl`, `## coredevice`, `## gates`, `## decision`; manifest schema 1; script in `OK coredevice discovery`.

- [ ] **Step 1: Viết script check thất bại**

```zsh
#!/bin/zsh
set -euo pipefail
REPORT="docs/spikes/2026-10-20-coredevice-discovery.md"
MANIFEST="Sources/OpenSimBridge/Physical/CoreDeviceManifest.json"
[[ -s "$REPORT" ]] || { print -u2 "missing report"; exit 1; }
for section in devicectl coredevice gates decision; do
  grep -q "^## $section" "$REPORT" || { print -u2 "missing $section"; exit 1; }
done
jq -e '
  .schemaVersion == 1 and
  (.mode == "deferred" or .mode == "readOnly" or .mode == "full") and
  (.gates | type == "object") and (.keyMap | type == "object") and
  (.recipes | type == "object") and (.classes | type == "array")
' "$MANIFEST" >/dev/null
print "OK coredevice discovery"
```

Run `chmod +x Scripts/physical/check-coredevice.sh && Scripts/physical/check-coredevice.sh`. Expected: FAIL vì report/manifest chưa có.

- [ ] **Step 2: Chạy discovery command surface**

```bash
mkdir -p docs/spikes Fixtures/CoreDevice Sources/OpenSimBridge/Physical Scripts/physical
xcrun --find devicectl
xcrun devicectl --version
xcrun devicectl help
xcrun devicectl device help
xcrun devicectl device info --help
xcrun devicectl device process --help
xcrun devicectl device install --help
xcrun devicectl device copy --help
xcrun devicectl manage --help
xcrun devicectl list devices --json-output /tmp/opensim-devicectl-devices.json
jq 'keys' /tmp/opensim-devicectl-devices.json
```

Nếu có thiết bị, chạy thêm `devicectl device info details --help`, `info files --help`, `info apps --help`, `info displays --help`, và lưu JSON list vào fixture. Redact tên/UDID bằng `jq`, thay bằng `Test iPhone` và `00008030-001A2D3E0E8A802E`. Nếu không có thiết bị, tạo fixture synthetic tối thiểu với các key `identifier`, `deviceProperties.name`, `hardwareProperties.udid`, `connectionProperties.pairingState`, và ghi `fixtureSource = synthetic` trong report.

- [ ] **Step 3: Ghi report**

Report phải có đúng bốn mục:

```markdown
## devicectl
Paste output version/help/list JSON; ghi rõ key path cho identifier, udid, name,
productType, osVersion, build, transport, pairing, developerMode, ddi.
Ghi rõ install/launch/terminate có --json-output hay không, pid nằm ở đâu.

## coredevice
Paste output:
ls -la /Library/Developer/PrivateFrameworks/CoreDevice.framework
plutil -p /Library/Developer/PrivateFrameworks/CoreDevice.framework/Info.plist
nm -gU /Library/Developer/PrivateFrameworks/CoreDevice.framework/Versions/A/CoreDevice | head -200
strings /Library/Developer/PrivateFrameworks/CoreDevice.framework/Versions/A/CoreDevice \
  | grep -E 'screenshot|Screenshot|HID|hid|logStream|LogStream' | sort -u | head -100
Tạo Fixtures/CoreDevice/candidates.txt chỉ từ tên đã thấy, mỗi dòng ClassName|selectorName.
Chạy probe-coredevice.swift và paste coredevice-probe.json. Không đoán selector.

## gates
Bảng: list, pair, install, launch, terminate, launchJSON, appList, containers,
screenshot, input, log. Mỗi gate true chỉ khi command/recipe đã chạy được.
`launchJSON` true chỉ khi `device process launch --json-output` trả JSON có pid.

## decision
mode: deferred, readOnly, hoặc full.
Lý do, capability unavailable, fallback, ngày review.
```

`probe-coredevice.swift` chỉ kiểm tra class/selector đã thấy, không gọi selector:

```swift
import Foundation
import Darwin
import ObjectiveC.runtime

let framework = ProcessInfo.processInfo.environment["OPENSIM_COREDEVICE_FRAMEWORK"]
    ?? "/Library/Developer/PrivateFrameworks/CoreDevice.framework/CoreDevice"
let candidatePath = ProcessInfo.processInfo.environment["OPENSIM_COREDEVICE_CANDIDATES"]
    ?? "Fixtures/CoreDevice/candidates.txt"
guard dlopen(framework, RTLD_NOW) != nil else {
    FileHandle.standardError.write(Data("cannot load \(framework)\n".utf8))
    exit(1)
}
let lines = try String(contentsOfFile: candidatePath, encoding: .utf8)
    .split(separator: "\n").map(String.init)
    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
var results: [[String: String]] = []
for line in lines {
    let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { continue }
    guard let cls = NSClassFromString(parts[0]) else {
        results.append(["class": parts[0], "selector": parts[1], "status": "classMissing"])
        continue
    }
    let exists = class_getInstanceMethod(cls, NSSelectorFromString(parts[1])) != nil
    results.append(["class": parts[0], "selector": parts[1],
                    "status": exists ? "responds" : "selectorMissing"])
}
let output = try JSONSerialization.data(
    withJSONObject: ["framework": framework, "results": results],
    options: [.prettyPrinted, .sortedKeys]
)
FileHandle.standardOutput.write(output)
```

Script không gọi selector, không đoán thêm tên, không kết luận capability chỉ từ tên class.

- [ ] **Step 4: Tạo manifest default an toàn**

```json
{
  "schemaVersion": 1,
  "mode": "deferred",
  "devicectlPath": "/usr/bin/xcrun",
  "deviceListPath": "",
  "keyMap": {},
  "gates": {
    "list": false, "pair": false, "install": false, "launch": false,
    "terminate": false, "launchJSON": false, "appList": false, "containers": false,
    "screenshot": false, "input": false, "log": false
  },
  "capabilities": {
    "screenshot": "unavailable", "input": "unavailable", "log": "unavailable"
  },
  "recipes": {},
  "classes": [],
  "notes": {}
}
```

Sau discovery, điền `deviceListPath`, `keyMap`, `gates`, `recipes`, `classes` chỉ từ report. `mode = deferred` nếu list fail; `readOnly` nếu pair/install/launch/terminate fail; `full` nếu tất cả gate chính pass. `recipes` chỉ chứa command đã chạy với placeholder `${udid}`, `${out}`, `${bundleID}`, `${x}`, `${y}`, `${durationMs}`, `${text}`, `${key}`, `${button}`.

- [ ] **Step 5: Chạy check và áp gate**

```bash
Scripts/physical/check-coredevice.sh
jq -r '.mode' Sources/OpenSimBridge/Physical/CoreDeviceManifest.json
```

Expected: `OK coredevice discovery`; mode `deferred`, `readOnly`, hoặc `full`.

Nếu `deferred`: dừng plan tại đây, không chạy Task 2-13, báo main agent fallback read-only hoặc defer. Nếu `readOnly`: Task 2-13 vẫn implement nhưng factory không cấp install/launch. Nếu `full`: chạy toàn bộ.

- [ ] **Step 6: Commit**

```bash
git add Scripts/physical docs/spikes/2026-10-20-coredevice-discovery.md Fixtures/CoreDevice Sources/OpenSimBridge/Physical/CoreDeviceManifest.json
git commit -m "docs(physical): record coredevice discovery and hard gate"
```

---

### Task 2: Identity, model, error và manifest

**Files:**
- Create: `Sources/OpenSimBridge/Physical/PhysicalDeviceID.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalModels.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalError.swift`
- Create: `Sources/OpenSimBridge/Physical/CoreDeviceManifest.swift`
- Modify: `Package.swift` (resource manifest)
- Test: `Tests/OpenSimBridgeTests/Physical/PhysicalTestSupport.swift`
- Test: `Tests/OpenSimBridgeTests/Physical/PhysicalDeviceIDTests.swift`
- Test: `Tests/OpenSimBridgeTests/Physical/PhysicalModelTests.swift`

**Interfaces:**
- Consumes: `DeviceID`, `Device`, `Capability`, `OpenSimError`, `OpenSimJSON`.
- Produces: `PhysicalDeviceID`, `PhysicalTransport`, `PhysicalPairingState`, `PhysicalDeveloperModeState`, `PhysicalCapabilitySet`, `PhysicalDeviceStatus`, `PhysicalMode`, `CoreDeviceManifest`, `PhysicalError`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class PhysicalDeviceIDTests: XCTestCase {
    func testLegacyAndModernUDID() throws {
        XCTAssertEqual(try XCTUnwrap(PhysicalDeviceID(udid: "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678")).rawValue,
                       "physical:a1b2c3d4e5f60718293a4b5c6d7e8f9012345678")
        XCTAssertEqual(try XCTUnwrap(PhysicalDeviceID(udid: "00008030-001A2D3E0E8A802E")).udid,
                       "00008030-001A2D3E0E8A802E")
    }

    func testRejectsTraversalAndWrongPrefix() {
        XCTAssertNil(PhysicalDeviceID(udid: "../etc/passwd"))
        XCTAssertNil(PhysicalDeviceID(reference: "00008030-001A2D3E0E8A802E"))
        XCTAssertFalse(PhysicalDeviceID.isPhysicalReference("physical:"))
    }

    func testMapsToDevice() {
        let status = PhysicalDeviceStatus.testFixture(pairing: .paired)
        let device = status.device
        XCTAssertEqual(device.id.rawValue, "physical:00008030-001A2D3E0E8A802E")
        XCTAssertEqual(device.platform, .iOS)
        XCTAssertEqual(device.state, .booted)
        XCTAssertEqual(device.runtime.rawValue, "physical-iOS-27.0")
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

`swift test --filter PhysicalDeviceIDTests`. Expected: FAIL vì type chưa tồn tại.

- [ ] **Step 3: Implement identity và models**

```swift
public struct PhysicalDeviceID: Hashable, Codable, Sendable, RawRepresentable {
    public static let prefix = "physical:"
    public let rawValue: String

    public init?(udid: String) {
        let legacy = "^[0-9A-Fa-f]{40}$"
        let modern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$"
        guard udid.range(of: legacy, options: .regularExpression) != nil
            || udid.range(of: modern, options: .regularExpression) != nil else { return nil }
        rawValue = Self.prefix + udid
    }

    public init?(rawValue: String) {
        guard rawValue.hasPrefix(Self.prefix) else { return nil }
        self.init(udid: String(rawValue.dropFirst(Self.prefix.count)))
    }

    public init?(deviceID: DeviceID) {
        self.init(rawValue: deviceID.rawValue)
    }

    public var udid: String { String(rawValue.dropFirst(Self.prefix.count)) }
    public var deviceID: DeviceID { DeviceID(rawValue: rawValue) }

    public static func isPhysicalReference(_ value: String) -> Bool {
        value.hasPrefix(prefix) && PhysicalDeviceID(rawValue: value) != nil
    }
}
```

Grammar UDID trên là giả thuyết từ định dạng Apple (40 hex cũ, 8-16 hex mới). Task 1 phải xác nhận với thiết bị thật; nếu UDID thật khác, sửa regex và thêm test trước khi implement tiếp.

`PhysicalModels.swift` định nghĩa `PhysicalTransport` (`usb`, `network`, `unknown`), `PhysicalPairingState` (`paired`, `unpaired`, `pendingTrust`, `trustDenied`, `unknown`), `PhysicalDeveloperModeState`, và:

```swift
public struct PhysicalCapabilitySet: Codable, Sendable, Equatable {
    public var list, pair, install, launch, terminate, appList, containers: Capability
    public var screenshot, input, log, accessibility, recording: Capability

    public static let allUnavailable = PhysicalCapabilitySet(
        list: .unavailable, pair: .unavailable, install: .unavailable,
        launch: .unavailable, terminate: .unavailable, appList: .unavailable,
        containers: .unavailable, screenshot: .unavailable, input: .unavailable,
        log: .unavailable, accessibility: .unavailable, recording: .unavailable
    )

    public var unsupportedFeatures: [String] {
        var values: [String] = []
        if pair == .unavailable { values.append("pairing") }
        if install == .unavailable { values.append("install") }
        if launch == .unavailable { values.append("launch") }
        if terminate == .unavailable { values.append("terminate") }
        if screenshot == .unavailable { values.append("screenshot") }
        if input == .unavailable { values.append("input") }
        if log == .unavailable { values.append("log tail") }
        if accessibility == .unavailable { values.append("accessibility tree") }
        if recording == .unavailable { values.append("screen recording") }
        if appList == .unavailable { values.append("app list") }
        if containers == .unavailable { values.append("app containers") }
        return values
    }
}

public struct PhysicalDeviceStatus: Codable, Sendable, Equatable {
    public var id: DeviceID
    public var udid, name, productType, osVersion, build: String
    public var transport: PhysicalTransport
    public var pairing: PhysicalPairingState
    public var developerMode: PhysicalDeveloperModeState
    public var ddiAvailable: Bool
    public var capabilities: PhysicalCapabilitySet
    public var checkedAt: Date
    public var notes: [String: String]

    public var device: Device {
        let ready = pairing == .paired && ddiAvailable
        return Device(
            id: id, name: name, platform: .iOS, deviceType: productType,
            runtime: RuntimeID(rawValue: "physical-iOS-\(osVersion)"),
            state: ready ? .booted : .unknown, isAvailable: ready,
            dataPath: nil, lastBootedAt: nil
        )
    }
}
```

Tạo `Tests/OpenSimBridgeTests/Physical/PhysicalTestSupport.swift` chứa helper dùng chung:

```swift
import Foundation
import OpenSimCore
@testable import OpenSimBridge

extension DeviceID {
    static let simulatorID = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")
    static let testID = PhysicalDeviceID.testID.deviceID
}

extension PhysicalDeviceID {
    static let testID = PhysicalDeviceID(udid: "00008030-001A2D3E0E8A802E")!
}

extension CoreDeviceManifest {
    static let testManifest = CoreDeviceManifest(
        schemaVersion: 1, mode: .full, devicectlPath: "/usr/bin/xcrun",
        deviceListPath: "result.devices",
        keyMap: [
            "identifier": "identifier",
            "udid": "hardwareProperties.udid",
            "name": "deviceProperties.name",
            "productType": "hardwareProperties.productType",
            "osVersion": "deviceProperties.osVersionNumber",
            "build": "deviceProperties.buildVersion",
            "transport": "connectionProperties.transportType",
            "pairing": "connectionProperties.pairingState",
            "developerMode": "deviceProperties.developerModeStatus",
            "ddi": "deviceProperties.ddiServicesAvailable",
            "containerPath": "result.path",
            "containerDomain.app": "appBundle",
            "containerDomain.data": "appDataContainer",
            "containerDomain.group": "groupContainer"
        ],
        gates: ["list": true, "pair": true, "install": true, "launch": true,
                "terminate": true, "launchJSON": true, "appList": true, "containers": true,
                "screenshot": false, "input": false, "log": false],
        capabilities: ["screenshot": "unavailable", "input": "unavailable", "log": "unavailable"],
        recipes: [:], classes: [], notes: [:]
    )
}

extension PhysicalDeviceRecord {
    static func testRecord(_ pairing: PhysicalPairingState) -> PhysicalDeviceRecord {
        PhysicalDeviceRecord(
            udid: PhysicalDeviceID.testID.udid, name: "Test iPhone",
            productType: "iPhone17,1", osVersion: "27.0", build: "24A434",
            transport: .usb, pairing: pairing, developerMode: .enabled, ddiAvailable: true
        )
    }
}

extension PhysicalDeviceStatus {
    static func testFixture(pairing: PhysicalPairingState) -> PhysicalDeviceStatus {
        PhysicalDeviceStatus(
            id: .testID, udid: PhysicalDeviceID.testID.udid, name: "Test iPhone",
            productType: "iPhone17,1", osVersion: "27.0", build: "24A434",
            transport: .usb, pairing: pairing, developerMode: .enabled,
            ddiAvailable: true, capabilities: .allUnavailable,
            checkedAt: Date(timeIntervalSince1970: 1_797_000_000), notes: [:]
        )
    }
}

extension Device {
    static func testDevice(_ id: DeviceID, _ name: String) -> Device {
        Device(id: id, name: name, platform: .iOS, deviceType: "iPhone17,1",
               runtime: RuntimeID(rawValue: "iOS-27-0"), state: .booted, isAvailable: true,
               dataPath: nil, lastBootedAt: nil)
    }
}

actor StubDeviceLister: PhysicalDeviceListing {
    private var responses: [[PhysicalDeviceRecord]]
    init(responses: [[PhysicalDeviceRecord]]) { self.responses = responses }
    func records() async throws -> [PhysicalDeviceRecord] {
        guard !responses.isEmpty else { return [] }
        return responses.removeFirst()
    }
}

struct FakeSigning: PhysicalSigningInspecting {
    var installable: Bool
    func inspect(appPath: String, targetUDID: String?) async throws -> PhysicalSigningReport {
        PhysicalSigningReport(
            appPath: appPath, bundleID: "com.example.app", teamIdentifier: "TEAM123",
            authorities: ["Apple Development"], expiresAt: Date(timeIntervalSinceNow: 86_400),
            profileName: "Test", provisionedDeviceCount: 1, targetUDIDIncluded: true,
            checks: [], isInstallable: installable
        )
    }
}
```

`PhysicalDeviceRecord`, `PhysicalSigningReport` và các struct khác có memberwise init internal; test target dùng `@testable`. Không đặt fixture trong production.

- [ ] **Step 4: Implement error và manifest**

`PhysicalError` dùng đúng code hiện có:

```swift
public enum PhysicalError {
    public static func simulatorOnly(_ operation: String) -> OpenSimError {
        OpenSimError(code: .capabilityUnavailable,
            message: "Operation \(operation) is simulator-only",
            details: ["capability": operation, "reason": "simulator_only"],
            recovery: "Use a simulator device for this operation", retryable: false)
    }
    public static func unavailable(_ capability: String, reason: String) -> OpenSimError {
        OpenSimError(code: .capabilityUnavailable,
            message: "Physical capability \(capability) is unavailable",
            details: ["capability": capability, "reason": reason],
            recovery: "Run `opensim doctor --json` and read the physical section",
            retryable: false)
    }
    public static func trustRequired() -> OpenSimError {
        OpenSimError(code: .permissionDenied, message: "The device is not trusted by this Mac",
            details: ["reason": "trust_required"],
            recovery: "Unlock the device, tap Trust, then run `opensim physical pair` again",
            retryable: true)
    }
    public static func developerModeDisabled() -> OpenSimError {
        OpenSimError(code: .permissionDenied, message: "Developer Mode is disabled on the device",
            details: ["reason": "developer_mode_disabled"],
            recovery: "Enable Settings > Privacy & Security > Developer Mode and reboot",
            retryable: true)
    }
    public static func devicectlFailed(status: Int32, stderr: String) -> OpenSimError {
        OpenSimError(code: .internalError, message: "devicectl failed with status \(status)",
            details: ["tool": "devicectl", "status": "\(status)", "stderr": String(stderr.prefix(2_000))],
            recovery: "Run the same command manually with `xcrun devicectl`", retryable: true)
    }
    public static func deviceLocked() -> OpenSimError {
        OpenSimError(code: .deviceBusy, message: "The device is locked",
            details: ["reason": "device_locked"],
            recovery: "Unlock the device and retry", retryable: true)
    }
    public static func invalidSignature(_ reason: String, message: String) -> OpenSimError {
        OpenSimError(code: .invalidArgument, message: message,
            details: ["reason": reason],
            recovery: "Build and sign the app with a development profile that includes this device",
            retryable: false)
    }
    public static func inputFailed(_ reason: String, gesture: String? = nil) -> OpenSimError {
        var details = ["reason": reason]
        if let gesture { details["gesture"] = gesture }
        return OpenSimError(code: .inputFailed, message: "Physical input failed",
            details: details, recovery: "Check the manifest recipe and the device screen",
            retryable: false)
    }
    public static func accessibilityUnavailable() -> OpenSimError {
        OpenSimError(code: .a11yUnavailable, message: "Accessibility tree is unavailable for physical devices",
            details: ["reason": "physical_a11y_unavailable"],
            recovery: "Use screenshot and coordinate input", retryable: false)
    }
}
```

`CoreDeviceManifest` có `schemaVersion`, `mode`, `devicectlPath`, `deviceListPath`, `keyMap`, `gates`, `capabilities`, `recipes`, `classes`, `notes`; `static func defaultDeferred()`, `load(from:)`, `bundled()` dùng `Bundle.module` với `subdirectory: "Physical"`, `gate(_:)`, `recipe(_:)`, `capability(_:)`. `Package.swift` thêm `.copy("Physical/CoreDeviceManifest.json")` vào resources của `OpenSimBridge`.

- [ ] **Step 5: Chạy pass và commit**

`swift test --filter PhysicalDeviceIDTests` pass 3 test; `swift test --filter PhysicalModelTests` pass manifest default/device mapping.

```bash
git add Package.swift Sources/OpenSimBridge/Physical Tests/OpenSimBridgeTests/Physical
git commit -m "feat(physical): add identity models errors and manifest"
```

---

### Task 3: Process runner, devicectl client và device service

**Files:**
- Create: `Sources/OpenSimBridge/Physical/CoreDeviceProcessRunning.swift`
- Create: `Sources/OpenSimBridge/Physical/DevicectlClient.swift`
- Create: `Sources/OpenSimBridge/Physical/DevicectlJSON.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalDeviceService.swift`
- Test: `Tests/OpenSimBridgeTests/Physical/DevicectlClientTests.swift`
- Test: `Tests/OpenSimBridgeTests/Physical/PhysicalDeviceServiceTests.swift`

**Interfaces:**
- Consumes: `CoreDeviceManifest`, `PhysicalDeviceID`, `OpenSimError`.
- Produces: `CoreDeviceProcessOutput`, `CoreDeviceProcessRunning`, `FoundationCoreDeviceProcessRunner`, `DevicectlClient`, `PhysicalDeviceListing`, `PhysicalDeviceRecord`, `PhysicalDeviceService`, `PhysicalDeviceCache`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

actor RecordingProcessRunner: CoreDeviceProcessRunning {
    private var outputs: [CoreDeviceProcessOutput]
    private(set) var calls: [(executable: String, arguments: [String], environment: [String: String])] = []
    init(outputs: [CoreDeviceProcessOutput]) { self.outputs = outputs }
    func run(executable: String, arguments: [String], environment: [String: String], timeout: Duration) async throws -> CoreDeviceProcessOutput {
        calls.append((executable, arguments, environment))
        guard !outputs.isEmpty else { throw OpenSimError(code: .internalError, message: "no stub") }
        return outputs.removeFirst()
    }
}

final class DevicectlClientTests: XCTestCase {
    func testListUsesXcrunAndSanitizedEnvironment() async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CoreDevice/devicectl-list-devices.json")
        let runner = RecordingProcessRunner(outputs: [
            CoreDeviceProcessOutput(status: 0, stdout: try Data(contentsOf: fixture), stderr: Data())
        ])
        let client = DevicectlClient(runner: runner, manifest: .testManifest)
        let devices = try await client.listDevices()
        XCTAssertEqual(devices.first?.udid, "00008030-001A2D3E0E8A802E")
        let calls = await runner.calls
        XCTAssertEqual(calls[0].executable, "/usr/bin/xcrun")
        XCTAssertEqual(calls[0].arguments, ["devicectl", "list", "devices", "--json-output", "-"])
        XCTAssertEqual(calls[0].environment["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertNil(calls[0].environment["SSH_AUTH_SOCK"])
    }
}
```

- [ ] **Step 2: Chạy fail**

`swift test --filter DevicectlClientTests`. Expected: FAIL.

- [ ] **Step 3: Implement runner và client**

`CoreDeviceProcessRunning` có method `run(executable:arguments:environment:timeout:)`. `FoundationCoreDeviceProcessRunner` dùng `Process`, `Pipe`, `FileHandle.nullDevice`, poll 50 ms, `terminate()` khi timeout, cap stdout/stderr 8 MiB, trả `CoreDeviceProcessOutput`. `DevicectlClient` luôn gọi `manifest.devicectlPath` với `["devicectl"] + arguments`, env chỉ `PATH`, `HOME`, `TMPDIR`, và `DEVELOPER_DIR` nếu có. Status khác 0 map `trust`, `developer mode`, `locked` sang lỗi tương ứng, còn lại `PhysicalError.devicectlFailed`.

`listDevices()` gọi `["list", "devices", "--json-output", "-"]`, parse bằng `DevicectlJSON.value(at: manifest.deviceListPath, in: root)`, đọc đúng `keyMap`, bỏ entry UDID không hợp lệ. Không hardcode key. Normalize value theo report: transport `usb|wired` thành `.usb`, `network|wifi` thành `.network`; pairing `paired|trusted` thành `.paired`, còn lại `.unknown`; developer mode `enabled|disabled` thành enum tương ứng.

- [ ] **Step 4: Implement device service**

`PhysicalDeviceCache` actor giữ `records`, `fetchedAt`, TTL 2 giây, single-flight bằng `Task`. `PhysicalDeviceService` conforms `DeviceControlling`: `listDevices()` map `PhysicalDeviceStatus.device`; `device(_ id: DeviceID)` parse prefix rồi gọi `status`; `.status(id: PhysicalDeviceID, refresh:)` trả `device_not_found` với recovery nếu không có; `.allStatuses(refresh:)`; `.invalidate()`; `createDevice`, `cloneDevice`, `boot`, `shutdown`, `erase`, `delete`, `rename`, `pair(watch:phone:)` throw `PhysicalError.simulatorOnly`. Capability set lấy từ manifest gates; `accessibility` và `recording` luôn `.unavailable`; pairing chưa paired hoặc DDI thiếu thì install/launch/terminate/container `.unavailable`.

- [ ] **Step 5: Chạy pass và commit**

`swift test --filter DevicectlClientTests` và `swift test --filter PhysicalDeviceServiceTests` pass; cache gọi lister một lần trong TTL, refresh gọi lại.

```bash
git add Sources/OpenSimBridge/Physical/CoreDeviceProcessRunning.swift Sources/OpenSimBridge/Physical/DevicectlClient.swift Sources/OpenSimBridge/Physical/DevicectlJSON.swift Sources/OpenSimBridge/Physical/PhysicalDeviceService.swift Tests/OpenSimBridgeTests/Physical
git commit -m "feat(physical): add devicectl client and device cache"
```

---

### Task 4: Pairing, trust và signing preflight

**Files:**
- Create: `Sources/OpenSimBridge/Physical/PhysicalPairingService.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalSigningInspector.swift`
- Test: `Tests/OpenSimBridgeTests/Physical/PhysicalPairingTests.swift`
- Test: `Tests/OpenSimBridgeTests/Physical/PhysicalSigningInspectorTests.swift`

**Interfaces:**
- Consumes: `DevicectlClient`, `PhysicalDeviceService`, `PathPolicy`, `IdentifierValidation`.
- Produces: `PhysicalPairingService.pair(device:timeout:)`, `.unpair(device:)`; `PhysicalSigningInspecting`, `PhysicalSigningReport`, `PhysicalSigningCheck`, `FoundationSigningCommandRunner`, `PhysicalSigningInspector`.

- [ ] **Step 1: Viết test pairing thất bại**

```swift
func testPairWaitsForTrustWithoutAutoAccept() async throws {
    let lister = StubDeviceLister(responses: [[.testRecord(.unpaired)], [.testRecord(.paired)]])
    let devices = PhysicalDeviceService(lister: lister, cacheTTL: .zero, manifest: .testManifest)
    let service = PhysicalPairingService(
        client: DevicectlClient(runner: RecordingProcessRunner(outputs: [
            CoreDeviceProcessOutput(status: 0, stdout: Data(), stderr: Data())
        ]), manifest: .testManifest),
        devices: devices,
        sleep: { _ in }
    )
    let status = try await service.pair(device: .testID, timeout: .seconds(10))
    XCTAssertEqual(status.pairing, .paired)
}
```

Thêm test Developer Mode disabled trả `permission_denied` reason `developer_mode_disabled`, và trust timeout trả `trust_required` sau khi poll, không đổi trạng thái.

- [ ] **Step 2: Chạy fail**

`swift test --filter PhysicalPairingTests`. Expected: FAIL.

- [ ] **Step 3: Implement pairing**

`pair` chỉ chạy khi manifest gate `pair` true; nếu không throw `capability_unavailable("physical_pair")`. Nó đọc status refresh, chặn Developer Mode disabled, trả luôn nếu đã paired, chạy `["manage", "pair", "--device", udid]` với timeout, poll mỗi 500 ms đến deadline; paired thì trả, trustDenied thì throw trust, hết giờ throw trust. Không tự bấm Trust, không retry sau timeout. `unpair` chỉ chạy khi gate `pair` true, chạy `["manage", "unpair", "--device", udid]` rồi `devices.invalidate()`.

- [ ] **Step 4: Viết test signing thất bại**

Fixture profile plist có `ProvisionedDevices`, `ExpirationDate`, `TeamIdentifier`, `Entitlements`. Test valid pass; expired fail check `profileExpiry`; wrong UDID fail check `provisionedDevice`; `isInstallable == false`. `FakeSigningRunner` trả XML entitlements và metadata, không dùng certificate thật.

- [ ] **Step 5: Implement signing**

`PhysicalSigningInspector.inspect(appPath:targetUDID:)`:

1. `PathPolicy.validateAppBundle(appPath)`.
2. `codesign --verify --deep --strict --verbose=2`.
3. `codesign -d --entitlements :-`; parse plist.
4. `codesign -dv --verbose=4`; lấy `TeamIdentifier`, `Authority`.
5. Đọc `embedded.mobileprovision` ở root app bundle; `security cms -D -i`; parse plist.
6. Check bundle ID khớp `Info.plist`, profile chưa hết hạn, `ProvisionedDevices` chứa UDID hoặc `ProvisionsAllDevices`, `application-identifier` khớp team + bundle ID.
7. Trả `PhysicalSigningReport` gồm checks, expiry, số device, `targetUDIDIncluded`; không log certificate, profile hay team secret.

`FoundationSigningCommandRunner` dùng `Process` với `/usr/bin/codesign`, `/usr/bin/security`, env sanitize như `DevicectlClient`. Không chạy `codesign --sign`, không cài profile, không mở keychain.

- [ ] **Step 6: Chạy pass và commit**

`swift test --filter PhysicalPairingTests` và `swift test --filter PhysicalSigningInspectorTests` pass.

```bash
git add Sources/OpenSimBridge/Physical/PhysicalPairingService.swift Sources/OpenSimBridge/Physical/PhysicalSigningInspector.swift Tests/OpenSimBridgeTests/Physical
git commit -m "feat(physical): add pairing and signing preflight"
```

---

### Task 5: App lifecycle và container

**Files:**
- Create: `Sources/OpenSimBridge/Physical/PhysicalAppService.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalContainerService.swift`
- Test: `Tests/OpenSimBridgeTests/Physical/PhysicalAppServiceTests.swift`

**Interfaces:**
- Consumes: `AppControlling`, `AppInfo`, `ContainerKind`, `PhysicalSigningInspecting`, `DevicectlClient`, `PhysicalDeviceService`.
- Produces: `PhysicalAppService`, `PhysicalContainerService`, `PhysicalLaunchRegistry`.

- [ ] **Step 1: Viết test thất bại**

```swift
func testInstallRunsPreflightThenDevicectl() async throws {
    let runner = RecordingProcessRunner(outputs: [
        CoreDeviceProcessOutput(status: 0, stdout: Data(), stderr: Data())
    ])
    let service = PhysicalAppService(
        client: DevicectlClient(runner: runner, manifest: .testManifest),
        signing: FakeSigning(installable: true),
        devices: PhysicalDeviceService(lister: StubDeviceLister(responses: []),
                                       cacheTTL: .zero, manifest: .testManifest),
        manifest: .testManifest
    )
    let app = try makeTestApp()
    _ = try await service.installApp(on: .testID.deviceID, at: app)
    let calls = await runner.calls
    XCTAssertEqual(calls[0].arguments, [
        "devicectl", "device", "install", "app", "--device", PhysicalDeviceID.testID.udid,
        app
    ])
}

func testUnsignedAppNeverRunsDevicectl() async throws {
    let runner = RecordingProcessRunner(outputs: [])
    let service = PhysicalAppService(
        client: DevicectlClient(runner: runner, manifest: .testManifest),
        signing: FakeSigning(installable: false),
        devices: PhysicalDeviceService(lister: StubDeviceLister(responses: []),
                                       cacheTTL: .zero, manifest: .testManifest),
        manifest: .testManifest
    )
    do {
        _ = try await service.installApp(on: .testID.deviceID, at: try makeTestApp())
        XCTFail("expected invalid_argument")
    } catch let error as OpenSimError {
        XCTAssertEqual(error.code, "invalid_argument")
        XCTAssertEqual(error.details["reason"], "signing_invalid")
    }
    let calls = await runner.calls
    XCTAssertTrue(calls.isEmpty)
}
```

`makeTestApp()` tạo `.app` tạm có `Info.plist` với `CFBundleIdentifier`, `CFBundleDisplayName`, version, build. `FakeSigning` trả `PhysicalSigningReport` với `isInstallable` theo tham số.

- [ ] **Step 2: Chạy fail**

`swift test --filter PhysicalAppServiceTests`. Expected: FAIL.

- [ ] **Step 3: Implement app service**

```swift
public struct PhysicalAppService: AppControlling {
    public func installApp(on device: DeviceID, at path: String) async throws -> AppInfo {
        try PathPolicy.validateAppBundle(path)
        let id = try requirePhysical(device)
        let report = try await signing.inspect(appPath: path, targetUDID: id.udid)
        guard report.isInstallable else {
            throw PhysicalError.invalidSignature("signing_invalid",
                message: "App is not signed for this device")
        }
        _ = try await client.run(
            ["device", "install", "app", "--device", id.udid, path],
            timeout: .seconds(120)
        )
        return try appInfoFromBundle(path)
    }

    public func launchApp(on device: DeviceID, bundleID: String, args: [String],
                          environment: [String: String]) async throws -> Int32 {
        let id = try requirePhysical(device)
        try IdentifierValidation.validateBundleID(bundleID)
        if !environment.isEmpty {
            throw OpenSimError.invalidArgument(
                "Physical launch does not accept environment variables in this build",
                details: ["reason": "environment_unsupported"])
        }
        var command = ["device", "process", "launch", "--device", id.udid]
        if manifest.gate("launchJSON") {
            command += ["--json-output", "-"]
        }
        command.append(bundleID)
        command += args
        let output = try await client.run(command, timeout: .seconds(60))
        await launchRegistry.record(bundleID, on: id)
        return manifest.gate("launchJSON") ? (Self.pid(from: output.stdout) ?? 0) : 0
    }

    public func terminateApp(on device: DeviceID, bundleID: String) async throws {
        let id = try requirePhysical(device)
        try IdentifierValidation.validateBundleID(bundleID)
        _ = try await client.run(
            ["device", "process", "terminate", "--device", id.udid, bundleID],
            timeout: .seconds(30)
        )
    }
}
```

`PhysicalAppService(client:signing:devices:container:launchRegistry:manifest:)` giữ manifest; nếu gate `install`/`launch`/`terminate` false, throw `capability_unavailable` trước khi gọi `devicectl` (mode readOnly). `requirePhysical(_:)` parse `PhysicalDeviceID(deviceID:)` hoặc throw `invalid_argument` reason `not_physical`; `pid(from:)` chỉ đọc JSON. `PhysicalAppService.containerPath` delegate sang `PhysicalContainerService`. `PhysicalLaunchRegistry` là actor giữ `[PhysicalDeviceID: String]` cho bundle ID vừa launch, dùng cho log console và audit note. `listApps` chỉ chạy khi manifest gate `appList`; parse `device info apps` theo `keyMap`. `appInfo` dùng list nếu có gate, nếu không trả `capability_unavailable("physical_app_info")`. `uninstallApp` chạy `device uninstall app --device <udid> <bundleID>` nhưng chỉ khi gate `install`; dispatcher đã kiểm tra confirm destructive. `pid(from:)` tìm `"pid"` trong JSON đã xác minh; không có thì trả `0` và ghi note `pid=unknown`, không đoán.

- [ ] **Step 4: Implement container service**

`PhysicalContainerService` map `ContainerKind` sang domain lấy từ manifest `keyMap["containerDomain.app|data|group"]`. Nếu domain chưa có, throw `capability_unavailable("physical_container")`. Chạy:

```swift
["device", "info", "files", "--device", id.udid,
 "--domain-type", domain, "--domain-identifier", bundleID, "--json-output", "-"]
```

Parse `keyMap["containerPath"]`; path phải bắt đầu `/private/var/` hoặc `/var/` và không chứa `..`; trả path thiết bị, không mở path host. `AppInfo.dataContainer`/`appContainer` cho physical để `nil` vì đây là path thiết bị, không phải host.

- [ ] **Step 5: Chạy pass và commit**

`swift test --filter PhysicalAppServiceTests` pass 2 test; test container args pass.

```bash
git add Sources/OpenSimBridge/Physical/PhysicalAppService.swift Sources/OpenSimBridge/Physical/PhysicalContainerService.swift Tests/OpenSimBridgeTests/Physical/PhysicalAppServiceTests.swift
git commit -m "feat(physical): add app lifecycle and container adapters"
```

---

### Task 6: Screenshot, input và log qua recipe

**Files:**
- Create: `Sources/OpenSimBridge/Physical/CoreDeviceRecipeRunner.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalScreenService.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalInputService.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalLogService.swift`
- Test: `Tests/OpenSimBridgeTests/Physical/PhysicalScreenAndInputTests.swift`
- Test: `Tests/OpenSimBridgeTests/Physical/PhysicalLogServiceTests.swift`

**Interfaces:**
- Consumes: `ScreenControlling`, `InputControlling`, `LogControlling`, `Screenshot`, `ScreenInfo`, `Point`, `Key`, `KeyModifiers`, `HardwareButton`, `LogPage`, `LogEntry`, `CoreDeviceCommandRecipe`.
- Produces: `PhysicalScreenshotTransport`, `RecipeScreenshotTransport`, `PhysicalInputTransport`, `PhysicalInputEvent`, `RecipeInputTransport`, `PhysicalLogTransport`, `RecipeLogTransport`, ba service.

- [ ] **Step 1: Viết test thất bại**

```swift
struct FakeScreenshotTransport: PhysicalScreenshotTransport {
    var result: Screenshot
    func capture(device: PhysicalDeviceID) async throws -> Screenshot { result }
}

actor FakeInputTransport: PhysicalInputTransport {
    private(set) var events: [PhysicalInputEvent] = []
    func send(_ event: PhysicalInputEvent) async throws { events.append(event) }
}

func testScreenshotAndTap() async throws {
    let shot = Screenshot(path: "/tmp/p.png", data: Data([0x89, 0x50]),
                          format: .png, width: 1179, height: 2556,
                          scale: 3, capturedAt: Date())
    let screen = PhysicalScreenService(transport: FakeScreenshotTransport(result: shot))
    let captured = try await screen.screenshot(on: .testID.deviceID, format: .png,
                                               scale: 1, quality: nil)
    XCTAssertEqual(captured.width, 1179)

    let input = FakeInputTransport()
    let service = PhysicalInputService(transport: input)
    try await service.tap(on: .testID.deviceID, at: Point(x: 10, y: 20), settle: false)
    let events = await input.events
    XCTAssertEqual(events, [.tap(Point(x: 10, y: 20))])
}

func testNoRecipeIsCapabilityUnavailable() async {
    do {
        _ = try await PhysicalScreenService(transport: nil)
            .screenshot(on: .testID.deviceID, format: .png, scale: 1, quality: nil)
        XCTFail("expected capability_unavailable")
    } catch let error as OpenSimError {
        XCTAssertEqual(error.code, "capability_unavailable")
    }
}
```

- [ ] **Step 2: Chạy fail**

`swift test --filter PhysicalScreenAndInputTests`. Expected: FAIL.

- [ ] **Step 3: Implement recipe runner**

```swift
public struct CoreDeviceRecipeRunner: Sendable {
    public static func expand(_ arguments: [String], values: [String: String]) throws -> [String] {
        let pattern = "\\$\\{([a-zA-Z0-9_]+)\\}"
        let regex = try NSRegularExpression(pattern: pattern)
        return try arguments.map { argument in
            let range = NSRange(argument.startIndex..<argument.endIndex, in: argument)
            var result = argument
            for match in regex.matches(in: argument, range: range).reversed() {
                guard let keyRange = Range(match.range(at: 1), in: argument),
                      let value = values[String(argument[keyRange])] else {
                    throw OpenSimError.invalidArgument("Missing recipe value for \(argument)")
                }
                guard value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                    throw OpenSimError.invalidArgument("Recipe value contains control characters")
                }
                if let full = Range(match.range, in: result) {
                    result.replaceSubrange(full, with: value)
                }
            }
            return result
        }
    }

    public func run(_ recipe: CoreDeviceCommandRecipe, values: [String: String]) async throws -> CoreDeviceProcessOutput {
        try await client.run(Self.expand(recipe.arguments, values: values),
                             timeout: .seconds(recipe.timeoutSeconds))
    }
}
```

`RecipeScreenshotTransport` tạo thư mục `~/Library/Caches/OpenSim/physical/<udid>/` quyền `0700`, file output `0600`, chạy recipe `screenshot` với `${udid}`, `${out}`, đọc PNG, lấy width/height từ `CGImageSource`, trả `Screenshot`. Nếu recipe không có, factory trả `nil`.

- [ ] **Step 4: Implement screen và input**

`PhysicalScreenService.screens` trả `capability_unavailable("physical_screen_info")` vì chưa xác minh display metadata. `screenshot` kiểm tra prefix, transport nil thì `capability_unavailable("physical_screenshot")`, ngược lại delegate; nếu caller xin `.jpeg` mà transport trả PNG, convert bằng ImageIO với quality request, và trả width/height/scale thật của ảnh. `startRecording`/`stopRecording` trả `capability_unavailable("physical_recording")`.

`PhysicalInputEvent` là enum `Sendable, Equatable` với các case tap, swipe, longPress, drag, pinch, rotate, scroll, text, key, button. `PhysicalInputService` kiểm tra `Point` hữu hạn, duration từ 0 đến 10000 ms, text tối đa 10.000 ký tự, rồi map sang event. Tọa độ là point của thiết bị; nếu Task 1 xác định recipe dùng pixel, thêm `inputScale` vào manifest và nhân trước khi gửi. Transport nil: mọi method throw `input_failed` details `reason=physical_hid_unavailable`. Recipe thiếu cho một gesture: throw `input_failed` details `reason=unsupported_gesture`, `gesture=<name>`.

- [ ] **Step 5: Implement log**

`RecipeLogTransport` chạy recipe `log` với `${udid}`, timeout theo recipe, parse dòng `timestamp level subsystem category process message`; dòng sai format dùng level `.info` và toàn dòng làm message. Cursor là base64 của `"<generation>:<index>"`; cursor hỏng trả `invalid_argument`. Filter là substring case-insensitive, áp dụng sau parse. `PhysicalLogService` kiểm tra prefix, limit từ 1 đến 1000, transport nil trả `capability_unavailable("physical_log", reason: "recipe_not_verified")`, nếu không delegate. Không ghi nội dung log vào audit.

- [ ] **Step 6: Chạy pass và commit**

`swift test --filter PhysicalScreenAndInputTests` pass 4 test; `swift test --filter PhysicalLogServiceTests` pass 2 test.

```bash
git add Sources/OpenSimBridge/Physical/CoreDeviceRecipeRunner.swift Sources/OpenSimBridge/Physical/PhysicalScreenService.swift Sources/OpenSimBridge/Physical/PhysicalInputService.swift Sources/OpenSimBridge/Physical/PhysicalLogService.swift Tests/OpenSimBridgeTests/Physical
git commit -m "feat(physical): add screenshot input and log recipe adapters"
```

---

### Task 7: Composite bridge và presentation

**Files:**
- Create: `Sources/OpenSimBridge/Physical/PhysicalRuntimeService.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalAccessibilityService.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalBridge.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalAdminService.swift`
- Create: `Sources/OpenSimBridge/Physical/CompositeSimulatorBridge.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalPresentation.swift`
- Test: `Tests/OpenSimBridgeTests/Physical/CompositeBridgeTests.swift`
- Test: `Tests/OpenSimBridgeTests/Physical/PhysicalPresentationTests.swift`

**Interfaces:**
- Consumes: `SimulatorBridge`, `BridgeCapabilities`, `Capability`, tất cả service protocol.
- Produces: `PhysicalBridge`, `PhysicalBridgeFactory`, `PhysicalAdminService`, `CompositeSimulatorBridge`, `PhysicalOperationExecuting`, `PhysicalPresentation`.

- [ ] **Step 1: Viết test thất bại**

```swift
func testListsBothSourcesAndRejectsBootOnPhysical() async throws {
    let simulator = StubSimulatorBridge(devices: [.testDevice(.simulatorID, "iPhone Air")])
    let physical = StubPhysicalDevices(devices: [.testDevice(.testID.deviceID, "Test iPhone")])
    let bridge = CompositeSimulatorBridge(simulator: simulator,
        physicalDevices: physical, physicalApps: nil, physicalLogs: nil,
        physicalScreen: nil, physicalInput: nil)
    let devices = try await bridge.devices.listDevices()
    XCTAssertEqual(Set(devices.map(\.id)), Set([.simulatorID, .testID.deviceID]))
    do {
        _ = try await bridge.devices.boot(.testID.deviceID, wait: false)
        XCTFail("expected capability_unavailable")
    } catch let error as OpenSimError {
        XCTAssertEqual(error.code, "capability_unavailable")
        XCTAssertEqual(error.details["reason"], "simulator_only")
    }
}
```

- [ ] **Step 2: Chạy fail**

`swift test --filter CompositeBridgeTests`. Expected: FAIL.

- [ ] **Step 3: Implement**

`PhysicalRuntimeService` trả `capability_unavailable("physical_runtime")`; `PhysicalAccessibilityService` trả `a11y_unavailable` cho `tree`/`find`. `StubSimulatorBridge` và `StubPhysicalDevices` được định nghĩa trong `CompositeBridgeTests.swift`: chỉ trả list device, các method còn lại throw `OpenSimError(code: .capabilityUnavailable, message: "stub")`. `PhysicalBridge` gom `devices`, `apps`, `logs`, `screen`, `input`, `accessibility`, `runtimes`, `public let manifest`, `lastError`, `allStatuses(refresh:)` delegate sang `PhysicalDeviceService`, và tính `BridgeCapabilities`: `render`/`video`/`watch`/`tv` luôn `.unavailable`; `screenshot`/`hid` theo manifest; `accessibility` `.unavailable`.

`PhysicalAdminService` dùng `PhysicalPairingService` cho pair/unpair, `PhysicalDeviceService` cho status, và `PhysicalSigningInspector` + `PhysicalDeviceService` cho check-signing; nó encode kết quả bằng `OpenSimJSON`. `PhysicalBridgeFactory.makeDefault()` đọc manifest bundled; nếu mode `.deferred` hoặc `gate.list` false trả `nil`; nếu không dựng `DevicectlClient`, `PhysicalDeviceService`, `PhysicalPairingService`, `PhysicalAppService`, `PhysicalContainerService`, `PhysicalLogService`, `PhysicalScreenService`, `PhysicalInputService`, `PhysicalAdminService`, `PhysicalBridge`.

`CompositeSimulatorBridge` có hai init: `(simulator:physical:)` cho daemon và init nhiều optional service cho test. Route bằng `PhysicalDeviceID.isPhysicalReference(id.rawValue)`. `listDevices` gộp và sort theo name; nếu physical list throw, trả simulator list và ghi lỗi physical vào `PhysicalBridge.lastError` (một actor hoặc lock bảo vệ) để doctor/UI hiển thị, không làm hỏng `device list` simulator. `boot/shutdown/create/clone/erase/delete/rename/pair(watch:phone:)` trên physical throw `PhysicalError.simulatorOnly`. `apps/logs/screen/input` route; physical service nil thì throw `capability_unavailable`. `accessibility` physical throw `a11y_unavailable`. `PhysicalOperationExecuting.executePhysical` chuyển bốn operation physical sang `PhysicalAdminService`; nếu bridge physical nil throw `capability_unavailable`.

`PhysicalPresentation.badge(transport:)` trả `Physical · USB`, `Physical · Network`, `Physical`; `unsupportedReasons(_:)` map `unsupportedFeatures` sang cặp `(feature, reason)`. Không dùng màu làm tín hiệu duy nhất; badge có text và accessibility label.

- [ ] **Step 4: Chạy pass và commit**

`swift test --filter CompositeBridgeTests` pass 2 test; `swift test --filter PhysicalPresentationTests` pass 2 test.

```bash
git add Sources/OpenSimBridge/Physical Tests/OpenSimBridgeTests/Physical
git commit -m "feat(physical): add composite bridge and presentation"
```

---

### Task 8: Catalog, daemon wiring và audit

**Files:**
- Create: `Sources/OpenSimCore/Catalog/PhysicalOperations.swift`
- Create: `Sources/OpenSimCore/Catalog/OpenSimCatalog.swift`
- Create: `Sources/OpenSimBridge/Physical/PhysicalAuditPolicy.swift`
- Modify: `Sources/OpenSimCore/Validation/DeviceResolver.swift`
- Modify: `Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift`
- Modify: `Sources/OpenSimDaemon/Runtime/DaemonRunner.swift`
- Modify: `Sources/OpenSimDaemon/Operations/OperationDispatcher.swift`
- Modify: `Sources/OpenSimDaemon/Server/DaemonServer.swift`
- Test: `Tests/OpenSimCoreTests/PhysicalOperationsTests.swift`
- Test: `Tests/OpenSimDaemonTests/PhysicalRoutingTests.swift`

**Interfaces:**
- Consumes: `Operation`, `OperationCatalog`, `OperationRequest`, `OperationDispatcher.serviceHandlers`, `AuditWriter`.
- Produces: `OperationCatalog.registerPhysicalOperations()`, `OperationCatalog.openSim()`, `PhysicalAuditPolicy.action(operation:target:)`.

- [ ] **Step 1: Viết test thất bại**

```swift
func testPhysicalMetadata() throws {
    let catalog = OperationCatalog.openSim()
    let pair = try XCTUnwrap(catalog.operation(forMCP: "physical_pair"))
    XCTAssertEqual(pair.cliPath, ["physical", "pair"])
    XCTAssertTrue(pair.requiresControlLease)
    XCTAssertFalse(pair.destructive)
    let unpair = try XCTUnwrap(catalog.operation(forMCP: "physical_unpair"))
    XCTAssertTrue(unpair.destructive)
    let status = try XCTUnwrap(catalog.operation(forMCP: "physical_status"))
    XCTAssertTrue(status.readOnly)
    XCTAssertFalse(status.requiresControlLease)
    XCTAssertNotNil(catalog.operation(forMCP: "app_install"))
}

func testAuditActionUsesPhysicalNamespace() {
    XCTAssertEqual(PhysicalAuditPolicy.action(operation: "app_install",
        target: "physical:00008030-001A2D3E0E8A802E"), "physical.install")
    XCTAssertEqual(PhysicalAuditPolicy.action(operation: "ui_tap",
        target: "physical:00008030-001A2D3E0E8A802E"), "physical.input")
    XCTAssertEqual(PhysicalAuditPolicy.action(operation: "app_install",
        target: "95B3747B-7065-447E-AB1E-53065142C3FC"), "app_install")
}
```

- [ ] **Step 2: Chạy fail**

`swift test --filter PhysicalOperationsTests`; `swift test --filter PhysicalRoutingTests`. Expected: FAIL.

- [ ] **Step 3: Implement catalog**

`registerPhysicalOperations()` đăng ký bốn operation:

| CLI | MCP | Lease | Destructive | Read-only | Parameters |
|---|---|---|---|---|---|
| `physical pair` | `physical_pair` | Có | Không | Không | `device`, `timeoutSeconds?` |
| `physical unpair` | `physical_unpair` | Có | Có | Không | `device` |
| `physical status` | `physical_status` | Không | Không | Có | `device` |
| `physical check-signing` | `physical_check_signing` | Không | Không | Có | `path`, `device?`, `udid?` |

`OpenSimCatalog.swift`:

```swift
public extension OperationCatalog {
    static func openSim() -> OperationCatalog {
        var catalog = OperationCatalog.plan3()
        catalog.registerUIOperations()
        catalog.registerStoragePerformanceOperations()
        catalog.registerPhysicalOperations()
        return catalog
    }
}
```

- [ ] **Step 4: Implement executor và daemon**

Trong `Sources/OpenSimCore/Validation/DeviceResolver.swift`, sau bước xử lý query rỗng và trước UUID regex, thêm exact-ID branch:

```swift
if let exact = devices.first(where: { $0.id.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }) {
    return exact
}
```

Nhánh này làm `physical:<udid>` hoạt động ở mọi call site hiện có: `BridgeOperationExecutor`, `OperationDispatcher`, `DaemonCommandBackend`, `MCPToolSession`. Không đổi signature hay kiểu trả về.

Trong `execute`, trước `default`, route bốn operation physical qua `PhysicalOperationExecuting`. Trong `DaemonRunner`, dựng:

```swift
let simulator = try SimctlBridge.live(timeout: .seconds(30))
let physical = PhysicalBridgeFactory.makeDefault()
let bridge = CompositeSimulatorBridge(simulator: simulator, physical: physical)
let catalog = OperationCatalog.openSim()
```

`DaemonServer` và MCP HTTP dùng `OperationCatalog.openSim()`. `OperationDispatcher` nhận `serviceHandlers` cho bốn physical operation và dùng `PhysicalAuditPolicy.action` khi ghi audit. `target` lấy `deviceID?.rawValue ?? request.parameters["device"] ?? operation.mcpName`.

- [ ] **Step 5: Implement audit policy**

```swift
public enum PhysicalAuditPolicy {
    public static func action(operation: String, target: String) -> String {
        guard target.hasPrefix(PhysicalDeviceID.prefix) else { return operation }
        switch operation {
        case "app_install": return "physical.install"
        case "app_launch": return "physical.launch"
        case "app_terminate": return "physical.terminate"
        case "app_container": return "physical.container"
        case "screen_screenshot": return "physical.screenshot"
        case "log_tail": return "physical.log"
        case "ui_tap", "ui_swipe", "ui_long_press", "ui_drag", "ui_pinch",
             "ui_rotate", "ui_scroll", "ui_type", "ui_key", "ui_button":
            return "physical.input"
        case "physical_pair": return "physical.pair"
        case "physical_unpair": return "physical.unpair"
        case "physical_status": return "physical.status"
        case "physical_check_signing": return "physical.check_signing"
        default: return "physical." + operation
        }
    }
}
```

- [ ] **Step 6: Chạy pass và commit**

`swift test --filter PhysicalOperationsTests`; `swift test --filter PhysicalRoutingTests`; `swift build --product opensim` pass.

```bash
git add Sources/OpenSimCore/Catalog/PhysicalOperations.swift Sources/OpenSimCore/Catalog/OpenSimCatalog.swift Sources/OpenSimCore/Validation/DeviceResolver.swift Sources/OpenSimBridge/Physical/PhysicalAuditPolicy.swift Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift Sources/OpenSimDaemon Tests
git commit -m "feat(physical): wire catalog daemon and audit"
```

---

### Task 9: CLI physical và MCP tools

**Files:**
- Create: `Sources/OpenSimCLI/Commands/PhysicalCommand.swift`
- Modify: `Sources/OpenSimCLI/Commands/DeviceCommands.swift`
- Modify: `Sources/OpenSimCLI/Commands/OpenSimCommand.swift`
- Modify: `Sources/OpenSimCLI/Commands/OpenSimCommandCatalog.swift`
- Modify: `Sources/OpenSimCLI/Commands/MCPCommand.swift`
- Modify: `Sources/OpenSimCLI/Commands/DoctorCommand.swift`
- Create: `Sources/OpenSimMCP/Tools/PhysicalToolPresenter.swift`
- Modify: `Sources/OpenSimMCP/Server/MCPHandler.swift`
- Test: `Tests/OpenSimCLITests/PhysicalCommandTests.swift`
- Test: `Tests/OpenSimMCPTests/PhysicalToolTests.swift`

**Interfaces:**
- Consumes: `CommandBackend`, `CLIRuntime.makeBackend`, `OperationCatalog.openSim()`, `PhysicalDeviceStatus`, `PhysicalSigningReport`, `ToolCatalogAdapter`.
- Produces: `PhysicalCommand` và bốn subcommand; doctor block `physical`; `PhysicalToolPresenter.present(tool:result:)`.

- [ ] **Step 1: Viết test CLI thất bại**

```swift
final class PhysicalCommandTests: XCTestCase {
    func testRootAddsPhysicalWithoutRemovingExistingGroups() {
        let names = Set(OpenSimCommand.configuration.subcommands.map { $0.configuration.commandName })
        XCTAssertTrue(names.contains("physical"))
        XCTAssertTrue(names.isSuperset(of: [
            "device", "runtime", "app", "log", "doctor", "daemon", "session", "mcp"
        ]))
    }

    func testParsesStatusAndUnpair() throws {
        let status = try OpenSimCommand.parseAsRoot([
            "physical", "status", "physical:00008030-001A2D3E0E8A802E", "--json"
        ])
        let statusCommand = try XCTUnwrap(status as? PhysicalStatusCommand)
        XCTAssertEqual(statusCommand.device, "physical:00008030-001A2D3E0E8A802E")
        let unpair = try OpenSimCommand.parseAsRoot([
            "physical", "unpair", "physical:00008030-001A2D3E0E8A802E", "--yes"
        ])
        let unpairCommand = try XCTUnwrap(unpair as? PhysicalUnpairCommand)
        XCTAssertTrue(unpairCommand.yes)
    }
}
```

- [ ] **Step 2: Chạy fail**

`swift test --filter PhysicalCommandTests`. Expected: FAIL vì nhóm `physical` chưa có.

- [ ] **Step 3: Implement CLI**

`PhysicalCommand` root với subcommands `PhysicalPairCommand`, `PhysicalUnpairCommand`, `PhysicalStatusCommand`, `PhysicalCheckSigningCommand`. Mỗi command dùng `CLIRuntime.run(globals:table:body:)` và gọi operation qua `CommandBackend`:

```swift
struct PhysicalStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status")
    @OptionGroup var globals: GlobalOptions
    @Argument var device: String

    func run() async throws {
        _ = try await CLIRuntime.run(globals: globals, table: { status in
            Table(
                headers: ["UDID", "NAME", "TRANSPORT", "PAIRING", "SCREENSHOT", "INPUT"],
                rows: [[
                    status.id.rawValue, status.name, status.transport.rawValue,
                    status.pairing.rawValue, status.capabilities.screenshot.rawValue,
                    status.capabilities.input.rawValue
                ]]
            )
        }) { backend in
            try await backend.execute(
                "physical_status", parameters: ["device": device], as: PhysicalDeviceStatus.self)
        }
    }
}
```

`pair` thêm `--timeout` mặc định 120 và in hướng dẫn Trust trước khi gọi. `unpair` thiếu `--yes` và stdin không phải TTY thì throw `confirmation_required` trước khi gọi backend. `check-signing` nhận `path`, `--device` optional; nếu có device, backend lấy UDID từ status. Bảng human-readable có cột `UDID`, `NAME`, `TRANSPORT`, `PAIRING`, `SCREENSHOT`, `INPUT`; JSON giữ nguyên envelope.

`DeviceCommands.swift` thêm cột `SOURCE` suy ra từ prefix, không đổi JSON `Device`. `OpenSimCommand` thêm `PhysicalCommand.self`. `OpenSimCommandCatalog.make()` và `MCPCommand` dùng `OperationCatalog.openSim()`. `DoctorCommand` thêm:

```swift
let physical = PhysicalBridgeFactory.makeDefault()
let physicalStatuses = (try? await physical?.allStatuses(refresh: true)) ?? []
```

và block JSON:

```swift
"physical": [
    "available": physical != nil,
    "mode": physical?.manifest.mode.rawValue ?? "deferred",
    "devices": physicalStatuses.map(\.id.rawValue),
    "screenshot": physical?.manifest.capability("screenshot").rawValue ?? "unavailable",
    "input": physical?.manifest.capability("input").rawValue ?? "unavailable",
    "log": physical?.manifest.capability("log").rawValue ?? "unavailable"
]
```

Doctor chỉ đọc manifest/status, không pair, không install, không yêu cầu trust.

- [ ] **Step 4: Viết test MCP thất bại**

```swift
func testToolsListIncludesPhysicalTools() {
    let tools = ToolCatalogAdapter.tools(from: OperationCatalog.openSim())
    let names = Set(tools.map(\.name))
    XCTAssertTrue(names.isSuperset(of: [
        "physical_pair", "physical_unpair", "physical_status", "physical_check_signing"
    ]))
}

func testPresenterSummarizesStatus() {
    let result = JSONValue.object([
        "productType": .string("iPhone17,1"),
        "transport": .string("usb"),
        "pairing": .string("paired"),
        "capabilities": .object([
            "screenshot": .string("unavailable"),
            "input": .string("unavailable")
        ])
    ])
    let text = PhysicalToolPresenter.present(tool: "physical_status", result: result)
    XCTAssertTrue(text?.contains("iPhone17,1") == true)
    XCTAssertTrue(text?.contains("screenshot") == true)
    XCTAssertNil(PhysicalToolPresenter.present(tool: "device_list", result: .object([:])))
}
```

- [ ] **Step 5: Implement MCP presenter**

```swift
public enum PhysicalToolPresenter {
    public static func present(tool: String, result: JSONValue) -> String? {
        switch tool {
        case "physical_status":
            guard let object = result.objectValue else { return nil }
            let product = object["productType"]?.stringValue ?? "physical device"
            let transport = object["transport"]?.stringValue ?? "unknown"
            let pairing = object["pairing"]?.stringValue ?? "unknown"
            let capabilities = object["capabilities"]?.objectValue ?? [:]
            let unavailable = capabilities
                .filter { $0.value.stringValue == "unavailable" }
                .keys.sorted()
            return "Physical \(product) over \(transport); pairing \(pairing); unavailable: \(unavailable.joined(separator: ", "))"
        case "physical_pair":
            return "Pairing requested. Unlock the device, tap Trust, then call physical_status again."
        case "physical_unpair":
            return "Physical device unpaired."
        case "physical_check_signing":
            let installable = result.objectValue?["isInstallable"]?.boolValue ?? false
            return installable
                ? "App signature is installable on the target device."
                : "App signature is not installable; inspect the checks array."
        default:
            return nil
        }
    }
}
```

Trong `MCPHandler`, đổi `toolResult(value:error:)` thành `toolResult(tool:value:error:)`; khi thành công:

```swift
let contentText = value.flatMap {
    PhysicalToolPresenter.present(tool: tool, result: $0)
} ?? "ok"
```

Không thêm danh sách tool thứ hai; `physical_*` đến từ catalog. `physical_unpair` destructive nên adapter MCP tự yêu cầu `confirm: true`.

- [ ] **Step 6: Chạy pass và commit**

Cập nhật `MCPHandlerTests.testToolsListComesFromCatalog` để không hardcode số 25; assert set chứa tool cũ và bốn tool physical. Chạy `swift test --filter PhysicalCommandTests`, `PhysicalToolTests`, `ToolCatalogAdapterTests`, `MCPHandlerTests`; tất cả pass. `swift run opensim physical status physical:00008030-001A2D3E0E8A802E --json` trả envelope hoặc `device_not_found` có recovery, không crash.

```bash
git add Sources/OpenSimCLI Sources/OpenSimMCP Tests/OpenSimCLITests/PhysicalCommandTests.swift Tests/OpenSimMCPTests/PhysicalToolTests.swift
git commit -m "feat(cli): add physical commands and MCP tools"
```

---

### Task 10: App UI badge, trust và unsupported states

**Files:**
- Create: `App/Sources/OpenSimApp/Windows/PhysicalDeviceBadge.swift`
- Create: `App/Sources/OpenSimApp/Windows/PhysicalDeviceNotice.swift`
- Create: `App/Sources/OpenSimApp/Windows/PhysicalTrustBanner.swift`
- Create: `App/Sources/OpenSimApp/Windows/PhysicalSigningSheet.swift`
- Modify: `App/Sources/OpenSimApp/Windows/DeviceWindow.swift`
- Modify: `App/Sources/OpenSimApp/Windows/DeviceWindowToolbar.swift`
- Modify: `App/Sources/OpenSimApp/App/AppShell.swift`
- Modify: `App/Sources/OpenSimApp/App/DaemonClient.swift`
- Test: `Tests/OpenSimAppUITests/PhysicalDeviceUITests.swift`

**Interfaces:**
- Consumes: `PhysicalDeviceStatus`, `PhysicalPresentation`, `PhysicalPairingState`, `PhysicalSigningReport`, `Device`.
- Produces: badge/notice/trust/signing views; `DeviceWindow` không dùng `SimDisplayView` cho physical; toolbar disable đúng control.

- [ ] **Step 1: Viết UI test thất bại**

```swift
final class PhysicalDeviceUITests: XCTestCase {
    func testBadgeAndUnsupportedNotice() {
        let app = XCUIApplication()
        app.launchArguments = ["-OpenSimPhysicalFixture", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Physical · USB"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["screenshot"].exists)
        XCTAssertTrue(app.staticTexts["accessibility tree"].exists)
        XCTAssertFalse(app.buttons["Boot"].isEnabled)
        XCTAssertFalse(app.buttons["Record"].isEnabled)
    }
}
```

- [ ] **Step 2: Chạy fail**

```bash
xcodegen generate --spec App/project.yml
xcodebuild -project App/OpenSim.xcodeproj -scheme OpenSim -configuration Debug \
  -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test \
  -only-testing:OpenSimAppUITests/PhysicalDeviceUITests
```

Expected: FAIL vì view chưa có.

- [ ] **Step 3: Implement views**

`PhysicalDeviceBadge`:

```swift
struct PhysicalDeviceBadge: View {
    var transport: PhysicalTransport?
    var body: some View {
        let text = transport.map { PhysicalPresentation.badge(transport: $0) } ?? "Physical"
        Label(text, systemImage: "cable.connector")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel(text)
    }
}
```

`PhysicalDeviceNotice` hiển thị `status.capabilities.unsupportedFeatures` với text và lý do; khi screenshot unavailable dùng:

```swift
ContentUnavailableView(
    "Live view is simulator-only",
    systemImage: "iphone.slash",
    description: Text("Use `opensim ui screenshot` or open the device in Xcode Devices.")
)
```

`PhysicalTrustBanner` nhận `pairing`, `developerMode`, `refresh` closure. Pairing khác `.paired` hiện hướng dẫn unlock + Trust; Developer Mode `.disabled` hiện hướng dẫn Settings; nút `Check again` gọi `refresh`, không tự pair. `PhysicalSigningSheet` nhận `PhysicalSigningReport`, hiện bundle ID, team, expiry, số device, từng check, nút Cancel và Install; Install disabled khi `isInstallable == false`.

- [ ] **Step 4: Ghép vào cửa sổ**

`DeviceWindow` thêm `@State private var physicalStatus: PhysicalDeviceStatus?`, load qua `DaemonClient.physicalStatus(deviceID:)`, hiển thị `PhysicalTrustBanner` phía trên notice khi pairing khác `.paired`, và render:

```swift
if PhysicalDeviceID.isPhysicalReference(device.id.rawValue) {
    if let physicalStatus {
        PhysicalDeviceNotice(status: physicalStatus)
    } else {
        ProgressView("Reading physical device status")
    }
} else {
    SimulatorScreenView(device: device)
}
```

`DeviceWindowToolbar` thêm `PhysicalDeviceBadge` với transport từ status và disable Boot/Shutdown/Erase/Delete/Record cho physical; tooltip lấy từ `PhysicalPresentation.unsupportedReasons`. `AppShell` row thêm badge `Physical` khi prefix physical (không cần transport vì row chỉ có `Device`). `DaemonClient` thêm:

```swift
func physicalStatus(deviceID: DeviceID) async throws -> PhysicalDeviceStatus {
    try await operation("physical_status",
        parameters: ["device": deviceID.rawValue], as: PhysicalDeviceStatus.self)
}
```

DEBUG: launch argument `-OpenSimPhysicalFixture` bằng `1` dựng status fixture với screenshot/input/a11y unavailable; production không dùng fixture.

- [ ] **Step 5: Chạy pass và commit**

`xcodebuild build` in `** BUILD SUCCEEDED **`; UI test pass 1 test.

```bash
git add App/Sources/OpenSimApp Tests/OpenSimAppUITests/PhysicalDeviceUITests.swift
git commit -m "feat(app): show physical badge and unsupported states"
```

---

### Task 11: Security hardening

**Files:**
- Create: `Tests/SecurityTests/PhysicalSecurityTests.swift`
- Create: `Scripts/security/check-physical-no-credentials.sh`
- Create: `Scripts/security/check-physical-no-shell.sh`
- Modify: `Sources/OpenSimBridge/Physical/PhysicalError.swift`
- Modify: `Sources/OpenSimCLI/Runtime/CLIRuntime.swift`
- Modify: `Sources/OpenSimCLI/Runtime/DirectCommandBackend.swift`
- Modify: `Sources/OpenSimCLI/Runtime/DaemonCommandBackend.swift`

**Interfaces:**
- Consumes: `PathPolicy`, `PhysicalError`, `CommandBackend`.
- Produces: `PhysicalWritePolicy.allowsDirectMode(operation:device:)`; hai script in `OK physical no credentials`, `OK physical no shell`.

- [ ] **Step 1: Viết test và script thất bại**

```swift
func testDirectModeRejectsPhysicalWrite() {
    XCTAssertFalse(PhysicalWritePolicy.allowsDirectMode(
        operation: "app_install", device: "physical:00008030-001A2D3E0E8A802E"))
    XCTAssertTrue(PhysicalWritePolicy.allowsDirectMode(
        operation: "physical_status", device: "physical:00008030-001A2D3E0E8A802E"))
    XCTAssertTrue(PhysicalWritePolicy.allowsDirectMode(
        operation: "app_install", device: "95B3747B-7065-447E-AB1E-53065142C3FC"))
}

func testTrustPromptIsNeverAutomated() {
    let error = PhysicalError.trustRequired()
    XCTAssertEqual(error.code, "permission_denied")
    XCTAssertTrue(error.recovery?.contains("tap Trust") == true)
}
```

`check-physical-no-credentials.sh` grep `SecItem`, `add-generic-password`, `find-generic-password`, `--password`, `kSecClass` trong `Sources/OpenSimBridge/Physical` và `Sources/OpenSimCLI/Commands/PhysicalCommand.swift`; có match thì exit 1. `check-physical-no-shell.sh` grep `/bin/(sh|zsh|bash)`, `bash -c`, `zsh -c`, `sh -c`; có match thì exit 1.

- [ ] **Step 2: Chạy fail**

`swift test --filter PhysicalSecurityTests` fail vì policy chưa có. Hai script được tạo ở Step 1 và chỉ xanh sau khi source physical không còn credential/shell string.

- [ ] **Step 3: Implement policy và direct refusal**

```swift
public enum PhysicalWritePolicy {
    private static let writeOperations: Set<String> = [
        "physical_pair", "physical_unpair", "app_install", "app_uninstall",
        "app_launch", "app_terminate", "ui_tap", "ui_swipe", "ui_long_press",
        "ui_drag", "ui_pinch", "ui_rotate", "ui_scroll", "ui_type", "ui_key", "ui_button"
    ]

    public static func allowsDirectMode(operation: String, device: String) -> Bool {
        guard device.hasPrefix(PhysicalDeviceID.prefix) else { return true }
        return !writeOperations.contains(operation)
    }
}
```

`PhysicalError` thêm:

```swift
public static func directWriteRefused() -> OpenSimError {
    OpenSimError(code: .daemonUnavailable, message: "Physical write operations require the daemon",
        details: ["reason": "physical_write_requires_daemon"],
        recovery: "Run the command without --direct so a lease and audit event are created",
        retryable: true)
}
```

`CLIRuntime.makeDirectBackend` dựng `CompositeSimulatorBridge(simulator: SimctlBridge.live(timeout: .seconds(globals.timeout)), physical: PhysicalBridgeFactory.makeDefault())` và truyền `catalog: OperationCatalog.openSim()` vào `BridgeOperationExecutor` để read-only physical (`physical_status`, `physical_check_signing`) hoạt động ở direct mode. `DirectCommandBackend.execute` kiểm tra trước khi gọi executor và throw `PhysicalError.directWriteRefused()`. `DaemonCommandBackend` dùng `DeviceResolver` đã có exact-ID branch; physical write vẫn tạo session/lease ngắn hạn và audit như simulator.

- [ ] **Step 4: Chạy pass và commit**

```bash
swift test --filter PhysicalSecurityTests
Scripts/security/check-physical-no-credentials.sh
Scripts/security/check-physical-no-shell.sh
```

Expected: PASS 2 test; `OK physical no credentials`; `OK physical no shell`.

```bash
git add Tests/SecurityTests/PhysicalSecurityTests.swift Scripts/security Sources/OpenSimBridge/Physical/PhysicalError.swift Sources/OpenSimCLI/Runtime
git commit -m "feat(physical): enforce direct write refusal and security checks"
```

---

### Task 12: Integration tests, manual checklist và CI

**Files:**
- Create: `Tests/IntegrationTests/PhysicalDeviceIntegrationTests.swift`
- Create: `Tests/Release/test-physical.sh`
- Create: `.github/workflows/physical.yml`
- Create: `docs/physical-device-checklist.md`

**Interfaces:**
- Consumes: `.build/debug/opensim`, `OPENSIM_PHYSICAL_DEVICE_UDID`, `OPENSIM_PHYSICAL_APP_PATH`, `OPENSIM_PHYSICAL_BUNDLE_ID`.
- Produces: integration test skip khi thiếu UDID; script in `SKIP physical integration`; workflow `workflow_dispatch`; checklist có sign-off.

- [ ] **Step 1: Viết integration test**

```swift
final class PhysicalDeviceIntegrationTests: XCTestCase {
    private var udid: String {
        ProcessInfo.processInfo.environment["OPENSIM_PHYSICAL_DEVICE_UDID"] ?? ""
    }
    private var binary: String {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/opensim").path
    }

    override func setUpWithError() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["OPENSIM_INTEGRATION"] != "1",
                      "OPENSIM_INTEGRATION is not set")
        try XCTSkipIf(udid.isEmpty, "OPENSIM_PHYSICAL_DEVICE_UDID is not set")
    }

    private func run(_ arguments: [String]) throws -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    func testStatusAndList() throws {
        let status = try run(["physical", "status", "physical:\(udid)", "--json"])
        XCTAssertEqual(status.0, 0, status.2)
        XCTAssertTrue(status.1.contains("\"pairing\""))
        let list = try run(["device", "list", "--json"])
        XCTAssertEqual(list.0, 0, list.2)
        XCTAssertTrue(list.1.contains("physical:\(udid)"))
    }

    func testAppLifecycleWhenAppPathIsSet() throws {
        guard let app = ProcessInfo.processInfo.environment["OPENSIM_PHYSICAL_APP_PATH"],
              let bundleID = ProcessInfo.processInfo.environment["OPENSIM_PHYSICAL_BUNDLE_ID"] else {
            throw XCTSkip("OPENSIM_PHYSICAL_APP_PATH or OPENSIM_PHYSICAL_BUNDLE_ID is not set")
        }
        let install = try run(["app", "install", app, "--device", "physical:\(udid)", "--json"])
        XCTAssertEqual(install.0, 0, install.2)
        let launch = try run(["app", "launch", bundleID, "--device", "physical:\(udid)", "--json"])
        XCTAssertEqual(launch.0, 0, launch.2)
        let terminate = try run(["app", "terminate", bundleID, "--device", "physical:\(udid)", "--json"])
        XCTAssertEqual(terminate.0, 0, terminate.2)
    }
}
```

Thêm test `testScreenshotWhenCapabilityAvailable` đọc `physical_status`; nếu `capabilities.screenshot == "available"` thì chạy `ui screenshot --out <temp> --json` và assert file tồn tại; nếu không thì `throw XCTSkip("physical screenshot is unavailable")`. Tương tự cho `log_tail` và `ui tap` nếu capability available.

- [ ] **Step 2: Chạy skip**

`swift test --filter PhysicalDeviceIntegrationTests`. Expected: PASS với test skip; message `OPENSIM_INTEGRATION is not set` khi chưa đặt, hoặc `OPENSIM_PHYSICAL_DEVICE_UDID is not set` khi đã đặt integration nhưng thiếu UDID.

- [ ] **Step 3: Viết script và workflow**

`Tests/Release/test-physical.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
swift test --filter Physical
if [[ -z "${OPENSIM_PHYSICAL_DEVICE_UDID:-}" ]]; then
  print "SKIP physical integration: OPENSIM_PHYSICAL_DEVICE_UDID is not set"
  print "OK physical unit"
  exit 0
fi
if [[ -z "${OPENSIM_PHYSICAL_APP_PATH:-}" ]]; then
  print "SKIP physical app lifecycle: OPENSIM_PHYSICAL_APP_PATH is not set"
fi
OPENSIM_INTEGRATION=1 swift test --filter PhysicalDeviceIntegrationTests
print "OK physical integration"
```

`.github/workflows/physical.yml`:

```yaml
name: physical
on:
  workflow_dispatch:
jobs:
  unit:
    runs-on: macos-27
    steps:
      - uses: actions/checkout@v4
      - run: Tests/Release/test-physical.sh
```

Workflow không nằm trong required checks, không chạy trên pull request, không cần hardware. Job integration chỉ chạy trên self-hosted runner có thiết bị và biến môi trường do owner đặt.

- [ ] **Step 4: Viết checklist thủ công**

`docs/physical-device-checklist.md` ghi ngày, macOS, Xcode, thiết bị, iOS, UDID, người chạy, và các bước:

1. Bật Developer Mode, reboot, cắm USB, unlock, bấm Trust.
2. `opensim physical pair "physical:<udid>" --timeout 120 --json` trả `pairing = paired`.
3. Bấm Don't Trust, chạy lại, nhận `permission_denied` reason `trust_required`.
4. Tắt Developer Mode, chạy lại, nhận `permission_denied` reason `developer_mode_disabled`.
5. `physical check-signing` với app dev-signed trả `isInstallable = true`; app unsigned hoặc profile sai UDID trả `invalid_argument`.
6. `app install`, `app launch`, `app terminate`, `app container --kind data` thành công; container là path thiết bị.
7. Screenshot/input/log: nếu capability available thì chạy và kiểm tra output; nếu unavailable thì assert đúng error code và ghi lý do.
8. `ui tree` trả `a11y_unavailable`, không crash.
9. App hiện badge Physical, disable Boot/Shutdown/Record, hiện unsupported notice.
10. Audit có `physical.pair`, `physical.install`, `physical.launch`, `physical.terminate`.
11. `grep -i password ~/Library/Logs/OpenSim/daemon.log` không có kết quả.
12. `physical unpair --yes`, cắm lại, pair lại, restart daemon, status vẫn đúng.
13. Ký sign-off và ghi rõ capability unavailable.

- [ ] **Step 5: Chạy check xanh và commit**

```bash
chmod +x Tests/Release/test-physical.sh
Tests/Release/test-physical.sh
```

Expected: `SKIP physical integration: OPENSIM_PHYSICAL_DEVICE_UDID is not set`; `OK physical unit`.

```bash
git add Tests/IntegrationTests/PhysicalDeviceIntegrationTests.swift Tests/Release/test-physical.sh .github/workflows/physical.yml docs/physical-device-checklist.md
git commit -m "test(physical): add env-gated integration and manual checklist"
```

---

### Task 13: Tài liệu và release note

**Files:**
- Create: `docs/physical-devices.md`
- Modify: `README.md`
- Modify: `docs/compatibility.md`
- Modify: `docs/release-checklist.md`

**Interfaces:**
- Consumes: toàn bộ Task 1-12, manifest, CLI/MCP catalog.
- Produces: runbook physical, capability matrix, security model, unsupported list, release note.

- [ ] **Step 1: Viết runbook**

`docs/physical-devices.md` gồm:

- **Phạm vi:** post-release Plan 9; release simulator 0.1.0 không gồm physical.
- **Yêu cầu:** macOS 27 arm64, Xcode 27.1 có `devicectl`, iPhone/iPad iOS 27, Developer Mode, USB, Trust, app ký development profile có UDID.
- **Device ID:** `physical:<udid>`; không dùng UDID trần.
- **Pairing/trust:** lệnh `opensim physical pair "physical:<udid>" --timeout 120 --json`; người dùng tự bấm Trust; OpenSim không lưu credential, không auto-accept.
- **App lifecycle:** `physical check-signing`, `app install`, `app launch`, `app terminate`, `app container`; preflight chặn app unsigned/hết hạn/sai UDID.
- **Screen/input/log/a11y:** chỉ available khi Task 1 xác minh recipe; a11y luôn `a11y_unavailable`; recording luôn `capability_unavailable`.
- **CLI/MCP:** bốn lệnh/tool physical; các tool cũ route theo prefix.
- **Security:** không credential/keychain/signing; write qua daemon; `--direct` từ chối; path allowlist; không listener mạng; log có thể chứa dữ liệu app nên không upload hay đưa vào audit.
- **Audit:** `physical.pair`, `physical.unpair`, `physical.install`, `physical.launch`, `physical.terminate`, `physical.container`, `physical.screenshot`, `physical.input`, `physical.log`, `physical.check_signing`.
- **Không hỗ trợ:** create/clone/boot/shutdown/erase/delete/rename; runtime install/delete; `device_pair` watch/phone; push/open_url/pasteboard/location/appearance/privacy; record; ui tree/find; storage/perf theo device; live render; `.ipa` chưa giải nén; LLDB/network debugging/Instruments.
- **Troubleshooting:** trust_required, developer_mode_disabled, device_locked, recipe_not_verified, provisioning_profile_missing; mỗi lỗi kèm recovery.

- [ ] **Step 2: Cập nhật README, compatibility, release checklist**

`README.md` thêm:

```markdown
- Thiết bị iPhone/iPad thật là post-release Plan 9; xem `docs/physical-devices.md`. Release simulator không yêu cầu thiết bị thật.
```

`docs/compatibility.md` thêm:

```markdown
| 27.1 | supported | iOS 27 physical (post-release Plan 9) | `devicectl`; screenshot/input/log chỉ khi discovery xác minh |
```

`docs/release-checklist.md` thêm:

```markdown
- [ ] `Tests/Release/test-physical.sh` không chặn release simulator; in `OK physical unit` và `SKIP physical integration` khi không có thiết bị.
```

- [ ] **Step 3: Chạy kiểm tra cuối**

```bash
swift test --filter Physical
swift test --filter PhysicalOperationsTests
swift test --filter PhysicalCommandTests
swift test --filter PhysicalToolTests
swift test --filter PhysicalSecurityTests
Tests/Release/test-physical.sh
Scripts/physical/check-coredevice.sh
Scripts/security/check-physical-no-credentials.sh
Scripts/security/check-physical-no-shell.sh
```

Expected: unit/contract pass; integration skip khi không có UDID; `OK coredevice discovery`; `OK physical no credentials`; `OK physical no shell`; `OK physical unit`.

- [ ] **Step 4: Commit**

```bash
git add docs/physical-devices.md README.md docs/compatibility.md docs/release-checklist.md
git commit -m "docs(physical): add runbook and release notes"
```

---

## Spec coverage

| Mục spec | Nội dung | Task |
|---|---|---|
| 2 mục 6, 3 | iOS/iPadOS là phạm vi; thiết bị thật là plan riêng sau release | 1, 13 |
| 4 | Kiến trúc abstraction, adapter không đổi lõi | 2, 7 |
| 5.1, 5.4 | CoreDevice/private API chỉ trong Bridge; capability gate và fallback | 1, 6, 7 |
| 5.5 | Luồng agent thao tác, lifecycle, screenshot | 3, 4, 5 |
| 5.6 | Tương thích Xcode 27.1 và fingerprint | 1, 4, 13 |
| 7.2 | CLI device/app/ui/log/session | 9 |
| 8.2 | Tool catalog và MCP adapter | 9 |
| 8.3 | Error code hiện có, recovery/retryable | 2, 5, 11 |
| 9.2 | Cửa sổ device, toolbar và badge | 10 |
| 9.3 | Capability thiếu thì banner/disable, không crash | 10 |
| 12 | Security: loopback, token, path, không credential | 11 |
| 13 | Audit JSONL, log rotate | 8, 11 |
| 14.1, 14.4 | Unit test, CI không yêu cầu hardware | 2-12 |
| 14.2 | Integration test, skip/fail rõ ràng | 12 |
| 16 Plan 9 | Pair, install, launch, screenshot, HID, log, test | 1-13 |
| 18 | Rủi ro private API, capability gate | 1, 7 |
| 19 | Release simulator không gồm physical; Plan 9 post-release | 1, 13 |

## Exit criteria

1. `docs/spikes/2026-10-20-coredevice-discovery.md` có đủ bốn mục và decision. Nếu `mode = deferred`, plan dừng đúng gate, không có production code.
2. `CoreDeviceManifest.json` khớp report: gates, keyMap, recipes, classes; không có selector/command nào không thấy trong report.
3. `swift test --filter Physical` pass toàn bộ unit/contract; `swift test` đầy đủ vẫn pass test simulator cũ.
4. `Tests/Release/test-physical.sh` in `OK physical unit` và `SKIP physical integration` khi không có UDID; không chặn CI.
5. Integration hoặc checklist thủ công chạy được khi có hardware: list, pair, signing check, install, launch, terminate, container, screenshot/input/log nếu capability available.
6. Checklist thủ công được ký trên ít nhất một iPhone và một iPad, ghi rõ Xcode, iOS, capability unavailable.
7. Mọi tính năng không hỗ trợ trả `capability_unavailable`, `input_failed`, hoặc `a11y_unavailable` kèm recovery; không crash, không giả lập thành công.
8. App hiện badge Physical, disable Boot/Shutdown/Record/Erase/Delete, hiện trust banner và unsupported notice; không dùng `SimDisplayView` cho physical.
9. Audit có action `physical.*` cho write; không có credential/keychain trong source physical; không có shell string.
10. Không đổi tên/kiểu/signature type/protocol lõi; chỉ thêm file catalog, type Bridge, adapter CLI/MCP/App, test và một nhánh exact-ID trong `DeviceResolver`.
11. `docs/physical-devices.md` liệt kê đúng supported/unsupported, security, troubleshooting; README và compatibility ghi post-release.
12. Main agent review và commit; plan author không commit.
