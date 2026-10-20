# OpenSim Plan 2 — Screen, Input, Accessibility, CLI `ui`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Điền `screen`, `input`, `accessibility` vào `SimulatorBridge` của Plan 1; thêm CLI `ui` để screenshot, record, đọc UI tree, find, tap theo selector, type, gesture và batch `act`; tạo fixture iOS có identifier ổn định; tạo `OpenSimBridgeUI.SimulatorScreenView` với API cố định cho Plan 4; xử lý private API bằng capability gate và fallback đã định trong spec.

**Architecture:** `OpenSimCore` thêm selector parser, point parser, automation DTO và catalog `ui`. `OpenSimBridge` có ba lớp: `SimctlScreenService` cho screenshot/record/screen info qua `simctl`; `FramebufferDisplaySurface` render IOSurface lấy từ `SimDeviceScreen(screenID: 1).screen.framebufferSurface`; input và accessibility qua XCUITest helper, screenshot polling là fallback render. `SimctlBridge.live` chọn backend bằng `Plan2CapabilityGate`, trả service tương ứng hoặc `nil`. `OpenSimCLI` thêm nhóm `ui`, dùng `OperationCatalog.plan2()`, `BridgeOperationExecutor` và `UIAutomationService`. `OpenSimBridgeUI` chỉ bọc `DisplaySurface`, không gọi private API.

**Tech Stack:** Swift 6 language mode, SwiftPM, AppKit, CoreGraphics/ImageIO, IOSurface, XCTest/XCUITest, `xcrun simctl`, XcodeGen cho fixture, macOS 27.0+, Xcode 27.1, arm64.

**Spec:** `docs/superpowers/specs/2026-10-19-open-simulator-design.md`

## Global Constraints

- macOS 27.0+; arm64; Xcode 27.1 là bản chính; yêu cầu full Xcode.
- Swift 6 language mode; package `OpenSim`; CLI `opensim`; fixture bundle ID `dev.opensim.fixture`.
- Plan 0 **đã chạy** (report `docs/superpowers/spikes/2026-10-19-private-api-spike.md`). Mọi private API đi qua `Plan2CapabilityGate`; gate không đạt thì dùng fallback hoặc trả `capability_unavailable`.
- Danh sách API private đóng: class `SimulatorKit.SimDeviceScreen`, `SimServiceContext`, `SimDeviceSet`, `SimDevice`; selector `sharedServiceContextForDeveloperDir:error:`, `defaultDeviceSetWithError:`, `devices`, `UDID`, `name`, `stateString`, `state`, `initWithDevice:screenID:`, `screen`, `framebufferSurface`, `maskedFramebufferSurface`, `displaySize`. `SimDisplayView`/`SimAccessibilityManager` và getter tree không còn trong đường primary. Symbol `IndigoHIDMessageFor*` chỉ dùng khi target mapping được xác minh; Plan 2 không đoán `IndigoHIDTarget`.
- Không thêm daemon, MCP, app UI, storage, performance, session/lease. `OpenSimBridgeUI` chỉ là view wrapper cho Plan 4.
- Mọi process dùng `Process` với argument array; không shell string. Không Chrome, không tải runtime, không lệnh destructive.
- Screenshot CLI mặc định ghi file. `Screenshot.scale` là hệ số resize so với pixel gốc; chấp nhận `0.1` đến `4.0`.
- Tọa độ `ui` là point, gốc trên-trái, hệ tọa độ simulator. `ScreenInfo.width/height` là pixel; `SimulatorScreenView.screenSize` là point.
- Recording state file quyền `0600` dưới `~/Library/Application Support/OpenSim/recordings`; output path qua `PathPolicy.validateOutputPath`.
- Integration test chỉ chạy khi `OPENSIM_INTEGRATION=1`. Test primary skip khi fallback active và ngược lại. Fixture cần `xcodegen`; thiếu thì skip và báo rõ, không tự cài.
- Mỗi task có check đỏ, implement, check xanh, commit. Không chạy commit trong lúc viết plan.
- Văn xuôi tiếng Việt; code/identifier/command tiếng Anh; không ký tự CJK.

## Plan 0 Result — Backend Decisions (2026-10-20)

Plan 0 đã chạy trên iPhone Air/iOS 27.0; report đầy đủ ở `docs/superpowers/spikes/2026-10-19-private-api-spike.md`. Kết quả dưới đây là nguồn quyết định; Task 6 gate chỉ xác nhận lại capability trên máy đích.

| Khả năng | Kết quả Plan 0 | Backend Plan 2 | Task |
|---|---|---|---|
| Render | PASS | `SimDeviceScreen(screenID: 1).screen.framebufferSurface` → IOSurface, host NSView | 9 |
| `SimDisplayView` direct | FAIL | Retire: không có `connectedScreen`/`pixelSize`/`unmaskedSurface`; view capture đen | 7 retired |
| Input | BLOCKED | XCUITest helper primary; `SimDisplayView` digitizer retired; HID target mapping follow-up | 10, 8 retired |
| Accessibility | UNAVAILABLE | XCUITest helper primary; `SimAccessibilityManager` không có tree getter | 10, 11 retired |
| Screenshot/video | PASS | `simctl io` | 4, 5 |
| watchOS/tvOS | BLOCKED | runtime missing; Plan 6 | — |

Quy tắc:

1. `render`: ưu tiên `framebufferSurface`; thiếu class/selector hoặc surface nil thì screenshot polling 10 fps.
2. `input`: `dtuhid` (CoreSimulator 1155.4+/Xcode 27) là primary; XCUITest helper chỉ còn cho accessibility và fallback. Không dùng `ViewEventInputService`/legacy Indigo làm primary.
3. `accessibility`: `xcuiTest`; private tree trả `a11y_unavailable`, không suy diễn từ `SimAccessibilityManager`.
4. `multiTouch` và `hardwareButtons` chỉ `available` sau khi XCUITest helper chạy `pinch`/`rotate`/`home` trên fixture; gate xác nhận.
5. `FramebufferDisplaySurface` đọc lại `displaySize`/surface mỗi frame; frame stream giới hạn `.bufferingNewest(1)`.
6. Task 7, 8, 11 bị **retire**: không implement code trong các section đó. Task 9 là primary render; Task 10 là primary input/a11y.

## File Structure

| File | Trách nhiệm |
|---|---|
| `Package.swift` | thêm target `OpenSimBridgeUI` ở Task 13 |
| `Sources/OpenSimCore/Domain/Automation.swift` | `UIActionResult`, `UIWaitResult`, `UIActStep`, `UIActStepResult`, `UIActResult`, `RecordingInfo`, `RecordingStopResult` |
| `Sources/OpenSimCore/Domain/Screen.swift` | thêm `ScreenRotation` |
| `Sources/OpenSimCore/Catalog/Plan2Operations.swift` | operation `screen_*`, `ui_*` |
| `Sources/OpenSimCore/Catalog/OperationCatalog.swift` | `merging(_:)` |
| `Sources/OpenSimCore/Validation/SelectorParser.swift` | parse `role=`, `label=`, `id=`, `text=` |
| `Sources/OpenSimCore/Validation/PointParser.swift` | parse `x,y` và cặp `--x/--y` |
| `Sources/OpenSimCore/Automation/UIElementMatcher.swift` | match và duyệt `UIElement` |
| `Sources/OpenSimCore/Support/OpenSimPaths.swift` | thư mục screenshots/recordings |
| `Sources/OpenSimCore/Validation/PathPolicy.swift` | `validateOutputPath` |
| `Sources/OpenSimBridge/Simctl/SimctlCommand.swift` | `io enumerate`, `io screenshot`, `io recordVideo`, `list devicetypes` |
| `Sources/OpenSimBridge/Screen/ScreenEnumerateParser.swift` | parse output `simctl io enumerate` |
| `Sources/OpenSimBridge/Screen/DeviceTypeProfileReader.swift` | scale/rotation từ `capabilities.plist` |
| `Sources/OpenSimBridge/Screen/ScreenshotProcessor.swift` | resize/encode PNG/JPEG |
| `Sources/OpenSimBridge/Screen/SimctlScreenCapture.swift` | `screens`, `screenshot` |
| `Sources/OpenSimBridge/Screen/RecordingStateStore.swift` | state file recording |
| `Sources/OpenSimBridge/Screen/SimctlRecordingController.swift` | start/stop `simctl io recordVideo` |
| `Sources/OpenSimBridge/Services/SimctlScreenService.swift` | `ScreenControlling`, `RecordingControlling` |
| `Sources/OpenSimBridge/Private/SimulatorKitLoader.swift` | `dlopen`, class/selector/symbol probe |
| `Sources/OpenSimBridge/Private/CoreSimulatorDeviceLookup.swift` | `SimDevice` object bằng selector Plan 0 |
| `Sources/OpenSimBridge/Capabilities/Plan2CapabilityGate.swift` | chọn backend |
| `Sources/OpenSimBridge/Screen/DisplaySurface.swift` | protocol surface |
| `Sources/OpenSimBridge/Screen/FramebufferDisplaySurface.swift` | primary render từ `framebufferSurface` |
| `Sources/OpenSimBridge/Screen/ScreenshotPollingSurface.swift` | fallback render |
| `Sources/OpenSimBridge/Input/InputGesturePlanner.swift` | sample gesture cho XCUITest |
| `Sources/OpenSimBridge/Input/KeyboardMap.swift` | keyCode và modifier |
| `Sources/OpenSimBridge/Input/CompositeInputService.swift` | route XCUITest/fallback |
| `Sources/OpenSimBridge/Accessibility/UIElementTreeBuilder.swift` | object tree sang `UIElement` |
| `Sources/OpenSimBridge/XCUITest/XCUITestSnapshotMapper.swift` | map snapshot JSON |
| `Sources/OpenSimBridge/XCUITest/XCUITestHelperRunner.swift` | chạy helper test |
| `Sources/OpenSimBridge/Services/XCUITestAccessibilityService.swift` | primary a11y |
| `Sources/OpenSimBridge/Services/XCUITestInputService.swift` | fallback input (legacy Xcode/helper) |
| `Sources/OpenSimBridge/Services/UIAutomationService.swift` | tap selector, wait, act |
| `Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift` | case `screen_*`, `ui_*` |
| `Sources/OpenSimBridge/SimctlBridge.swift` | điền optional service |
| `Sources/OpenSimBridge/Environment/CapabilityEvaluator.swift` | map gate vào capability |
| `Sources/OpenSimBridge/Environment/DoctorService.swift` | backend trong notes |
| `Sources/OpenSimBridgeUI/SimulatorScreenView.swift` | API cho Plan 4 |
| `Sources/OpenSimBridgeUI/ScreenPointerMapper.swift` | map point và rotation |
| `Sources/OpenSimCLI/Commands/UICommand.swift` | nhóm `ui` |
| `Sources/OpenSimCLI/Commands/UICommandSupport.swift` | encode selector/point/steps |
| `Sources/OpenSimCLI/Runtime/CLIRuntime.swift` | catalog `plan2`, automation |
| `Fixtures/OpenSimFixture/project.yml` | XcodeGen app + UI test |
| `Fixtures/OpenSimFixture/Sources/AppDelegate.swift` | lifecycle |
| `Fixtures/OpenSimFixture/Sources/FixtureViewController.swift` | màn hình fixture |
| `Fixtures/OpenSimFixture/Sources/DetailsViewController.swift` | màn hình details |
| `Fixtures/OpenSimFixture/UITests/OpenSimFixtureUITests.swift` | helper fallback |
| `Fixtures/OpenSimFixture/build.sh` | build app |
| `Tests/OpenSimCoreTests/Plan2CatalogTests.swift` | catalog |
| `Tests/OpenSimCoreTests/SelectorParserTests.swift` | parser, matcher |
| `Tests/OpenSimBridgeTests/ScreenLayerTests.swift` | enumerate, processor, screenshot |
| `Tests/OpenSimBridgeTests/RecordingControllerTests.swift` | start/stop |
| `Tests/OpenSimBridgeTests/Plan2CapabilityGateTests.swift` | chọn backend |
| `Tests/OpenSimBridgeTests/Plan2GateProbeTests.swift` | probe thật, skip |
| `Tests/OpenSimBridgeTests/InputTests.swift` | planner, keyboard, surface support |
| `Tests/OpenSimBridgeTests/CompositeInputTests.swift` | composite routing |
| `Tests/OpenSimBridgeTests/FallbackTests.swift` | IOSurface support, polling, snapshot |
| `Tests/OpenSimBridgeTests/AccessibilityTreeTests.swift` | tree builder |
| `Tests/OpenSimBridgeTests/UIAutomationServiceTests.swift` | tap selector, wait, act |
| `Tests/OpenSimBridgeUITests/SimulatorScreenViewTests.swift` | API, size, rotation |
| `Tests/OpenSimCLITests/UICommandParsingTests.swift` | parse `ui` |
| `Tests/IntegrationTests/Plan2FixtureIntegrationTests.swift` | fixture flow |
| `Tests/IntegrationTests/Support/FixtureInstaller.swift` | build/install/launch |
| `Tests/IntegrationTests/README.md` | hướng dẫn |
| `docs/superpowers/spikes/2026-10-20-plan2-capability-gate.md` | gate report |

---

### Task 1: Automation domain và catalog `ui`

**Files:**
- Modify: `Sources/OpenSimCore/Domain/Screen.swift`, `Sources/OpenSimCore/Catalog/OperationCatalog.swift`
- Create: `Sources/OpenSimCore/Domain/Automation.swift`, `Sources/OpenSimCore/Catalog/Plan2Operations.swift`
- Test: `Tests/OpenSimCoreTests/Plan2CatalogTests.swift`

**Interfaces:**
- Consumes: `Operation`, `OperationParameter`, `OperationCatalog.plan1()`, `Point`, `Screenshot`, `ElementSelector`, `KeyModifiers`, `ScreenshotFormat`, `RecordingID`, `DeviceID`, `VideoCodec`.
- Produces: `ScreenRotation`; `UIActionResult`; `UIWaitResult`; `UIActStep`; `UIActStepResult`; `UIActResult`; `RecordingInfo`; `RecordingStopResult`; `OperationCatalog.merging(_:)`; `OperationCatalog.plan2()`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimCore

final class Plan2CatalogTests: XCTestCase {
    func testPlan1IsUnchanged() {
        XCTAssertEqual(OperationCatalog.plan1().mcpOperations().count, 23)
    }

    func testPlan2AddsEveryUIOperation() throws {
        let catalog = OperationCatalog.plan2()
        XCTAssertEqual(catalog.validate(), [])
        XCTAssertEqual(try XCTUnwrap(catalog.operation(forCLI: ["ui", "tap"])).mcpName, "ui_tap")
        XCTAssertEqual(try XCTUnwrap(catalog.operation(forMCP: "screen_screenshot")).cliPath, ["ui", "screenshot"])
        XCTAssertTrue(try XCTUnwrap(catalog.operation(forMCP: "ui_tree")).readOnly)
        XCTAssertTrue(try XCTUnwrap(catalog.operation(forMCP: "ui_tap")).requiresControlLease)
    }

    func testActionStepRoundTrips() throws {
        let step = UIActStep(type: "tap", on: ElementSelector(identifier: "fixture-primary-button"))
        let data = try OpenSimJSON.encoder(pretty: false).encode(step)
        XCTAssertEqual(try OpenSimJSON.decoder().decode(UIActStep.self, from: data), step)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter Plan2CatalogTests
```

Expected: FAIL với `cannot find 'UIActStep' in scope`.

- [ ] **Step 3: Viết domain và catalog**

Target `OpenSimBridgeUI` và `OpenSimBridgeUITests` được thêm ở Task 13, sau khi có source đầu tiên, để `swift build` không lỗi target rỗng.

`ScreenRotation`: `portrait`, `landscapeLeft`, `portraitUpsideDown`, `landscapeRight`; `degrees` lần lượt `0`, `90`, `180`, `270`; `isSideways` cho 90/270.

`Automation.swift` khai báo các struct `Codable, Sendable, Equatable` với optional field mặc định `nil`:

```swift
public struct UIActStep: Codable, Sendable, Equatable {
    public var type: String
    public var x: Double? = nil
    public var y: Double? = nil
    public var from: Point? = nil
    public var to: Point? = nil
    public var center: Point? = nil
    public var at: Point? = nil
    public var scale: Double? = nil
    public var angle: Double? = nil
    public var deltaX: Double? = nil
    public var deltaY: Double? = nil
    public var durationMs: Int? = nil
    public var text: String? = nil
    public var key: String? = nil
    public var button: String? = nil
    public var modifiers: KeyModifiers? = nil
    public var on: ElementSelector? = nil
    public var selector: String? = nil
    public var ms: Int? = nil
    public var idleMs: Int? = nil
    public var timeoutMs: Int? = nil
    public var format: ScreenshotFormat? = nil
    public var quality: Int? = nil
    public var out: String? = nil
    public var settle: Bool? = nil

    public init(type: String) {
        self.type = type
    }

    public init(type: String, on: ElementSelector) {
        self.type = type
        self.on = on
    }
}
```

`UIActionResult` gồm `action`, `point`, `matchedElementID`, `matchedCount`, `settleMs`, `screenshot`; `UIWaitResult` gồm `matched`, `idle`, `waitedMs`, `element`; `UIActStepResult` gồm `index`, `type`, `ok`, `error`, `action`, `wait`, `screenshot`; `UIActResult` gồm `steps`, `stopped`. `RecordingInfo` gồm `id`, `deviceID`, `path`, `codec`, `startedAt`; `RecordingStopResult` gồm `id`, `path`, `durationMs`. Tất cả có init public và optional mặc định `nil`.

`OperationCatalog.merging`:

```swift
public func merging(_ other: OperationCatalog) -> OperationCatalog {
    var result = self
    for operation in other.operations.values {
        result.register(operation)
    }
    return result
}
```

`Plan2Operations` dùng bảng spec thay vì lặp init:

```swift
public extension OperationCatalog {
    static func plan2() -> OperationCatalog {
        plan1().merging(OperationCatalog(operations: Plan2Operations.all))
    }
}

public enum Plan2Operations {
    private static func p(_ name: String, _ type: String, required: Bool = true, default value: String? = nil) -> OperationParameter {
        OperationParameter(name: name, type: type, required: required, defaultValue: value)
    }
    private static let device = p("device", "string", required: false)
    private static let duration = p("durationMs", "integer", required: false, default: "300")

    private static let specs: [(path: [String], mcp: String, readOnly: Bool, lease: Bool, service: BridgeService?, params: [OperationParameter])] = [
        (["ui", "info"], "screen_info", true, false, .screen, [device]),
        (["ui", "screenshot"], "screen_screenshot", true, false, .screen, [device, p("format", "string", required: false, default: "png"), p("scale", "number", required: false, default: "1.0"), p("quality", "integer", required: false), p("out", "string", required: false)]),
        (["ui", "record", "start"], "screen_record_start", false, true, .screen, [device, p("out", "string", required: false), p("codec", "string", required: false, default: "h264")]),
        (["ui", "record", "stop"], "screen_record_stop", false, true, .screen, [p("recordingID", "string")]),
        (["ui", "tree"], "ui_tree", true, false, .accessibility, [device, p("maxDepth", "integer", required: false, default: "30"), p("maxNodes", "integer", required: false, default: "1500")]),
        (["ui", "find"], "ui_find", true, false, .accessibility, [device, p("selector", "selector")]),
        (["ui", "tap"], "ui_tap", false, true, .input, [device, p("x", "number", required: false), p("y", "number", required: false), p("on", "selector", required: false), p("settle", "boolean", required: false, default: "false")]),
        (["ui", "swipe"], "ui_swipe", false, true, .input, [device, p("from", "point"), p("to", "point"), duration]),
        (["ui", "long-press"], "ui_long_press", false, true, .input, [device, p("x", "number"), p("y", "number"), p("durationMs", "integer", required: false, default: "800")]),
        (["ui", "drag"], "ui_drag", false, true, .input, [device, p("from", "point"), p("to", "point"), duration]),
        (["ui", "pinch"], "ui_pinch", false, true, .input, [device, p("center", "point"), p("scale", "number"), duration]),
        (["ui", "rotate"], "ui_rotate", false, true, .input, [device, p("center", "point"), p("angle", "number"), duration]),
        (["ui", "scroll"], "ui_scroll", false, true, .input, [device, p("deltaX", "number"), p("deltaY", "number"), p("at", "point", required: false)]),
        (["ui", "type"], "ui_type", false, true, .input, [device, p("text", "string")]),
        (["ui", "key"], "ui_key", false, true, .input, [device, p("key", "string"), p("modifiers", "json", required: false)]),
        (["ui", "button"], "ui_button", false, true, .input, [device, p("button", "string")]),
        (["ui", "wait"], "ui_wait", true, false, .accessibility, [device, p("selector", "selector", required: false), p("idleMs", "integer", required: false, default: "250"), p("timeoutMs", "integer", required: false, default: "5000")]),
        (["ui", "act"], "ui_act", false, true, .input, [device, p("steps", "json"), p("stopOnError", "boolean", required: false, default: "true")]),
    ]

    public static var all: [Operation] {
        specs.map { spec in
            Operation(
                cliPath: spec.path,
                mcpName: spec.mcp,
                summary: spec.mcp.replacingOccurrences(of: "_", with: " "),
                requiresControlLease: spec.lease,
                destructive: false,
                readOnly: spec.readOnly,
                parameters: spec.params,
                requiredService: spec.service
            )
        }
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift test --filter Plan2CatalogTests
```

Expected: PASS; `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCore Tests/OpenSimCoreTests/Plan2CatalogTests.swift
git commit -m "feat(core): add plan 2 automation types and ui catalog"
```

---

### Task 2: Selector parser, point parser và element matcher

**Files:**
- Create: `Sources/OpenSimCore/Validation/SelectorParser.swift`, `Sources/OpenSimCore/Validation/PointParser.swift`, `Sources/OpenSimCore/Automation/UIElementMatcher.swift`
- Test: `Tests/OpenSimCoreTests/SelectorParserTests.swift`

**Interfaces:**
- Produces: `SelectorParser.parse(_:)`; `PointParser.parse(_:label:)`, `.parse(x:y:)`; `UIElementMatcher.matches(_:selector:)`, `.find(in:selector:limit:)`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimCore

final class SelectorParserTests: XCTestCase {
    func testParsesQuotedAndEscapedValues() throws {
        let selector = try SelectorParser.parse("role=button, label=\"Sign in, now\"")
        XCTAssertEqual(selector.role, "button")
        XCTAssertEqual(selector.label, "Sign in, now")
        XCTAssertEqual(try SelectorParser.parse("label=Hello\\, world").label, "Hello, world")
    }

    func testRejectsInvalidSelectors() {
        XCTAssertThrowsError(try SelectorParser.parse("foo=bar"))
        XCTAssertThrowsError(try SelectorParser.parse("label="))
        XCTAssertThrowsError(try SelectorParser.parse("id=a,id=b"))
    }

    func testPointAndMatcher() throws {
        XCTAssertEqual(try PointParser.parse("12.5,-4", label: "from"), Point(x: 12.5, y: -4))
        XCTAssertThrowsError(try PointParser.parse(x: "10", y: nil))
        let element = UIElement(id: "e", role: "button", label: "Primary Action", identifier: "fixture-primary-button", value: nil, frame: Rect(x: 10, y: 20, width: 100, height: 44), enabled: true, selected: false, children: [])
        XCTAssertTrue(UIElementMatcher.matches(element, selector: ElementSelector(identifier: "fixture-primary-button")))
        XCTAssertFalse(UIElementMatcher.matches(element, selector: ElementSelector(role: "staticText")))
        XCTAssertEqual(UIElementMatcher.find(in: element, selector: ElementSelector(text: "primary")).count, 1)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter SelectorParserTests
```

Expected: FAIL với `cannot find 'SelectorParser' in scope`.

- [ ] **Step 3: Viết parser và matcher**

`SelectorParser` quét chuỗi, hỗ trợ quote đơn/kép, escape `\,`, `\=`, `\\`; key hợp lệ `role`, `label`, `id`/`identifier`, `text`; cấm key lạ, value rỗng, key lặp; yêu cầu ít nhất một field. `PointParser` yêu cầu đúng hai số hữu hạn. `UIElementMatcher`: role/label/identifier so khớp không phân biệt hoa thường; text so khớp chứa trong label/value/identifier; mọi field là AND; `find` duyệt pre-order, giới hạn `limit`.

```swift
public enum SelectorParser {
    public static func parse(_ text: String) throws -> ElementSelector {
        var selector = ElementSelector()
        var seen = Set<String>()
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace || text[index] == "," { index = text.index(after: index) }
            if index == text.endIndex { break }
            var key = ""
            while index < text.endIndex, text[index] != "=" {
                key.append(text[index])
                index = text.index(after: index)
            }
            guard index < text.endIndex else {
                throw OpenSimError.invalidArgument("Selector field \(key) is missing '='")
            }
            index = text.index(after: index)
            var value = ""
            var quote: Character?
            var escaped = false
            while index < text.endIndex {
                let character = text[index]
                if escaped {
                    value.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if let active = quote {
                    if character == active { quote = nil } else { value.append(character) }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "," {
                    break
                } else {
                    value.append(character)
                }
                index = text.index(after: index)
            }
            let normalizedKey = key.trimmingCharacters(in: .whitespaces).lowercased()
            let normalizedValue = value.trimmingCharacters(in: .whitespaces)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else {
                throw OpenSimError.invalidArgument("Selector key and value must not be empty")
            }
            guard seen.insert(normalizedKey).inserted else {
                throw OpenSimError.invalidArgument("Duplicate selector field \(normalizedKey)")
            }
            switch normalizedKey {
            case "role": selector.role = normalizedValue
            case "label": selector.label = normalizedValue
            case "id", "identifier": selector.identifier = normalizedValue
            case "text": selector.text = normalizedValue
            default:
                throw OpenSimError.invalidArgument("Unknown selector field \(normalizedKey)", details: ["allowed": "role,label,id,text"])
            }
        }
        guard selector.role != nil || selector.label != nil || selector.identifier != nil || selector.text != nil else {
            throw OpenSimError.invalidArgument("Selector must contain at least one field")
        }
        return selector
    }
}
```

`PointParser.parse` tách dấu phẩy, kiểm tra `Double` và `.isFinite`; `parse(x:y:)` yêu cầu cả hai. `UIElementMatcher` dùng `compare(options: [.caseInsensitive, .diacriticInsensitive])` và `range(of:options:)`; `find` đệ quy với `limit`.

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift test --filter SelectorParserTests
```

Expected: PASS; `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCore/Validation/SelectorParser.swift Sources/OpenSimCore/Validation/PointParser.swift Sources/OpenSimCore/Automation/UIElementMatcher.swift Tests/OpenSimCoreTests/SelectorParserTests.swift
git commit -m "feat(core): add selector and point parsing"
```

---

### Task 3: Fixture iOS với accessibility identifier ổn định

**Files:**
- Create: `Fixtures/OpenSimFixture/project.yml`, `Fixtures/OpenSimFixture/Sources/AppDelegate.swift`, `Fixtures/OpenSimFixture/Sources/FixtureViewController.swift`, `Fixtures/OpenSimFixture/Sources/DetailsViewController.swift`, `Fixtures/OpenSimFixture/build.sh`
- Modify: `.gitignore` cho `Fixtures/OpenSimFixture/build/` và `Fixtures/OpenSimFixture/OpenSimFixture.xcodeproj/`

**Interfaces:**
- Produces: bundle `dev.opensim.fixture`; identifier `fixture-title`, `fixture-text-field`, `fixture-text-value`, `fixture-primary-button`, `fixture-counter-label`, `fixture-toggle`, `fixture-toggle-state`, `fixture-slider`, `fixture-slider-value`, `fixture-details-button`, `fixture-long-press-target`, `fixture-swipe-area`, `fixture-gesture-label`, `fixture-gesture-canvas`, `fixture-canvas-label`, `fixture-item-alpha`, `fixture-item-beta`, `fixture-item-gamma`, `fixture-selection-label`, `fixture-bottom-label`, `fixture-details-label`; `build.sh` in `.app` path ở dòng cuối.

- [ ] **Step 1: Viết check thất bại**

```bash
test -x Fixtures/OpenSimFixture/build.sh
```

Expected: FAIL vì script chưa tồn tại.

- [ ] **Step 2: Viết project, build script và fixture**

`project.yml` khai báo app iOS deployment 17.0, `PRODUCT_BUNDLE_IDENTIFIER: dev.opensim.fixture`, `CODE_SIGNING_ALLOWED: NO`, `GENERATE_INFOPLIST_FILE: YES`, `INFOPLIST_KEY_UILaunchScreen_Generation: YES`; target UI test `OpenSimFixtureUITests` type `bundle.ui-testing`, `TEST_TARGET_NAME: OpenSimFixture`; scheme build cả hai target.

`build.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
command -v xcodegen >/dev/null || { print -u2 "xcodegen is required"; exit 2; }
cd "$ROOT"
xcodegen generate --spec project.yml --project .
xcodebuild -project OpenSimFixture.xcodeproj -scheme OpenSimFixture -configuration Debug \
  -sdk iphonesimulator -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
print "$ROOT/build/Build/Products/Debug-iphonesimulator/OpenSimFixture.app"
```

`AppDelegate` tạo `UIWindow` với `UINavigationController(rootViewController: FixtureViewController())`.

`FixtureViewController` dùng `UIScrollView` + `UIStackView`, thêm:

- `UILabel` `fixture-title` text `OpenSim Fixture`.
- `UITextField` `fixture-text-field`, delegate/editingChanged cập nhật `fixture-text-value` = `text=\(text)`.
- `UIButton` `fixture-primary-button` tăng `tapCount`, cập nhật `fixture-counter-label` và title `Primary Action \(tapCount)`.
- `UISwitch` `fixture-toggle` cập nhật `fixture-toggle-state`; `UISlider` `fixture-slider` cập nhật `fixture-slider-value`.
- `UIButton` `fixture-details-button` push `DetailsViewController`; `DetailsViewController` có label `fixture-details-label`.
- `UIView` `fixture-long-press-target` với `UILongPressGestureRecognizer` cập nhật `fixture-gesture-label` = `gesture=long-press`.
- `UIView` `fixture-swipe-area` với swipe trái/phải cập nhật `fixture-gesture-label`.
- `UIView` `fixture-gesture-canvas` với pinch/rotate cập nhật `fixture-canvas-label` dạng `canvas=scale:%.2f,rotation:%.2f`.
- Ba button `fixture-item-alpha/beta/gamma` cập nhật `fixture-selection-label`.
- 12 spacer và `fixture-bottom-label` để scroll.

Mỗi container gesture đặt `isAccessibilityElement = true`, `accessibilityLabel`; control đặt `accessibilityIdentifier`; label trong container `isUserInteractionEnabled = false`.

```swift
private func makeButton(_ title: String, identifier: String, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.accessibilityIdentifier = identifier
    button.addTarget(self, action: action, for: .touchUpInside)
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    return button
}

@objc private func primaryTapped() {
    tapCount += 1
    counterLabel.text = "\(tapCount)"
    primaryButton.setTitle("Primary Action \(tapCount)", for: .normal)
}
```

- [ ] **Step 3: Build, install và xác nhận**

```bash
chmod +x Fixtures/OpenSimFixture/build.sh
APP="$(Fixtures/OpenSimFixture/build.sh | tail -1)"
UDID="$(xcrun simctl list devices booted -j | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for v in d["devices"].values() for x in v if x["state"]=="Booted"))')"
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" dev.opensim.fixture
xcrun simctl io "$UDID" screenshot /tmp/opensim-fixture.png
```

Expected: app launch in PID; ảnh có title, text field, button. Đọc ảnh bằng tool Read. Nếu thiếu `xcodegen`, dừng và báo blocker.

- [ ] **Step 4: Commit**

```bash
git add .gitignore Fixtures/OpenSimFixture
git commit -m "test(fixture): add stable iOS fixture app"
```

---

### Task 4: Screen enumeration và screenshot qua `simctl`

**Files:**
- Modify: `Sources/OpenSimBridge/Simctl/SimctlCommand.swift`, `Sources/OpenSimCore/Support/OpenSimPaths.swift`, `Sources/OpenSimCore/Validation/PathPolicy.swift`
- Create: `Sources/OpenSimBridge/Screen/ScreenEnumerateParser.swift`, `Sources/OpenSimBridge/Screen/DeviceTypeProfileReader.swift`, `Sources/OpenSimBridge/Screen/ScreenshotProcessor.swift`, `Sources/OpenSimBridge/Screen/SimctlScreenCapture.swift`
- Test: `Tests/OpenSimBridgeTests/ScreenLayerTests.swift`

**Interfaces:**
- Produces: `SimctlArguments.ioEnumerate`, `.ioScreenshot`, `.ioRecordVideo`, `.listDeviceTypesJSON`; `ScreenEnumerateParser.parse`; `ScreenProfile`; `ScreenProfileProviding`; `SimctlDeviceTypeProfileProvider`; `ScreenshotProcessor.render`; `RenderedScreenshot`; `ScreenDeviceReading`; `SimctlScreenCapture.screens`, `.screenshot`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class ScreenLayerTests: XCTestCase {
    func testEnumerateParsesDisplays() {
        let text = """
        Port:
            UUID: A
            Class: Unknown
            Port Identifier: com.apple.display.captureservice

        Port:
            UUID: B
            Class: Display
            Port Identifier: com.apple.framebuffer.display
            Power state: On
            Display class: 0
            Default width: 1260
            Default height: 2736
        """
        let values = ScreenEnumerateParser.parse(text)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0].width, 1260)
        XCTAssertEqual(values[0].displayClass, 0)
    }

    func testIOArgumentsAndOutputPath() throws {
        let udid = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")
        XCTAssertEqual(SimctlArguments.ioEnumerate(udid).arguments, ["io", udid.rawValue, "enumerate"])
        XCTAssertEqual(SimctlArguments.ioScreenshot(udid, path: "/tmp/a.png").arguments, ["io", udid.rawValue, "screenshot", "--type=png", "/tmp/a.png"])
        XCTAssertEqual(SimctlArguments.ioRecordVideo(udid, path: "/tmp/a.mov", codec: .h264).arguments, ["io", udid.rawValue, "recordVideo", "--codec=h264", "--force", "/tmp/a.mov"])
        XCTAssertNoThrow(try PathPolicy.validateOutputPath("/tmp/a.png", allowedExtensions: ["png", "jpeg"]))
        XCTAssertThrowsError(try PathPolicy.validateOutputPath("a.png", allowedExtensions: ["png"]))
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter ScreenLayerTests
```

Expected: FAIL với `cannot find 'ScreenEnumerateParser' in scope`.

- [ ] **Step 3: Viết screen layer**

`SimctlCommand` thêm:

```swift
public static func listDeviceTypesJSON() -> SimctlCommand { SimctlCommand(arguments: ["list", "devicetypes", "-j"]) }
public static func ioEnumerate(_ device: DeviceID) -> SimctlCommand { SimctlCommand(arguments: ["io", device.rawValue, "enumerate"]) }
public static func ioScreenshot(_ device: DeviceID, path: String) -> SimctlCommand { SimctlCommand(arguments: ["io", device.rawValue, "screenshot", "--type=png", path]) }
public static func ioRecordVideo(_ device: DeviceID, path: String, codec: VideoCodec) -> SimctlCommand {
    SimctlCommand(arguments: ["io", device.rawValue, "recordVideo", "--codec=\(codec.rawValue)", "--force", path])
}
```

`OpenSimPaths` thêm `screenshotsDirectory`, `recordingsDirectory`, `recordingStateDirectory`, `ensureMediaDirectories` (quyền `0700`). `PathPolicy.validateOutputPath` kiểm tra absolute, null byte, `clientRoots`, parent tồn tại, extension, không phải directory.

`ScreenEnumerateParser` tách block theo `\n\n`, đọc key/value theo dấu `:`, chỉ nhận `Class: Display`, yêu cầu `UUID`, `Default width`, `Default height`; trả `IOSurfaceDescriptor` gồm `uuid`, `portIdentifier`, `displayClass`, `width`, `height`, `powerState`.

`SimctlDeviceTypeProfileProvider` chạy `list devicetypes -j`, tìm `bundlePath`, đọc `Contents/Resources/capabilities.plist`, lấy `capabilities.ScreenDimensionsCapability` với `main-screen-scale`, `main-screen-orientation`, `main-screen-width`, `main-screen-height`; cache actor theo deviceType.

`ScreenshotProcessor.render` dùng ImageIO:

```swift
public func render(source: URL, format: ScreenshotFormat, scale: Double, quality: Int?) throws -> RenderedScreenshot {
    guard 0.1 <= scale && scale <= 4.0 else {
        throw OpenSimError.invalidArgument("scale must be between 0.1 and 4.0")
    }
    if let quality, format == .png {
        throw OpenSimError.invalidArgument("quality is only supported for JPEG")
    }
    if let quality, !(1..<101).contains(quality) {
        throw OpenSimError.invalidArgument("quality must be between 1 and 100")
    }
    guard let sourceImage = CGImageSourceCreateWithURL(source as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(sourceImage, 0, nil) else {
        throw OpenSimError(code: .inputFailed, message: "Could not read screenshot")
    }
    let width = max(1, Int((Double(image.width) * scale).rounded()))
    let height = max(1, Int((Double(image.height) * scale).rounded()))
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let context else { throw OpenSimError(code: .internalError, message: "No image context") }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let scaled = context.makeImage() else { throw OpenSimError(code: .internalError, message: "No scaled image") }
    let data = NSMutableData()
    let type = format == .png ? UTType.png.identifier : UTType.jpeg.identifier
    guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else {
        throw OpenSimError(code: .internalError, message: "No image destination")
    }
    var properties: [CFString: Any] = [:]
    if format == .jpeg { properties[kCGImageDestinationLossyCompressionQuality] = Double(quality ?? 80) / 100 }
    CGImageDestinationAddImage(destination, scaled, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw OpenSimError(code: .internalError, message: "Encode failed") }
    return RenderedScreenshot(data: data as Data, width: width, height: height)
}
```

`SimctlScreenCapture.screens`: chạy `io enumerate`, parse, lấy `Device` qua protocol hẹp `ScreenDeviceReading` (extension `SimctlDeviceService`), lấy profile, trả `ScreenInfo(id: UInt32(index + 1), width, height, scale: main ? profile.scale : 1, rotation: main ? profile.orientation : 0, displayClass)`. **Main display xác định theo `displayClass == 0`**, không theo thứ tự đầu tiên (iPad có thể liệt kê external display trước). `.screenshot` chạy `io screenshot` ra temp PNG, render, chọn đích `out` hoặc `screenshotsDirectory/shot-<uuid>.<ext>`, validate path, ghi file, trả `Screenshot(path:data:nil:format:width:height:scale:capturedAt:)`.

Đo thật 2026-10-20: `simctl io screenshot` headless mất **~41 giây** mỗi lần (cả khi gọi trực tiếp), không phụ thuộc app foreground. `SimctlScreenService` ưu tiên `FramebufferScreenshotter` (SimDeviceScreen.screen.framebufferSurface + CIContext) khi gate render là `ioSurface`; đo được **~0,6 giây**. Simctl vẫn là fallback khi private API không khả dụng.

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift test --filter ScreenLayerTests
```

Expected: PASS; `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge Sources/OpenSimCore Tests/OpenSimBridgeTests/ScreenLayerTests.swift
git commit -m "feat(bridge): add screen enumeration and screenshot capture"
```

---

### Task 5: Recording state và `ScreenControlling` hoàn chỉnh

**Files:**
- Modify: `Sources/OpenSimCore/Protocol/ServiceProtocols.swift`
- Create: `Sources/OpenSimBridge/Screen/RecordingStateStore.swift`, `Sources/OpenSimBridge/Screen/SimctlRecordingController.swift`, `Sources/OpenSimBridge/Services/SimctlScreenService.swift`
- Test: `Tests/OpenSimBridgeTests/RecordingControllerTests.swift`

**Interfaces:**
- Produces: `RecordingControlling`; `RecordingState`; `RecordingStateStore`; `RecordingProcessLaunching`; `RecordingProcessHandle`; `ProcessRecordingLauncher`; `SimctlRecordingController.start/stop/info`; `SimctlScreenService` conform `ScreenControlling`, `RecordingControlling`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class RecordingControllerTests: XCTestCase {
    func testStartStopAndBusy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let handle = FakeRecordingHandle()
        let controller = SimctlRecordingController(
            launcher: FakeRecordingLauncher(handle: handle),
            store: RecordingStateStore(directory: root),
            paths: OpenSimPaths(baseDirectory: root),
            now: { Date(timeIntervalSince1970: 10) }
        )
        let device = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")
        let path = root.appendingPathComponent("a.mov")
        let id = try await controller.start(on: device, to: path.path, codec: .h264)
        try Data("video".utf8).write(to: path)
        handle.finish()
        let result = try await controller.stop(id)
        XCTAssertEqual(result.path, path.path)
        XCTAssertTrue(handle.didReceiveInterrupt)
        do {
            _ = try await controller.start(on: device, to: path.path, codec: .h264)
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "device_busy")
        }
    }
}

final class FakeRecordingHandle: RecordingProcessHandle, @unchecked Sendable {
    let processIdentifier: Int32 = 42_424
    private(set) var didReceiveInterrupt = false
    private var finished = false
    func sendInterrupt() throws { didReceiveInterrupt = true }
    func waitForExit(timeout: Duration) async -> Bool { finished }
    func isRunning() -> Bool { !finished }
    func finish() { finished = true }
}

struct FakeRecordingLauncher: RecordingProcessLaunching {
    let handle: FakeRecordingHandle
    func launch(arguments: [String], path: String) async throws -> any RecordingProcessHandle { handle }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter RecordingControllerTests
```

Expected: FAIL với `cannot find 'RecordingStateStore' in scope`.

- [ ] **Step 3: Viết recording layer**

Thêm vào `ServiceProtocols.swift`:

```swift
public protocol RecordingControlling: Sendable {
    func recordingInfo(_ id: RecordingID) async throws -> RecordingInfo
    func stopRecordingResult(_ id: RecordingID) async throws -> RecordingStopResult
}
```

`RecordingState` gồm `id`, `deviceID`, `path`, `pid`, `codec`, `startedAt`. `RecordingStateStore` là actor: `save` ghi atomic và set `0600`; `load`; `active(for:)` quét JSON, xoá state có PID chết (`kill(pid, 0) == 0` mới còn sống); `remove`.

`SimctlRecordingController` là actor. `start` kiểm tra active recording cùng device trả `device_busy`; chọn path `out` qua `PathPolicy.validateOutputPath` hoặc `recordingsDirectory/<uuid>.mov`; launch `["simctl","io",udid,"recordVideo","--codec=<codec>","--force",path]`; lưu state; trả `RecordingID`. `ProcessRecordingLauncher` dùng `Process`, đọc stderr đến dòng `Recording started` (timeout 15 giây). `stop` gửi SIGINT, đợi tối đa 10 giây, kiểm tra file size > 0, xoá state, trả duration. `info` đọc state.

```swift
public actor RecordingStateStore {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func save(_ state: RecordingState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = fileURL(state.id)
        try OpenSimJSON.encoder(pretty: true).encode(state).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func load(_ id: RecordingID) throws -> RecordingState? {
        let url = fileURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try OpenSimJSON.decoder().decode(RecordingState.self, from: Data(contentsOf: url))
    }

    public func active(for device: DeviceID) throws -> RecordingState? {
        for state in try all() where state.deviceID == device {
            if kill(state.pid, 0) == 0 { return state }
            try? FileManager.default.removeItem(at: fileURL(state.id))
        }
        return nil
    }

    public func all() throws -> [RecordingState] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? OpenSimJSON.decoder().decode(RecordingState.self, from: Data(contentsOf: $0)) }
    }

    public func remove(_ id: RecordingID) throws {
        try? FileManager.default.removeItem(at: fileURL(id))
    }

    private func fileURL(_ id: RecordingID) -> URL {
        directory.appendingPathComponent("\(id.rawValue).json")
    }
}
```

`SimctlScreenService` giữ `SimctlScreenCapture` và `SimctlRecordingController`; chuyển tiếp `screens`, `screenshot`, `startRecording`, `stopRecording`; thêm overload screenshot có `out` cho executor; implement `recordingInfo`, `stopRecordingResult`.

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift test --filter RecordingControllerTests
```

Expected: PASS; `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCore/Protocol/ServiceProtocols.swift Sources/OpenSimBridge/Screen/RecordingStateStore.swift Sources/OpenSimBridge/Screen/SimctlRecordingController.swift Sources/OpenSimBridge/Services/SimctlScreenService.swift Tests/OpenSimBridgeTests/RecordingControllerTests.swift
git commit -m "feat(bridge): add screen recording service"
```

---

### Task 6: Capability gate cho private API

**Files:**
- Create: `Sources/OpenSimBridge/Private/SimulatorKitLoader.swift`, `Sources/OpenSimBridge/Private/CoreSimulatorDeviceLookup.swift`, `Sources/OpenSimBridge/Capabilities/Plan2CapabilityGate.swift`
- Test: `Tests/OpenSimBridgeTests/Plan2CapabilityGateTests.swift`, `Tests/OpenSimBridgeTests/Plan2GateProbeTests.swift`
- Create: `docs/superpowers/spikes/2026-10-20-plan2-capability-gate.md`

**Interfaces:**
- Produces: `SimulatorKitClassChecking`; `SimulatorKitLoader.live/hasClass/responds/indigoSymbols/sendSelectors`; `CoreSimulatorDeviceLookup.device`; `RenderBackend`; `InputBackend`; `AccessibilityBackend`; `Plan2Capabilities`; `Plan2CapabilityGate.evaluate(checker:helperConfigured:)`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

private struct Checker: SimulatorKitClassChecking {
    var classes: Set<String> = []
    var selectors: Set<String> = []
    var symbols: [String] = []
    var sends: [String] = []
    func hasClass(_ name: String) -> Bool { classes.contains(name) }
    func responds(_ className: String, _ selector: String) -> Bool { selectors.contains("\(className).\(selector)") }
    func indigoSymbols() -> [String] { symbols }
    func sendSelectors(className: String) -> [String] { sends }
}

final class Plan2CapabilityGateTests: XCTestCase {
    func testPrimaryNeedsDisplaySelectorsAndAccessibilityGetter() {
        var checker = Checker()
        checker.classes = ["SimServiceContext", "SimDisplayView", "SimDeviceScreen", "SimAccessibilityManager"]
        checker.selectors = ["SimDisplayView.setDevice:", "SimDisplayView.connectedScreen", "SimDisplayView.pixelSize", "SimDeviceScreen.screen", "SimAccessibilityManager.rootElement"]
        let result = Plan2CapabilityGate.evaluate(checker: checker, helperConfigured: true)
        XCTAssertEqual(result.render, .simDisplayView)
        XCTAssertEqual(result.input, .simulatorKit)
        XCTAssertEqual(result.accessibility, .simAccessibilityManager)
    }

    func testFallbacksAndUnavailable() {
        var checker = Checker()
        checker.classes = ["SimServiceContext", "SimDeviceScreen"]
        checker.selectors = ["SimDeviceScreen.screen"]
        XCTAssertEqual(Plan2CapabilityGate.evaluate(checker: checker, helperConfigured: true).render, .ioSurface)
        XCTAssertEqual(Plan2CapabilityGate.evaluate(checker: Checker(), helperConfigured: true).render, .screenshotPolling)
        XCTAssertEqual(Plan2CapabilityGate.evaluate(checker: Checker(), helperConfigured: false).input, .unavailable)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter Plan2CapabilityGateTests
```

Expected: FAIL với `cannot find 'Plan2CapabilityGate' in scope`.

- [ ] **Step 3: Viết loader và gate**

`SimulatorKitLoader` dùng `XcodeLocator` + `FrameworkLocator`, `dlopen` cả `CoreSimulator` và `SimulatorKit` (binary `SimulatorKit.framework/Versions/A/SimulatorKit`) với `RTLD_LAZY | RTLD_LOCAL`. Class lookup thử `NSClassFromString(name)` trước (cho `SimServiceContext`), rồi `SimulatorKit.<name>`, rồi mangled name Plan 0 (`_TtC12SimulatorKit14SimDisplayView`, `_TtC12SimulatorKit15SimDeviceScreen`, `_TtC12SimulatorKit24SimDeviceLegacyHIDClient`, `_TtC12SimulatorKit23SimAccessibilityManager`). `CoreSimulatorDeviceLookup` cũng `dlopen` CoreSimulator trước khi lấy class. `responds` dùng `class_getInstanceMethod`/`class_getClassMethod`, không invoke. `indigoSymbols()` chạy `/usr/bin/nm -gU <binary>` và lọc prefix `IndigoHIDMessageFor`. `sendSelectors` đọc method list, lọc tên bắt đầu `send`.

`CoreSimulatorDeviceLookup` gọi đúng selector Plan 0 bằng IMP: `sharedServiceContextForDeveloperDir:error:` (truyền nil error), `defaultDeviceSetWithError:`, `devices`, đọc KVC `UDID`; trả `AnyObject` hoặc `device_not_found`/`private_api_unavailable`.

`Plan2Capabilities`:

```swift
public struct Plan2Capabilities: Codable, Sendable, Equatable {
    public var render: RenderBackend
    public var input: InputBackend
    public var accessibility: AccessibilityBackend
    public var multiTouch: Capability
    public var hardwareButtons: Capability
    public var notes: [String: String]
}
```

`Plan2CapabilityGate.evaluate`:

```swift
public static let accessibilitySelectors = [
    "rootElement", "accessibilityElement", "accessibilityTree",
    "snapshot", "elements", "elementAtPoint:",
]

public static func evaluate(checker: (any SimulatorKitClassChecking)?, helperConfigured: Bool) -> Plan2Capabilities {
    let core = checker?.hasClass("SimServiceContext") == true
    let displays = core
        && checker?.hasClass("SimDisplayView") == true
        && checker?.responds("SimDisplayView", "setDevice:") == true
        && checker?.responds("SimDisplayView", "connectedScreen") == true
        && checker?.responds("SimDisplayView", "pixelSize") == true
    let surfaces = core
        && checker?.hasClass("SimDeviceScreen") == true
        && checker?.responds("SimDeviceScreen", "screen") == true
    let render: RenderBackend = displays ? .simDisplayView : (surfaces ? .ioSurface : .screenshotPolling)
    let input: InputBackend = supportsDTUHID
        ? .dtuhid
        : (displays ? .simulatorKit : (helperConfigured ? .xcuiTest : .unavailable))
    let manager = checker?.hasClass("SimAccessibilityManager") == true
        && accessibilitySelectors.contains { checker?.responds("SimAccessibilityManager", $0) == true }
    let accessibility: AccessibilityBackend = manager ? .simAccessibilityManager : (helperConfigured ? .xcuiTest : .unavailable)
    let sends = checker?.sendSelectors(className: "SimDeviceLegacyHIDClient") ?? []
    let symbols = checker?.indigoSymbols() ?? []
    return Plan2Capabilities(
        render: render,
        input: input,
        accessibility: accessibility,
        multiTouch: symbols.isEmpty ? .unavailable : .unknown,
        hardwareButtons: sends.isEmpty ? .unavailable : .unknown,
        notes: [
            "render": render.rawValue,
            "input": input.rawValue,
            "accessibility": accessibility.rawValue,
            "indigoSymbolCount": String(symbols.count),
            "legacyHIDSendSelectors": sends.joined(separator: ","),
        ]
    )
}
```

`Plan2GateProbeTests` chạy khi `OPENSIM_GATE=1`, in JSON `PLAN2_GATE`, `PLAN2_INDIGO`, `PLAN2_SEND`. Ghi nguyên văn vào gate report, kèm máy/Xcode/runtime và các dòng Plan 0 nếu có. `multiTouch`/`hardwareButtons` chỉ chuyển `available` sau integration Task 15.

- [ ] **Step 4: Chạy gate**

```bash
swift test --filter Plan2CapabilityGateTests
OPENSIM_GATE=1 swift test --filter Plan2GateProbeTests
```

Expected: unit test PASS; probe in JSON và symbol/selector thật. Report ghi `unknown` khi chưa có bằng chứng, không suy diễn.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Private Sources/OpenSimBridge/Capabilities Tests/OpenSimBridgeTests/Plan2CapabilityGateTests.swift Tests/OpenSimBridgeTests/Plan2GateProbeTests.swift docs/superpowers/spikes/2026-10-20-plan2-capability-gate.md
git commit -m "feat(bridge): add plan 2 capability gate"
```

---

### Task 7 (RETIRED — Plan 0 override): `DisplaySurface` primary, gesture planner và keyboard map

> Không implement section này. `SimDisplayView.connectedScreen`/`pixelSize`/`unmaskedSurface` không tồn tại trên Xcode 27.1; dùng Task 9. Giữ `InputGesturePlanner`/`KeyboardMap` nếu Task 10 cần, nhưng không dùng digitizer làm primary.

**Files:**
- Create: `Sources/OpenSimBridge/Screen/DisplaySurface.swift`, `Sources/OpenSimBridge/Screen/SimDisplaySurface.swift`, `Sources/OpenSimBridge/Input/InputGesturePlanner.swift`, `Sources/OpenSimBridge/Input/KeyboardMap.swift`
- Test: `Tests/OpenSimBridgeTests/InputTests.swift`

**Interfaces:**
- Produces: `DisplaySurface`; `SimDisplaySurface.isSupported/connect/disconnect/interactionView`; `TouchPhase`; `TouchSample`; `GesturePlan`; `MagnifyPlan`; `RotatePlan`; `InputGesturePlanner`; `KeyboardStroke`; `KeyboardMap`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class InputTests: XCTestCase {
    func testGesturePlans() {
        let tap = InputGesturePlanner.tap(at: Point(x: 10, y: 20))
        XCTAssertEqual(tap.samples.map(\.phase), [.began, .ended])
        let swipe = InputGesturePlanner.swipe(from: Point(x: 0, y: 0), to: Point(x: 100, y: 200), durationMs: 200)
        XCTAssertEqual(swipe.samples.last?.point, Point(x: 100, y: 200))
        let pinch = InputGesturePlanner.pinch(center: Point(x: 1, y: 1), scale: 2, durationMs: 100)
        XCTAssertEqual(pinch.reduce(0) { $0 + $1.magnification }, 1, accuracy: 0.001)
    }

    func testKeyboardMap() throws {
        XCTAssertEqual(try XCTUnwrap(KeyboardMap.stroke(for: "a")).keyCode, 0)
        XCTAssertTrue(try XCTUnwrap(KeyboardMap.stroke(for: "A")).modifiers.shift)
        XCTAssertEqual(try XCTUnwrap(KeyboardMap.stroke(forKey: "return")).keyCode, 36)
        XCTAssertNil(KeyboardMap.stroke(for: "é"))
    }

    func testSurfaceSupportSelectors() {
        var checker = SurfaceChecker()
        checker.classes = ["SimDisplayView"]
        checker.selectors = ["SimDisplayView.setDevice:", "SimDisplayView.connectedScreen", "SimDisplayView.pixelSize"]
        XCTAssertTrue(SimDisplaySurface.isSupported(checker: checker))
        checker.selectors.remove("SimDisplayView.setDevice:")
        XCTAssertFalse(SimDisplaySurface.isSupported(checker: checker))
    }
}

struct SurfaceChecker: SimulatorKitClassChecking {
    var classes: Set<String> = []
    var selectors: Set<String> = []
    func hasClass(_ name: String) -> Bool { classes.contains(name) }
    func responds(_ className: String, _ selector: String) -> Bool { selectors.contains("\(className).\(selector)") }
    func indigoSymbols() -> [String] { [] }
    func sendSelectors(className: String) -> [String] { [] }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter InputTests
```

Expected: FAIL với `cannot find 'InputGesturePlanner' in scope`.

- [ ] **Step 3: Viết surface, planner và keyboard**

`DisplaySurface` là protocol `@MainActor`, `AnyObject`: `view`, `pixelSize`, `screenScale`, `onSizeChange`, `onError`, `connect`, `disconnect`.

`SimDisplaySurface` tạo `SimDisplayView` động bằng `alloc` + IMP `initWithFrame:` (không dùng selector mới), gọi `setDevice:` qua `perform`, chờ `connectedScreen` + `pixelSize` tối đa 5 giây, poll size mỗi 500 ms. `isSupported` kiểm tra đúng ba selector. `disconnect` cancel task, remove view.

```swift
public func connect() async throws {
    guard let viewClass = NSClassFromString("SimulatorKit.SimDisplayView") ?? NSClassFromString("_TtC12SimulatorKit14SimDisplayView") else {
        throw OpenSimError(code: .privateApiUnavailable, message: "SimDisplayView is missing")
    }
    let deviceObject = try lookup.device(device)
    guard let allocated = (viewClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeRetainedValue(),
          let method = class_getInstanceMethod(viewClass, NSSelectorFromString("initWithFrame:")) else {
        throw OpenSimError(code: .privateApiUnavailable, message: "SimDisplayView cannot be created")
    }
    typealias InitFn = @convention(c) (AnyObject, Selector, CGRect) -> AnyObject
    let initFn = unsafeBitCast(method_getImplementation(method), to: InitFn.self)
    let display = initFn(allocated, NSSelectorFromString("initWithFrame:"), view.bounds)
    guard let displayView = display as? NSView else {
        throw OpenSimError(code: .privateApiUnavailable, message: "SimDisplayView is not an NSView")
    }
    displayView.autoresizingMask = [.width, .height]
    interactionView = displayView
    view.addSubview(displayView)
    _ = displayView.perform(NSSelectorFromString("setDevice:"), with: deviceObject)
    guard await waitForConnection(displayView) else {
        throw OpenSimError(code: .privateApiUnavailable, message: "SimDisplayView did not connect")
    }
}
```

`InputGesturePlanner`: tap `[began, ended]` delay 80; swipe 20 bước; drag 30 bước; long-press delay duration; pinch 10 bước tổng `scale - 1`; rotate 10 bước tổng `angle`.

`KeyboardMap` map chữ thường keyCode 0,1,2,3,4,5,6,7,8,9,11,12,13,14,15,16,17,31,32,34,35,37,38,40,45,46; chữ số 18,19,20,21,23,22,26,28,25,29; dấu câu US; named `return/enter` 36, `tab` 48, `space` 49, `delete/backspace` 51, `escape` 53, mũi tên 123-126, `home` 115, `end` 119; uppercase bật shift; ký tự ngoài map trả nil.

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift test --filter InputTests
```

Expected: PASS; `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Screen/DisplaySurface.swift Sources/OpenSimBridge/Screen/SimDisplaySurface.swift Sources/OpenSimBridge/Input Tests/OpenSimBridgeTests/InputTests.swift
git commit -m "feat(bridge): add display surface and input primitives"
```

---

### Task 8 (RETIRED — Plan 0 override): Primary input qua digitizer và composite routing

> Không implement section này. `NSApp`/`mouseDown` trên `SimDisplayView` không tới device trong Plan 0; HID target chưa xác minh. Dùng XCUITest helper ở Task 10.

**Files:**
- Create: `Sources/OpenSimBridge/Input/ViewEventInputService.swift`, `Sources/OpenSimBridge/Input/CompositeInputService.swift`
- Test: `Tests/OpenSimBridgeTests/CompositeInputTests.swift`

**Interfaces:**
- Produces: `HardwareButtonHandling`; `KeyboardSupplement`; `ViewEventInputService` conform `InputControlling`; `CompositeInputService` với `primaryMultiTouch`, `primaryHardwareButtons`. Nếu gate report xác minh `IndigoHIDMessageForKeyboardNSEvent` và một selector `send` của `SimDeviceLegacyHIDClient`, ViewEventInputService nhận thêm supplement conform `KeyboardSupplement`; nếu không, dùng `NSEvent` key events và ghi `indigoKeyboard=unavailable` trong gate report. Không viết call shape suy đoán.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

private actor Recorder {
    private(set) var values: [String] = []
    func add(_ value: String) { values.append(value) }
}

private struct StubInput: InputControlling {
    let name: String
    let recorder: Recorder
    func tap(on device: DeviceID, at point: Point, settle: Bool) async throws { await recorder.add("\(name):tap") }
    func swipe(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {}
    func longPress(on device: DeviceID, at point: Point, durationMs: Int) async throws {}
    func drag(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {}
    func pinch(on device: DeviceID, center: Point, scale: Double, durationMs: Int) async throws { await recorder.add("\(name):pinch") }
    func rotate(on device: DeviceID, center: Point, angle: Double, durationMs: Int) async throws {}
    func scroll(on device: DeviceID, deltaX: Double, deltaY: Double, at point: Point?) async throws {}
    func typeText(on device: DeviceID, text: String) async throws {}
    func key(on device: DeviceID, key: Key, modifiers: KeyModifiers) async throws {}
    func button(on device: DeviceID, button: HardwareButton) async throws { await recorder.add("\(name):button") }
}

final class CompositeInputTests: XCTestCase {
    func testRoutesUnsupportedOperationsToFallback() async throws {
        let recorder = Recorder()
        let service = CompositeInputService(
            primary: StubInput(name: "primary", recorder: recorder),
            fallback: StubInput(name: "fallback", recorder: recorder),
            primaryMultiTouch: false,
            primaryHardwareButtons: false
        )
        let device = DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC")
        try await service.tap(on: device, at: Point(x: 1, y: 2), settle: false)
        try await service.pinch(on: device, center: Point(x: 1, y: 1), scale: 2, durationMs: 100)
        try await service.button(on: device, button: .home)
        let values = await recorder.values
        XCTAssertEqual(values, ["primary:tap", "fallback:pinch", "fallback:button"])
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter CompositeInputTests
```

Expected: FAIL với `cannot find 'CompositeInputService' in scope`.

- [ ] **Step 3: Viết input service**

`KeyboardSupplement`:

```swift
public protocol KeyboardSupplement: Sendable {
    func send(key: Key, modifiers: KeyModifiers, on device: DeviceID) async throws
}
```

`CompositeInputService` chuyển tap/swipe/long-press/drag/scroll/type/key cho primary; `pinch`/`rotate` dùng primary nếu `primaryMultiTouch`, ngược lại fallback, ngược lại `capability_unavailable("multi_touch")`; `button` tương tự với `hardware_button`.

`ViewEventInputService` giữ dictionary `[DeviceID: SimDisplayInputHost]`. `host(for:)` gọi `screen.screens`, chọn displayClass 0, tính point size = pixel / scale, tạo `SimDisplaySurface`, connect, tạo borderless `NSWindow` alpha 0, gắn surface.view, `makeFirstResponder(displayView)`.

`SimDisplayInputHost`:

- `send(sample:)` tạo `NSEvent.mouseEvent` `.leftMouseDown/.leftMouseDragged/.leftMouseUp`, gọi trực tiếp `mouseDown/mouseDragged/mouseUp`.
- `send(stroke:)` tạo keyDown/keyUp với `NSEvent.ModifierFlags` từ `KeyModifiers`, gọi `keyDown/keyUp`.
- `sendMagnify`/`sendRotation` dùng `NSEvent.otherEvent` `.magnify`/`.rotate`, gọi `magnify(with:)`/`rotate(with:)`; chỉ dùng khi gate `multiTouch` available.
- `sendScroll` tạo `CGEvent(scrollWheelEvent2Source:units:.pixel,wheelCount:2,wheel1:deltaY,wheel2:deltaX,wheel3:0)`, bọc `NSEvent(cgEvent:)`, gọi `scrollWheel(with:)`.
- `viewPoint` đổi point top-left sang view bottom-left: `x = point.x / pointWidth * bounds.width`, `y = (1 - point.y / pointHeight) * bounds.height`.

`typeText` map từng ký tự qua `KeyboardMap`; ký tự không map trả `input_failed` với details `character`; `key` map tên + modifier; `button` chỉ gọi `HardwareButtonHandling` nếu được inject, ngược lại `capability_unavailable`.

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift test --filter CompositeInputTests
```

Expected: PASS; `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Input/ViewEventInputService.swift Sources/OpenSimBridge/Input/CompositeInputService.swift Tests/OpenSimBridgeTests/CompositeInputTests.swift
git commit -m "feat(bridge): add digitizer input and composite routing"
```

---

### Task 9: Framebuffer display surface (primary — Plan 0 override)

> Plan 0: dùng `SimDeviceScreen(screenID: 1).screen.framebufferSurface` (IOSurface), không dùng `SimDisplayView`/`unmaskedSurface`. Nội dung code bên dưới được cập nhật theo hướng này trước khi implement.

**Files:**
- Create: `Sources/OpenSimBridge/Screen/DisplaySurface.swift`, `Sources/OpenSimBridge/Screen/IOSurfaceDisplaySurface.swift`
- Test: `Tests/OpenSimBridgeTests/FallbackTests.swift`

> `DisplaySurface` được tạo ở đây vì Task 7 đã retired; Task 10 và Task 13 dùng protocol này.

**Interfaces:**
- Produces: `IOSurfaceDisplaySurface.isSupported/connect/disconnect`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimBridge

final class FallbackTests: XCTestCase {
    func testIOSurfaceSupport() {
        var checker = SurfaceChecker()
        checker.classes = ["SimServiceContext", "SimDeviceScreen"]
        checker.selectors = ["SimDeviceScreen.screen"]
        XCTAssertTrue(IOSurfaceDisplaySurface.isSupported(checker: checker))
        checker.selectors = []
        XCTAssertFalse(IOSurfaceDisplaySurface.isSupported(checker: checker))
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter FallbackTests
```

Expected: FAIL với `cannot find 'IOSurfaceDisplaySurface' in scope`.

- [ ] **Step 3: Viết IOSurface surface**

`connect` lấy `SimDeviceScreen` object qua `initWithDevice:screenID:` (screenID 1) bằng IMP, đọc `.screen`, rồi gọi `framebufferSurface` trên proxy (dynamic forwarding), chuyển IOSurface sang `CGImage` bằng `CIContext` rồi gán `view.layer.contents`, `contentsGravity = .resizeAspect`; refresh bằng `NSView.displayLink` 60 Hz (fallback task 16 ms khi view chưa có window), không dùng task 33 ms; `pixelSize` từ `IOSurfaceGetWidth/Height`; `screenScale` từ `ScreenControlling.screens`. `isSupported` yêu cầu `SimDeviceScreen` class, selector `screen`, và `SimServiceContext` class. Lỗi thiếu API trả `private_api_unavailable`.

Gán trực tiếp IOSurface vào `layer.contents` làm process crash (`swift_unknownObjectRelease`, SIGTRAP) trên macOS 27.0.1; đường CGImage đã được kiểm chứng bằng integration test kết nối simulator thật. Giữ strong reference tới IOSurface trong surface và clear layer trước khi thả ở `disconnect`.

```swift
public func connect() async throws {
    guard let screenClass = NSClassFromString("SimulatorKit.SimDeviceScreen")
        ?? NSClassFromString("_TtC12SimulatorKit15SimDeviceScreen") else {
        throw OpenSimError(code: .privateApiUnavailable, message: "SimDeviceScreen is missing")
    }
    let deviceObject = try lookup.device(device)
    guard let allocated = (screenClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeRetainedValue(),
          let method = class_getInstanceMethod(screenClass, NSSelectorFromString("initWithDevice:screenID:")) else {
        throw OpenSimError(code: .privateApiUnavailable, message: "SimDeviceScreen cannot be created")
    }
    typealias InitFn = @convention(c) (AnyObject, Selector, AnyObject, UInt32) -> AnyObject
    let initFn = unsafeBitCast(method_getImplementation(method), to: InitFn.self)
    screenObject = initFn(allocated, NSSelectorFromString("initWithDevice:screenID:"), deviceObject, 1)
    updateSurface()
    refreshTask = Task { @MainActor [weak self] in
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            self?.updateSurface()
        }
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift test --filter FallbackTests
```

Expected: PASS; `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Screen/IOSurfaceDisplaySurface.swift Tests/OpenSimBridgeTests/FallbackTests.swift
git commit -m "feat(bridge): add iosurface display fallback"
```

---

### Task 10: Fallback B — screenshot polling và XCUITest helper

**Files:**
- Create: `Sources/OpenSimBridge/Screen/ScreenshotPollingSurface.swift`, `Sources/OpenSimBridge/XCUITest/XCUITestSnapshotMapper.swift`, `Sources/OpenSimBridge/XCUITest/XCUITestHelperRunner.swift`, `Sources/OpenSimBridge/Services/XCUITestAccessibilityService.swift`, `Sources/OpenSimBridge/Services/XCUITestInputService.swift`, `Fixtures/OpenSimFixture/UITests/OpenSimFixtureUITests.swift`
- Test: `Tests/OpenSimBridgeTests/FallbackTests.swift`

**Interfaces:**
- Produces: `ScreenshotPollingSurface`; `HelperNode`; `XCUITestSnapshotMapper.toUIElement/limited`; `XCUITestHelperAction`; `XCUITestHelperResponse`; `XCUITestHelperRunner.isConfigured/run`; `XCUITestAccessibilityService`; `XCUITestInputService`.

- [ ] **Step 1: Viết test thất bại**

Thêm vào `FallbackTests`:

```swift
    func testSnapshotMapper() {
        let node = HelperNode(
            role: "button", identifier: "fixture-primary-button", label: "Primary Action", value: nil,
            x: 10, y: 20, width: 100, height: 44, enabled: true, selected: false, children: []
        )
        let element = XCUITestSnapshotMapper.toUIElement(node, path: "0")
        XCTAssertEqual(element.identifier, "fixture-primary-button")
        XCTAssertEqual(element.frame.height, 44)
        let tree = XCUITestSnapshotMapper.limited(element, maxDepth: 0, maxNodes: 5)
        XCTAssertTrue(tree.truncated)
    }
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter FallbackTests
```

Expected: FAIL với `cannot find 'HelperNode' in scope`.

- [ ] **Step 3: Viết fallback B**

`ScreenshotPollingSurface` là `NSImageView`; `connect` poll ngay rồi task 100 ms gọi `screen.screenshot`, load `NSImage`, cập nhật `pixelSize`; 3 lỗi liên tiếp gọi `onError(capability_unavailable("screen_polling"))` và dừng.

`HelperNode` Codable gồm `role`, `identifier`, `label`, `value`, `x`, `y`, `width`, `height`, `enabled`, `selected`, `children`. `XCUITestSnapshotMapper.toUIElement` tạo id `xct-<path>`, map frame; `limited` cắt depth/node và đặt `truncated`.

`OpenSimFixtureUITests.testHelper`: đọc env `OPENSIM_HELPER_ACTION`, `OPENSIM_HELPER_BUNDLE_ID`, `OPENSIM_HELPER_IDENTIFIER`, `OPENSIM_HELPER_X/Y`, `OPENSIM_HELPER_FROMX/FROMY`, `OPENSIM_HELPER_TOX/TOY`, `OPENSIM_HELPER_DURATION_MS`, `OPENSIM_HELPER_TEXT`, `OPENSIM_HELPER_SCALE`, `OPENSIM_HELPER_ANGLE`, `OPENSIM_HELPER_DX/DY`, `OPENSIM_HELPER_KEY`, `OPENSIM_HELPER_MODIFIER_*`, `OPENSIM_HELPER_BUTTON`; `XCUIApplication(bundleIdentifier:)`, `activate`; action `tree` dùng `try app.snapshot()` đệ quy (depth tối đa 30), `tapIdentifier` dùng `descendants(matching:.any).matching(identifier:).firstMatch.tap()`, `tapPoint`/`scroll` dùng coordinate, `typeText`, `swipe`/`drag`/`longPress`, `pinch`, `rotate`, `key` dùng `app.typeKey(_:modifierFlags:)`, `button` chỉ hỗ trợ `home` bằng `XCUIDevice.shared.press(.home)`; in `OPENSIM_HELPER_RESULT:<base64 JSON>`.

Xcode 27.1 đổi `XCUIKeyModifierFlags` thành `XCUIElement.KeyModifierFlags` và `app.snapshot()` thành throwing; fixture đã cập nhật theo API này.

```swift
func testHelper() throws {
    let env = ProcessInfo.processInfo.environment
    guard let action = env["OPENSIM_HELPER_ACTION"], let bundleID = env["OPENSIM_HELPER_BUNDLE_ID"] else { return }
    let app = XCUIApplication(bundleIdentifier: bundleID)
    if app.state != .runningForeground { app.activate() }
    switch action {
    case "tree":
        emit(Result(ok: true, error: nil, node: snapshot(app)))
    case "tap-id":
        let element = app.descendants(matching: .any).matching(identifier: env["OPENSIM_HELPER_IDENTIFIER"] ?? "").firstMatch
        if element.waitForExistence(timeout: 5) { element.tap(); emit(Result(ok: true, error: nil, node: nil)) }
        else { emit(Result(ok: false, error: "element not found", node: nil)) }
    case "pinch":
        app.pinch(withScale: CGFloat(Double(env["OPENSIM_HELPER_SCALE"] ?? "2") ?? 2), velocity: 1)
        emit(Result(ok: true, error: nil, node: nil))
    case "rotate":
        app.rotate(CGFloat(Double(env["OPENSIM_HELPER_ANGLE"] ?? "90") ?? 90), withVelocity: 1)
        emit(Result(ok: true, error: nil, node: nil))
    case "home":
        XCUIDevice.shared.press(.home)
        emit(Result(ok: true, error: nil, node: nil))
    default:
        emit(Result(ok: false, error: "unknown action", node: nil))
    }
}
```

`XCUITestHelperRunner` kiểm tra `xcodegen` + `Fixtures/OpenSimFixture/project.yml`; `build-for-testing` vào cache `~/Library/Caches/OpenSim/xcuitest`. Runner là actor giữ **một persistent session cho mỗi cặp device + bundle ID**:

- Fixture có thêm `testHelperServer`: đọc `OPENSIM_HELPER_SERVER_PORT`/`OPENSIM_HELPER_BUNDLE_ID`, kết nối TCP `127.0.0.1`, gửi `{"ready":true}`, nhận JSON line action, trả JSON response, thoát khi nhận `quit`; `executionTimeAllowance = 3600`.
- Runner copy `.xctestrun` vào cùng thư mục `Build/Products` (vì `__TESTROOT__` resolve theo vị trí file), inject env server, mở listener loopback, chạy `xcodebuild test-without-building ... testHelperServer` một lần, chờ kết nối và handshake, rồi gửi action qua socket.
- Startup ~30–50 giây; mỗi action sau đó nhanh (tree/tap vài trăm ms đến vài giây). Đo thật: startup + tree + tap + tree = **46–53 giây**, counter đổi từ 0 → 1 trong cùng session.
- Session kết thúc khi CLI process thoát hoặc gọi `shutdown`; lúc đó xcodebuild shutdown simulator. Vì vậy state chỉ được giữ trong một process; command CLI riêng lẻ cần daemon Plan 3, còn batch `ui act` và integration test dùng một session.

`XCUITestHelperAction`/`Response` vẫn là contract; runner `run` yêu cầu `bundleID`, thiếu thì `invalid_argument`. Fixture vẫn giữ `testHelper` một lần chạy (env) để debug.

Cache build dùng stamp mtime của fixture để tránh `build-for-testing` lại mỗi lần. Lần chạy thật đầu tiên mất khoảng 130 giây (app build + test build + 2 helper invocation); các lần sau nhanh hơn nhưng mỗi action vẫn là một lần xcodebuild.

`XCUITestAccessibilityService.tree` gọi helper `tree`, map, giới hạn; `find` dùng `UIElementMatcher`. `XCUITestInputService` map point sang `coordinate(withNormalizedOffset:)` trên app; `pinch`/`rotate` gọi helper; `button` chỉ hỗ trợ `.home`, còn lại `capability_unavailable`. Cả hai đọc bundle ID từ init hoặc env `OPENSIM_XCUITEST_BUNDLE_ID`; thiếu bundle ID thì service không được tạo. Cả hai chỉ được tạo khi helper configured; fallback test skip khi primary active.

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift test --filter FallbackTests
```

Expected: PASS; snapshot test chạy, helper integration skip nếu thiếu fixture/`OPENSIM_INTEGRATION`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Screen/ScreenshotPollingSurface.swift Sources/OpenSimBridge/XCUITest Sources/OpenSimBridge/Services/XCUITestAccessibilityService.swift Sources/OpenSimBridge/Services/XCUITestInputService.swift Fixtures/OpenSimFixture/UITests Tests/OpenSimBridgeTests/FallbackTests.swift
git commit -m "feat(bridge): add screenshot polling and xcuitest fallback"
```

---

### Task 11 (RETIRED — Plan 0 override): Primary accessibility qua `SimAccessibilityManager`

> Không implement section này. Plan 0 xác nhận `accessibilityChildren=nil` và không có tree getter; dùng XCUITest helper ở Task 10.

**Files:**
- Create: `Sources/OpenSimBridge/Accessibility/UIElementTreeBuilder.swift`, `Sources/OpenSimBridge/Accessibility/SimAccessibilityService.swift`
- Test: `Tests/OpenSimBridgeTests/AccessibilityTreeTests.swift`

**Interfaces:**
- Produces: `UIElementTreeBuilder.build(root:maxDepth:maxNodes:)`; `SimAccessibilityService` conform `AccessibilityReading`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class FakeAccessibilityNode: NSObject {
    @objc dynamic var role: String
    @objc dynamic var label: String?
    @objc dynamic var identifier: String?
    @objc dynamic var value: String?
    @objc dynamic var enabled: Bool = true
    @objc dynamic var selected: Bool = false
    @objc dynamic var children: [FakeAccessibilityNode]
    @objc dynamic var frame: NSValue

    init(role: String, identifier: String, children: [FakeAccessibilityNode] = []) {
        self.role = role
        self.label = identifier
        self.identifier = identifier
        self.value = nil
        self.children = children
        self.frame = NSValue(rect: NSRect(x: 0, y: 0, width: 10, height: 20))
    }
}

final class AccessibilityTreeTests: XCTestCase {
    func testBuildAndLimit() {
        let root = FakeAccessibilityNode(role: "application", identifier: "app", children: [
            FakeAccessibilityNode(role: "button", identifier: "one"),
            FakeAccessibilityNode(role: "button", identifier: "two"),
        ])
        let tree = UIElementTreeBuilder().build(root: root, maxDepth: 10, maxNodes: 2)
        XCTAssertEqual(tree.nodeCount, 2)
        XCTAssertTrue(tree.truncated)
        XCTAssertEqual(tree.root.children.count, 1)
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter AccessibilityTreeTests
```

Expected: FAIL với `cannot find 'UIElementTreeBuilder' in scope`.

- [ ] **Step 3: Viết tree builder và service**

`UIElementTreeBuilder` đọc KVC key `role`, `label`, `identifier`, `value`, `frame`, `enabled`, `selected`, `children`; frame nhận `NSValue.rectValue`; id là `a11y-<path>`; pre-order; dừng khi `count >= maxNodes` hoặc `depth >= maxDepth`, đặt `truncated`. Root lỗi trả element rỗng.

```swift
public struct UIElementTreeBuilder {
    public init() {}

    public func build(root: AnyObject, maxDepth: Int, maxNodes: Int) -> UITree {
        var count = 0
        var truncated = false
        func visit(_ object: AnyObject, path: String, depth: Int) -> UIElement? {
            guard count < maxNodes else { truncated = true; return nil }
            count += 1
            let children: [UIElement]
            if depth >= maxDepth {
                truncated = true
                children = []
            } else {
                let raw = object.value(forKey: "children") as? [AnyObject] ?? []
                children = raw.enumerated().compactMap { index, child in
                    visit(child, path: "\(path).\(index)", depth: depth + 1)
                }
            }
            let frame = (object.value(forKey: "frame") as? NSValue)?.rectValue ?? .zero
            return UIElement(
                id: "a11y-\(path)",
                role: (object.value(forKey: "role") as? String) ?? "unknown",
                label: object.value(forKey: "label") as? String,
                identifier: object.value(forKey: "identifier") as? String,
                value: object.value(forKey: "value") as? String,
                frame: Rect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height),
                enabled: (object.value(forKey: "enabled") as? Bool) ?? true,
                selected: (object.value(forKey: "selected") as? Bool) ?? false,
                children: children
            )
        }
        guard let element = visit(root, path: "0", depth: 0) else {
            return UITree(root: UIElement(id: "a11y-0", role: "unknown", label: nil, identifier: nil, value: nil, frame: Rect(x: 0, y: 0, width: 0, height: 0), enabled: false, selected: false, children: []), nodeCount: count, truncated: true)
        }
        return UITree(root: element, nodeCount: count, truncated: truncated)
    }
}
```

`SimAccessibilityService` tạo manager bằng `new`, thử getter theo thứ tự `rootElement`, `accessibilityElement`, `accessibilityTree`, `snapshot`, `elements`, `elementAtPoint:` (chỉ gọi getter không tham số; `elementAtPoint:` bỏ qua trong tree), build tree. Không có manager/getter trả `a11y_unavailable`; lỗi runtime trả `private_api_unavailable`. `find` build tree với `maxDepth 30`, `maxNodes 1500` rồi `UIElementMatcher.find`. Thêm init `__test(tree:)` cho unit test.

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift test --filter AccessibilityTreeTests
```

Expected: PASS; `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Accessibility Tests/OpenSimBridgeTests/AccessibilityTreeTests.swift
git commit -m "feat(bridge): add simulator accessibility tree service"
```

---

### Task 12: `SimctlBridge` wiring, `UIAutomationService` và executor

**Files:**
- Create: `Sources/OpenSimBridge/Services/UIAutomationService.swift`
- Modify: `Sources/OpenSimBridge/SimctlBridge.swift`, `Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift`, `Sources/OpenSimBridge/Environment/CapabilityEvaluator.swift`, `Sources/OpenSimBridge/Environment/DoctorService.swift`, `Sources/OpenSimCLI/Runtime/CLIRuntime.swift`
- Test: `Tests/OpenSimBridgeTests/UIAutomationServiceTests.swift`

**Interfaces:**
- Produces: `SimulatorScreenDisplaying`; `SimctlBridge.init` nhận thêm `screen`, `input`, `accessibility`, `displaySurfaceFactory`; `makeDisplaySurface`; `UIAutomationService.tap/wait/act/find`; executor case `screen_*`, `ui_*`.

- [ ] **Step 1: Viết test thất bại**

```swift
import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

private struct FakeAccessibility: AccessibilityReading {
    let tree: UITree
    func tree(on device: DeviceID, maxDepth: Int, maxNodes: Int) async throws -> UITree { tree }
    func find(on device: DeviceID, selector: ElementSelector) async throws -> [UIElement] {
        UIElementMatcher.find(in: tree.root, selector: selector)
    }
}

private actor TapRecorder {
    private(set) var points: [Point] = []
    func add(_ point: Point) { points.append(point) }
}

private struct FakeInput: InputControlling {
    let recorder: TapRecorder
    func tap(on device: DeviceID, at point: Point, settle: Bool) async throws { await recorder.add(point) }
    func swipe(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {}
    func longPress(on device: DeviceID, at point: Point, durationMs: Int) async throws {}
    func drag(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws {}
    func pinch(on device: DeviceID, center: Point, scale: Double, durationMs: Int) async throws {}
    func rotate(on device: DeviceID, center: Point, angle: Double, durationMs: Int) async throws {}
    func scroll(on device: DeviceID, deltaX: Double, deltaY: Double, at point: Point?) async throws {}
    func typeText(on device: DeviceID, text: String) async throws {}
    func key(on device: DeviceID, key: Key, modifiers: KeyModifiers) async throws {}
    func button(on device: DeviceID, button: HardwareButton) async throws {}
}

final class UIAutomationServiceTests: XCTestCase {
    func testTapSelectorUsesCenter() async throws {
        let button = UIElement(id: "e", role: "button", label: "Go", identifier: "go", value: nil, frame: Rect(x: 10, y: 20, width: 100, height: 40), enabled: true, selected: false, children: [])
        let tree = UITree(root: UIElement(id: "root", role: "application", label: nil, identifier: nil, value: nil, frame: Rect(x: 0, y: 0, width: 390, height: 844), enabled: true, selected: false, children: [button]), nodeCount: 2, truncated: false)
        let recorder = TapRecorder()
        let service = UIAutomationService(screen: nil, input: FakeInput(recorder: recorder), accessibility: FakeAccessibility(tree: tree))
        let result = try await service.tap(on: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"), selector: ElementSelector(identifier: "go"), settle: false)
        XCTAssertEqual(result.point, Point(x: 60, y: 40))
        let points = await recorder.points
        XCTAssertEqual(points, [Point(x: 60, y: 40)])
    }

    func testMissingServicesReturnCapabilityUnavailable() async {
        let service = UIAutomationService(screen: nil, input: nil, accessibility: nil)
        do {
            _ = try await service.tap(
                on: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"),
                selector: ElementSelector(identifier: "missing"),
                settle: false
            )
            XCTFail("expected capability_unavailable")
        } catch let error as OpenSimError {
            XCTAssertEqual(error.code, "capability_unavailable")
        }
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter UIAutomationServiceTests
```

Expected: FAIL với `cannot find 'UIAutomationService' in scope`.

- [ ] **Step 3: Viết automation và wiring**

`UIAutomationService` giữ optional `screen`, `input`, `accessibility`. `tap(selector:)` guard service, `find`, chọn match đầu tiên có frame khác rỗng, center, gọi input, settle tùy chọn, trả `UIActionResult` với `matchedCount`:

```swift
public struct UIAutomationService: Sendable {
    private let screen: (any ScreenControlling)?
    private let input: (any InputControlling)?
    private let accessibility: (any AccessibilityReading)?

    public init(
        screen: (any ScreenControlling)?,
        input: (any InputControlling)?,
        accessibility: (any AccessibilityReading)?
    ) {
        self.screen = screen
        self.input = input
        self.accessibility = accessibility
    }

    public func tap(on device: DeviceID, selector: ElementSelector, settle: Bool) async throws -> UIActionResult {
    guard let accessibility, let input else {
        throw OpenSimError.capabilityUnavailable(accessibility == nil ? "accessibility" : "input")
    }
    let matches = try await accessibility.find(on: device, selector: selector)
    guard let element = matches.first(where: { $0.frame.width > 0 && $0.frame.height > 0 }) else {
        throw OpenSimError.invalidArgument("Selector matched no element with a non-empty frame", details: ["matched": String(matches.count)])
    }
    let point = Point(x: element.frame.x + element.frame.width / 2, y: element.frame.y + element.frame.height / 2)
    try await input.tap(on: device, at: point, settle: settle)
    let settleMs = settle ? try await waitForIdle(on: device, idleMs: 250, timeoutMs: 2_000) : 0
    return UIActionResult(action: "tap", point: point, matchedElementID: element.id, matchedCount: matches.count, settleMs: settleMs)
}
```

`find` trả `[UIElement]`; `waitForIdle` poll screenshot hash mỗi 50 ms. `wait`: có selector thì poll `find` mỗi 100 ms đến timeout; không selector thì poll screenshot hash, yêu cầu ổn định `idleMs`, tối đa `timeoutMs`; trả `UIWaitResult`. `act`: decode steps, dispatch `tap`, `swipe`, `long-press`, `drag`, `pinch`, `rotate`, `scroll`, `type`, `key`, `button`, `wait` (`ms` sleep hoặc selector), `screenshot`; step lỗi dừng nếu `stopOnError`; trả `UIActResult`.

`SimctlBridge` thêm protocol và stored properties:

```swift
public protocol SimulatorScreenDisplaying: Sendable {
    @MainActor func makeDisplaySurface(for device: DeviceID) throws -> any DisplaySurface
}

public let screen: (any ScreenControlling)?
public let input: (any InputControlling)?
public let accessibility: (any AccessibilityReading)?
private let displaySurfaceFactory: (@MainActor @Sendable (DeviceID) throws -> any DisplaySurface)?

public init(
    devices: any DeviceControlling,
    runtimes: any RuntimeControlling,
    apps: any AppControlling,
    logs: any LogControlling,
    crashReports: any CrashReportReading,
    doctor: any DoctorReporting,
    screen: (any ScreenControlling)? = nil,
    input: (any InputControlling)? = nil,
    accessibility: (any AccessibilityReading)? = nil,
    displaySurfaceFactory: (@MainActor @Sendable (DeviceID) throws -> any DisplaySurface)? = nil,
    capabilityProvider: @escaping @Sendable () async -> BridgeCapabilities
) {
    self.screen = screen
    self.input = input
    self.accessibility = accessibility
    self.displaySurfaceFactory = displaySurfaceFactory
    self.devices = devices
    self.runtimes = runtimes
    self.apps = apps
    self.logs = logs
    self.crashService = crashReports
    self.doctorService = doctor
    self.capabilityProvider = capabilityProvider
}

@MainActor
public func makeDisplaySurface(for device: DeviceID) throws -> any DisplaySurface {
    guard let displaySurfaceFactory else { throw OpenSimError.capabilityUnavailable("render") }
    return try displaySurfaceFactory(device)
}
```

`live` tạo gate, `SimctlScreenService`, surface factory theo `gate.render` (`IOSurfaceDisplaySurface`, `ScreenshotPollingSurface`; nhánh `.simDisplayView` đã retired nên dùng IOSurface), và `FramebufferScreenshotter` khi gate render là ioSurface. Input dùng `DTUHIDInputService` khi CoreSimulator >= 1155.4; XCUITest helper chỉ còn cho accessibility (và fallback trên toolchain cũ). Multi-touch/button vẫn `unknown` cho tới khi xác minh hai ngón.

`SimctlScreenService` conform thêm `ScreenshotOutWriting` để executor truyền `out`; operation `screen_screenshot` dùng overload này khi có `out`. `UIAutomationService` được inject trong `CLIRuntime.makeBackend` cùng catalog `.plan2()`.

`BridgeOperationExecutor` thêm property và init parameter:

```swift
public let automation: UIAutomationService?

public init(
    bridge: any SimulatorBridge,
    crashReports: (any CrashReportReading)? = nil,
    doctor: (any DoctorReporting)? = nil,
    catalog: OperationCatalog = .plan1(),
    automation: UIAutomationService? = nil
) {
    self.bridge = bridge
    self.crashReports = crashReports
    self.doctor = doctor
    self.catalog = catalog
    self.automation = automation
}
```

Thêm case `screen_info`, `screen_screenshot`, `screen_record_start`, `screen_record_stop`, `ui_tree`, `ui_find`, `ui_wait`, `ui_act`, `ui_tap`, `ui_swipe`, `ui_long_press`, `ui_drag`, `ui_pinch`, `ui_rotate`, `ui_scroll`, `ui_type`, `ui_key`, `ui_button`. Mẫu:

```swift
case "ui_tap":
    guard let automation, let input = bridge.input else { throw OpenSimError.capabilityUnavailable("input") }
    let device = try await resolveDevice(params)
    let settle = try params.bool("settle", default: false)
    if let selector = try selector(from: params) {
        return try encode(try await automation.tap(on: device, selector: selector, settle: settle))
    }
    let point = try PointParser.parse(x: params.optionalString("x"), y: params.optionalString("y"))
    try await input.tap(on: device, at: point, settle: settle)
    return try encode(UIActionResult(action: "tap", point: point, matchedCount: 0, settleMs: 0))
```

`selector(from:)` parse JSON `ElementSelector` hoặc `SelectorParser.parse`; `pointParameter` decode JSON `Point` hoặc fallback `PointParser.parse("x,y")`; `key` parse modifiers JSON; `button` map `HardwareButton(rawValue:)`; `ui_act` decode `[UIActStep]` từ string JSON. `CapabilityEvaluator.evaluate` nhận `plan2: Plan2Capabilities? = nil`, map `render/hid/accessibility`. `DoctorService` ghi backend vào notes. `CLIRuntime.makeBackend` dùng `OperationCatalog.plan2()` và inject `UIAutomationService`.

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift test --filter UIAutomationServiceTests
swift test --filter Plan2CatalogTests
swift build
```

Expected: PASS; `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridge/Services/UIAutomationService.swift Sources/OpenSimBridge/SimctlBridge.swift Sources/OpenSimBridge/Operations/BridgeOperationExecutor.swift Sources/OpenSimBridge/Environment Sources/OpenSimCLI/Runtime/CLIRuntime.swift Tests/OpenSimBridgeTests/UIAutomationServiceTests.swift
git commit -m "feat(bridge): wire plan 2 services and automation"
```

---

### Task 13: `OpenSimBridgeUI.SimulatorScreenView` cho Plan 4

**Files:**
- Modify: `Package.swift` (thêm target `OpenSimBridgeUI`, test target `OpenSimBridgeUITests`)
- Create: `Sources/OpenSimBridgeUI/SimulatorScreenView.swift`, `Sources/OpenSimBridgeUI/ScreenPointerMapper.swift`
- Test: `Tests/OpenSimBridgeUITests/SimulatorScreenViewTests.swift`

**Interfaces:**
- Produces API cố định:
  - `init(device: DeviceID) throws`
  - `init(device: DeviceID, bridge: any SimulatorScreenDisplaying)`
  - `connect() async throws`, `disconnect()`
  - `var screenSize: CGSize`, `var onScreenSizeChange: ((CGSize) -> Void)?`
  - `var onError: ((OpenSimError) -> Void)?`
  - `var rotation: ScreenRotation`, `func setRotation(_:)`
  - `func simulatorPoint(fromViewPoint:) -> Point?`, `func viewPoint(fromSimulatorPoint:) -> NSPoint?`

- [ ] **Step 1: Viết test thất bại**

```swift
import AppKit
import XCTest
@testable import OpenSimBridgeUI
@testable import OpenSimBridge
@testable import OpenSimCore

@MainActor
private final class FakeSurface: DisplaySurface {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
    var pixelSize = CGSize(width: 600, height: 1200)
    var screenScale: CGFloat = 3
    var onSizeChange: ((CGSize) -> Void)?
    var onError: ((OpenSimError) -> Void)?
    func connect() async throws {}
    func disconnect() {}
}

@MainActor
private struct FakeBridge: SimulatorScreenDisplaying {
    func makeDisplaySurface(for device: DeviceID) throws -> any DisplaySurface { FakeSurface() }
}

final class SimulatorScreenViewTests: XCTestCase {
    @MainActor
    func testConnectAndRotate() async throws {
        let view = try SimulatorScreenView(device: DeviceID("95B3747B-7065-447E-AB1E-53065142C3FC"), bridge: FakeBridge())
        var size: CGSize?
        view.onScreenSizeChange = { size = $0 }
        try await view.connect()
        XCTAssertEqual(view.screenSize, CGSize(width: 200, height: 400))
        XCTAssertEqual(size, CGSize(width: 200, height: 400))
        view.setRotation(.landscapeLeft)
        XCTAssertEqual(view.screenSize, CGSize(width: 400, height: 200))
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter SimulatorScreenViewTests
```

Expected: FAIL với `cannot find 'SimulatorScreenView' in scope`.

- [ ] **Step 3: Viết view**

Thêm target/product `OpenSimBridgeUI` deps `OpenSimCore`, `OpenSimBridge`; test target `OpenSimBridgeUITests`; thêm `OpenSimBridgeUI` vào deps `IntegrationTests`.

`SimulatorScreenView` là `NSView` chứa `rotationContainer` và surface.view. `screenSize` = pixelSize / screenScale, swap khi `rotation.isSideways`. `rotation` là hướng hiển thị của view; thay đổi orientation thiết bị không thuộc Plan 2. `connect` tạo surface, gán callback, connect, add subview, phát size. `disconnect` gọi surface, remove, reset. `setRotation` cập nhật, phát size mới, `needsLayout`.

`layout` giữ `rotationContainer.bounds` = kích thước gốc (base), đặt frame căn giữa bounds, rồi áp `frameCenterRotation` với scale lấy từ aspect-fit của kích thước hiển thị (đã swap nếu xoay). Không đặt frame container bằng aspect-fit rotated rectangle trước khi xoay (sẽ lệch geometry).

> Landscape visual chưa nghiệm thu: `OpenSimPreview --rotate` chỉ còn một phần nội dung ở góc; `screenSize`/pointer math đúng nhưng render layer-backed view khi xoay cần xử lý ở Plan 4 (rotate layer/image host). Preview hiện chỉ mở portrait; `setRotation` vẫn được unit test ở mức size.

`ScreenPointerMapper` nhận `bounds`, `contentSize` (base), `rotation`; `aspectFitRect(content:in:)` tính tỉ lệ; `simulatorPoint` chuẩn hoá điểm theo rect hiển thị (trục y đổi từ NSView bottom-left sang top-left), áp inverse rotation (90: `(y, 1-x)`, 180: `(1-x,1-y)`, 270: `(1-y,x)`), trả nil ngoài `0` đến `1`; `viewPoint` là nghịch đảo. Surface nhận `screenScaleProvider` async để lấy scale thật từ `screen_info` khi connect, tránh báo screenSize bằng pixel.

```swift
@MainActor
public final class SimulatorScreenView: NSView {
    public let device: DeviceID
    private let bridge: any SimulatorScreenDisplaying
    private var surface: (any DisplaySurface)?
    private let rotationContainer = NSView()
    private let mapper = ScreenPointerMapper()

    public private(set) var screenSize: CGSize = .zero
    public private(set) var rotation: ScreenRotation = .portrait
    public var onScreenSizeChange: ((CGSize) -> Void)?
    public var onError: ((OpenSimError) -> Void)?

    public convenience init(device: DeviceID) throws {
        try self.init(device: device, bridge: SimctlBridge.live())
    }

    public init(device: DeviceID, bridge: any SimulatorScreenDisplaying) {
        self.device = device
        self.bridge = bridge
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 640))
        wantsLayer = true
        rotationContainer.wantsLayer = true
        addSubview(rotationContainer)
    }

    public required init?(coder: NSCoder) { return nil }

    public func connect() async throws {
        do {
            let surface = try bridge.makeDisplaySurface(for: device)
            surface.onSizeChange = { [weak self] size in self?.update(size) }
            surface.onError = { [weak self] error in self?.onError?(error) }
            try await surface.connect()
            self.surface = surface
            rotationContainer.addSubview(surface.view)
            update(surface.pixelSize)
            needsLayout = true
        } catch let error as OpenSimError {
            onError?(error)
            throw error
        }
    }

    public func disconnect() {
        surface?.disconnect()
        surface?.view.removeFromSuperview()
        surface = nil
        screenSize = .zero
    }

    public func setRotation(_ rotation: ScreenRotation) {
        self.rotation = rotation
        if let surface { update(surface.pixelSize) }
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        guard let surface else { return }
        let base = CGSize(width: surface.pixelSize.width / max(1, surface.screenScale), height: surface.pixelSize.height / max(1, surface.screenScale))
        let content = rotation.isSideways ? CGSize(width: base.height, height: base.width) : base
        rotationContainer.frame = mapper.aspectFitRect(content: content, in: bounds)
        surface.view.frame = rotationContainer.bounds
        rotationContainer.layer?.setAffineTransform(CGAffineTransform(rotationAngle: rotation.degrees * .pi / 180))
    }

    public func simulatorPoint(fromViewPoint point: NSPoint) -> Point? {
        guard let surface else { return nil }
        return mapper.simulatorPoint(fromViewPoint: point, container: rotationContainer, contentSize: baseSize(surface), rotation: rotation, root: self)
    }

    public func viewPoint(fromSimulatorPoint point: Point) -> NSPoint? {
        guard let surface else { return nil }
        return mapper.viewPoint(fromSimulatorPoint: point, container: rotationContainer, contentSize: baseSize(surface), rotation: rotation, root: self)
    }

    private func baseSize(_ surface: any DisplaySurface) -> CGSize {
        CGSize(width: surface.pixelSize.width / max(1, surface.screenScale), height: surface.pixelSize.height / max(1, surface.screenScale))
    }

    private func update(_ pixels: CGSize) {
        guard let surface else { return }
        let base = baseSize(surface)
        let size = rotation.isSideways ? CGSize(width: base.height, height: base.width) : base
        if size != screenSize {
            screenSize = size
            onScreenSizeChange?(size)
            needsLayout = true
        }
    }
}
```

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift test --filter SimulatorScreenViewTests
swift build
```

Expected: PASS; Plan 4 dùng đúng API trên.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimBridgeUI Tests/OpenSimBridgeUITests
git commit -m "feat(ui): add simulator screen view for plan 4"
```

---

### Task 14: CLI `ui` commands

**Files:**
- Create: `Sources/OpenSimCLI/Commands/UICommand.swift`, `Sources/OpenSimCLI/Commands/UICommandSupport.swift`
- Test: `Tests/OpenSimCLITests/UICommandParsingTests.swift`

**Interfaces:**
- Produces: `UICommand` và leaf commands; `UICommandSupport.selectorJSON`, `.pointJSON`, `.actionTable`, `.treeTable`, `.elementTable`, `.actTable`.

- [ ] **Step 1: Viết test thất bại**

```swift
import ArgumentParser
import XCTest
@testable import OpenSimCLI
@testable import OpenSimCore

final class UICommandParsingTests: XCTestCase {
    func testScreenshotAndTap() throws {
        let shot = try XCTUnwrap(try OpenSimCommand.parseAsRoot(["ui", "screenshot", "--out", "/tmp/a.png", "--scale", "0.5", "--json"]) as? UIScreenshotCommand)
        XCTAssertEqual(shot.out, "/tmp/a.png")
        XCTAssertEqual(shot.scale, 0.5)
        let tap = try XCTUnwrap(try OpenSimCommand.parseAsRoot(["ui", "tap", "--on", "id=fixture-primary-button", "--settle"]) as? UITapCommand)
        XCTAssertEqual(tap.on, "id=fixture-primary-button")
        XCTAssertNoThrow(try tap.validate())
        let invalid = try XCTUnwrap(try OpenSimCommand.parseAsRoot(["ui", "tap", "--x", "1", "--y", "2", "--on", "id=a"]) as? UITapCommand)
        XCTAssertThrowsError(try invalid.validate())
    }

    func testTreeFindWaitAct() throws {
        XCTAssertEqual(try XCTUnwrap(try OpenSimCommand.parseAsRoot(["ui", "tree", "--max-depth", "10"]) as? UITreeCommand).maxDepth, 10)
        XCTAssertEqual(try XCTUnwrap(try OpenSimCommand.parseAsRoot(["ui", "find", "id=fixture-primary-button"]) as? UIFindCommand).selector, "id=fixture-primary-button")
        XCTAssertEqual(try XCTUnwrap(try OpenSimCommand.parseAsRoot(["ui", "wait", "--on", "id=a", "--timeout-ms", "3000"]) as? UIWaitCommand).timeoutMs, 3000)
        let act = try XCTUnwrap(try OpenSimCommand.parseAsRoot(["ui", "act", "--steps", "[{\"type\":\"tap\",\"on\":{\"identifier\":\"a\"}}]"]) as? UIActCommand)
        XCTAssertNoThrow(try act.validatedSteps())
    }
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter UICommandParsingTests
```

Expected: FAIL với `cannot find type 'UIScreenshotCommand' in scope`.

- [ ] **Step 3: Viết command group**

`UICommand` subcommands: `screenshot`, `record` (start/stop), `info`, `tap`, `swipe`, `long-press`, `drag`, `pinch`, `rotate`, `scroll`, `type`, `key`, `button`, `wait`, `tree`, `find`, `act`.

ArgumentParser tự gọi `validate()` khi parse, nên tổ hợp `--on` + `--x/--y` fail ngay ở bước parse; test không tạo command invalid rồi gọi validate lần hai.

| Lệnh | Operation | Flag chính |
|---|---|---|
| `ui screenshot` | `screen_screenshot` | `--out`, `--format`, `--scale`, `--quality` |
| `ui record start` | `screen_record_start` | `--out`, `--codec` |
| `ui record stop` | `screen_record_stop` | positional `recording-id` |
| `ui info` | `screen_info` | `--device` |
| `ui tap` | `ui_tap` | `--x`, `--y`, `--on`, `--settle` |
| `ui swipe` / `ui drag` | `ui_swipe` / `ui_drag` | `--from`, `--to`, `--duration-ms` |
| `ui long-press` | `ui_long_press` | `--x`, `--y`, `--duration-ms` |
| `ui pinch` | `ui_pinch` | `--center`, `--scale`, `--duration-ms` |
| `ui rotate` | `ui_rotate` | `--center`, `--angle`, `--duration-ms` |
| `ui scroll` | `ui_scroll` | `--delta-x`, `--delta-y`, `--at` |
| `ui type` | `ui_type` | positional text |
| `ui key` | `ui_key` | positional name, `--command/--shift/--option/--control` |
| `ui button` | `ui_button` | positional enum |
| `ui wait` | `ui_wait` | `--on`, `--idle-ms`, `--timeout-ms` |
| `ui tree` | `ui_tree` | `--max-depth`, `--max-nodes` |
| `ui find` | `ui_find` | positional selector |
| `ui act` | `ui_act` | `--steps`, `--steps-file`, `--stop-on-error` |

Helper:

```swift
public enum UICommandSupport {
    public static func selectorJSON(_ text: String) throws -> String {
        let selector = try SelectorParser.parse(text)
        return String(decoding: try OpenSimJSON.encoder(pretty: false).encode(selector), as: UTF8.self)
    }

    public static func pointJSON(_ text: String, label: String) throws -> String {
        let point = try PointParser.parse(text, label: label)
        return String(decoding: try OpenSimJSON.encoder(pretty: false).encode(point), as: UTF8.self)
    }

    public static func actionTable(_ result: UIActionResult) -> Table {
        Table(headers: ["ACTION", "X", "Y", "MATCHED", "SETTLE_MS"], rows: [[
            result.action,
            result.point.map { String($0.x) } ?? "",
            result.point.map { String($0.y) } ?? "",
            String(result.matchedCount),
            String(result.settleMs),
        ]])
    }
}
```

`UITapCommand.validate()` yêu cầu đúng một trong hai dạng: `--on`, hoặc `--x` + `--y`; parse sớm bằng `SelectorParser`/`PointParser`. `UIActCommand.validatedSteps()` decode `[UIActStep]`, yêu cầu không rỗng, type thuộc `tap`, `swipe`, `long-press`, `drag`, `pinch`, `rotate`, `scroll`, `type`, `key`, `button`, `wait`, `screenshot`; `--steps-file` validate extension `json` và đọc file. Tất cả command dùng `CLIRuntime.run` và operation tương ứng; JSON envelope giữ schema Plan 1.

- [ ] **Step 4: Chạy để thấy pass**

```bash
swift test --filter UICommandParsingTests
```

Expected: PASS; `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCLI/Commands/UICommand.swift Sources/OpenSimCLI/Commands/UICommandSupport.swift Tests/OpenSimCLITests/UICommandParsingTests.swift
git commit -m "feat(cli): add ui command group"
```

---

### Task 15: Integration test fixture, CLI smoke và chốt gate

> **Status 2026-10-20:** input đã chuyển sang **dtuhidd XPC** (`DTUHIDInputService`); XCUITest chỉ còn accessibility. Integration flow `testFixtureInputAccessibilityAndScreenshot` **PASS 43s** (screenshot, tree/find, tap → counter, type email, long-press, swipe/pan, `ui act`). Đã xác minh thêm qua CLI/preview: tap, type ký tự shift `@`, swipe-left, long-press, scroll, Home button. Pinch/rotate hai ngón đã xác nhận; gate `multiTouch`/`hardwareButtons = available`. `testFixtureRecording` **skip** vì `simctl recordVideo` headless không dừng. CLI giờ giữ state giữa các lệnh vì input không cần session; daemon Plan 3 vẫn cần cho accessibility/lease. Bằng chứng: `docs/superpowers/spikes/2026-10-20-plan2-input-blocker.md`.

**Files:**
- Create: `Tests/IntegrationTests/Support/FixtureInstaller.swift`, `Tests/IntegrationTests/Plan2FixtureIntegrationTests.swift`
- Modify: `Tests/IntegrationTests/README.md`, `docs/superpowers/spikes/2026-10-20-plan2-capability-gate.md`

**Interfaces:**
- Produces: fixture flow; CLI smoke; gate report cuối.

- [ ] **Step 1: Viết test thất bại**

`FixtureInstaller` (import `XCTest`) chạy `Fixtures/OpenSimFixture/build.sh` bằng `Process`, lấy dòng cuối làm `.app`, `bridge.apps.installApp`, trả bundle ID. Thiếu script/build thì `XCTSkip` với hướng dẫn.

`Plan2FixtureIntegrationTests` setUp skip trừ khi `OPENSIM_INTEGRATION=1`; `prepare` lấy bridge live, tìm iOS booted, install, launch fixture, sleep 1 giây. Các test:

```swift
func testScreenshotTreeAndFind() async throws {
    try await prepare()
    let shot = try await XCTUnwrap(bridge.screen).screenshot(on: device.id, format: .png, scale: 1, quality: nil)
    XCTAssertGreaterThan(shot.width, 0)
    guard let accessibility = bridge.accessibility else { throw XCTSkip("accessibility unavailable") }
    let tree = try await accessibility.tree(on: device.id, maxDepth: 30, maxNodes: 1_500)
    XCTAssertGreaterThan(tree.nodeCount, 0)
    let matches = try await accessibility.find(on: device.id, selector: ElementSelector(identifier: "fixture-primary-button"))
    XCTAssertEqual(matches.count, 1)
    try await bridge.apps.terminateApp(on: device.id, bundleID: "dev.opensim.fixture")
}
```

Các test còn lại:

1. `testTapSelectorChangesCounter`: tree counter `0`; `UIAutomationService.tap` selector `fixture-primary-button`; `wait` counter; assert value `1`.
2. `testTypeText`: tap `fixture-text-field`; `typeText("hello@example.com")`; find field; assert `value`.
3. `testGestureAndRecording`: swipe, long-press; nếu gate `multiTouch` available thì pinch/rotate; start/stop recording, file size > 0.
4. `testActBatch`: tap, wait 200 ms, screenshot JPEG 0.5; 3 step `ok`.
5. `testCapabilityUnavailable`: tạo `BridgeOperationExecutor` với bridge có service nil, gọi `ui_tree`, assert `capability_unavailable`.
6. Fallback test: chỉ chạy khi gate chọn `xcuiTest`; nếu primary active `XCTSkip`; ngược lại chạy `ui tree`/tap qua helper với `OPENSIM_XCUITEST_BUNDLE_ID=dev.opensim.fixture`.

```swift
func testFallbackBackend() async throws {
    let gate = Plan2CapabilityGate.evaluate(
        checker: SimulatorKitLoader.live(),
        helperConfigured: XCUITestHelperRunner.isConfigured
    )
    try XCTSkipIf(gate.accessibility != .xcuiTest, "primary accessibility is active")
    try await prepare()
    guard let accessibility = bridge.accessibility else { throw XCTSkip("fallback helper is unavailable") }
    let tree = try await accessibility.tree(on: device.id, maxDepth: 30, maxNodes: 1_500)
    XCTAssertGreaterThan(tree.nodeCount, 0)
}
```

- [ ] **Step 2: Chạy để thấy fail**

```bash
swift test --filter Plan2FixtureIntegrationTests
```

Expected: PASS-with-skip vì `OPENSIM_INTEGRATION` chưa đặt.

- [ ] **Step 3: Chạy integration và CLI smoke**

```bash
swift build
OPENSIM_INTEGRATION=1 swift test --filter Plan2FixtureIntegrationTests
export OPENSIM_XCUITEST_BUNDLE_ID=dev.opensim.fixture
BIN="$(swift build --show-bin-path)/opensim"
APP="$(Fixtures/OpenSimFixture/build.sh | tail -1)"
xcrun simctl install booted "$APP"
xcrun simctl launch booted dev.opensim.fixture
"$BIN" ui info --device "iPhone Air" --json
"$BIN" ui screenshot --device "iPhone Air" --out /tmp/opensim-ui.png --json
"$BIN" ui tree --device "iPhone Air" --json
"$BIN" ui find 'id=fixture-primary-button' --device "iPhone Air" --json
"$BIN" ui act --steps '[{"type":"tap","on":{"identifier":"fixture-primary-button"}},{"type":"wait","ms":200},{"type":"screenshot","format":"png"}]' --device "iPhone Air" --json
# Mỗi lệnh CLI là một session riêng: tap/type/wait rời rạc không giữ state.
# Dùng ui act cho chuỗi stateful; daemon Plan 3 giữ session giữa các lệnh.
# record start/stop bị treo headless (simctl recordVideo không dừng) — Task 15 skip.
```

Expected: envelope `schemaVersion = 1`; `ui info` có screen; screenshot file tồn tại; tree có identifier; find một element; `ui act` đủ step và có screenshot. `testFixtureInputAccessibilityAndScreenshot` PASS; recording test skip kèm lý do. Khi service nil, exit `5`, stderr `error[capability_unavailable]`.

- [ ] **Step 4: Chốt gate report**

Ghi vào gate report: backend render/input/a11y; `multiTouch` available nếu pinch/rotate đổi `fixture-canvas-label`; `hardwareButtons` available nếu `home` lên SpringBoard; test skip tương ứng; thời gian `ui tree`, tap, fps polling. Chạy:

```bash
swift test
```

Expected: unit test pass; integration skip nếu không có env.

- [ ] **Step 5: Commit**

```bash
git add Tests/IntegrationTests docs/superpowers/spikes/2026-10-20-plan2-capability-gate.md
git commit -m "test(integration): add plan 2 fixture and cli smoke"
```

---

## Spec coverage

| Mục spec | Nội dung | Task |
|---|---|---|
| 5.4 | render `SimDisplayView`/IOSurface/polling; input digitizer; a11y `SimAccessibilityManager` + XCUITest fallback | 6, 7, 8, 9, 10, 11 |
| 5.5 | agent đọc tree, tap selector, type, settle | 12, 14, 15 |
| 6 | `ScreenInfo`, `UIElement`, `UITree`, `ElementSelector`; DTO automation | 1, 2, 11 |
| 7.1 | `--json`, `--device`, exit code, envelope Plan 1 | 12, 14 |
| 7.2 | `ui` screenshot/record/info, input, tree/find/tap on/wait/act | 14 |
| 7.3 | batch `ui act`, step result, `stopOnError` | 1, 12, 14, 15 |
| 8.2 | tên `screen_*`, `ui_*` trong catalog (MCP adapter ở Plan 3) | 1, 12 |
| 8.3 | `capability_unavailable`, `input_failed`, `a11y_unavailable`, `simctl_failed` | 8, 9, 10, 11, 12 |
| 9.2 | `SimulatorScreenView` size/error callback, rotation | 13 |
| 12 | path allowlist, recording state `0600`, không shell string | 4, 5, 14 |
| 14.1 | selector parser, point parser, matcher | 2 |
| 14.2 | fixture, screenshot, tree, find, tap, type, gesture, record | 3, 15 |
| 16 Plan 2 | screen + input + a11y + CLI `ui` | tất cả |
| 17.1 | acceptance 4, 5, 6 | 15 |
| 17.2 | tree ≤ 500 ms, input latency; ghi số đo | 6, 15 |
| 18 | gate + fallback + capability report | 6, 9, 10, 15 |

## Exit criteria

- `swift build` thành công với `OpenSimBridgeUI`; `swift test` pass `OpenSimCoreTests`, `OpenSimBridgeTests`, `OpenSimBridgeUITests`, `OpenSimCLITests`.
- `OPENSIM_INTEGRATION=1 swift test --filter Plan2FixtureIntegrationTests` pass với fixture trên simulator iOS 27 booted; primary/fallback skip đúng backend.
- `opensim ui screenshot`, `ui info`, `ui record start/stop`, `ui tree`, `ui find`, `ui tap --on`, `ui type`, `ui wait`, `ui act` chạy trên simulator thật; envelope `schemaVersion = 1`.
- Khi `screen/input/accessibility` nil, CLI trả exit `5` và `capability_unavailable`, không crash.
- `SimulatorScreenView` cung cấp đúng API Task 13; Plan 4 tạo view, connect, nhận callback, rotation, map point.
- Gate report có kết quả thật cho render/input/a11y, multi-touch, hardware button, backend và số đo.
- Không có daemon, MCP, app UI, storage, performance, session/lease trong diff.
- Không có selector private ngoài danh sách đóng; quan sát thêm chỉ nằm trong gate report.