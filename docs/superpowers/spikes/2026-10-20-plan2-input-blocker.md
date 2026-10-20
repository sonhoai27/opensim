# Plan 2 input blocker — 2026-10-20

## Kết luận

XCUITest helper **không dùng được làm input path chính** trên môi trường này:

- Mỗi action là một lần `xcodebuild test-without-building`, mất **75–147 giây**.
- `xcodebuild` **shutdown simulator** sau mỗi lần chạy, nên app bị terminate và state UI mất.
- Vì vậy tap ở lần chạy trước không quan sát được ở lần chạy sau. Đây là blocker của Task 15
  (`testTapSelectorChangesCounter`) và của mục tiêu "agent điều khiển simulator".

## Bằng chứng

### 1. Helper trả tree/tap đúng

`ui find 'id=fixture-primary-button'` trả element:

```json
{"identifier":"fixture-primary-button","frame":{"height":44,"width":380,"x":20,"y":285}}
```

`ui tap --on 'id=fixture-primary-button'` trả `ok: true`, `matchedCount: 1`, point `(210, 307)`.
Thời gian một lần tap: **147 giây**.

### 2. State không giữ được

Ngay sau tap, `ui find 'id=fixture-counter-label'` trả `label = "0"` (đáng lẽ `"1"`).
Kiểm tra process: fixture không còn chạy; simulator ở trạng thái `Shutting Down`.

```text
before: iPhone Air (95B3747B-...) (Booted)
xcodebuild=0
after:  iPhone Air (95B3747B-...) (Shutting Down)
app-gone
```

Thử `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`: vẫn shutdown.

### 3. Screenshot headless

`xcrun simctl io <udid> screenshot` mất **~41 giây** mỗi lần, kể cả khi gọi trực tiếp và sau reboot.
Đã thay primary bằng framebuffer (`SimDeviceScreen.screen.framebufferSurface` + CIContext):
**~0,6 giây**, ảnh 1260×2736. Simctl vẫn là fallback.

## Spike HID bổ sung (cùng ngày)

Đã thử đường private trong SimulatorKit (không dùng XCUITest):

- `SimDeviceScreen` có các Swift getter thật: `unmaskedSurface`, `maskedSurface`, `pixelSize`,
  `scale`, `buttonTarget`, `screen`.
- `SimDigitizerInputView` là NSView nhận mouse events; `SimDeviceLegacyHIDClient` là
  `SimDigitizerInputViewDelegate` và là nơi build/gửi Indigo HID message.
- `SimDeviceLegacyHIDClient` là ObjC-visible; `sendWithMessage:freeWhenDone:completionQueue:completion:`
  hoạt động. `SimDigitizerInputView.delegate` là Swift protocol **class-constrained** (không phải @objc),
  nên phải gán qua Swift ABI.

Kết quả: gọi trực tiếp Swift getter/setter (`buttonTarget`, `delegate`) từ process ngoài bằng
`@convention(thin)` bị sai ABI (crash `-[Swift.__StringStorage deviceType]`, hoặc crash khi setter).
Gán raw pointer vào ivar `delegate` (offset 544) chạy được, nhưng view không gọi delegate khi
`isEnabled=false`; bật `isEnabled=true` bằng raw memory thì crash trong `SimDigitizerInputView`
khi dispatch mouse event — delegate/existential chưa đúng ABI.

### Harness ABI (đã thử)

Đã dựng trampoline arm64 đặt `self` vào `x20`, args bắt đầu `x0` (đúng Swift method convention),
và kiểm chứng bằng một dylib Swift tự tạo: method, property getter/setter, existential property
đều trả đúng.

Với SimulatorKit:
- `SimDigitizerInputView.delegate` setter/getter (`...vsTj`/`...vgTj`) là **resilient dispatch thunk**:
  disassembly dùng `autda x20`, đọc method descriptor tại `x20 + 0x218` rồi `braa`.
- Gọi thunk với `x20 = instance` (convention thường): getter trả `nil`, setter không có tác dụng.
- Gọi với `x20 = class metadata`: **SIGBUS** (giá trị `x20 + 0x218` không phải method descriptor hợp lệ).

Kết luận: đường HID private đúng hướng và không cần quyền macOS Accessibility, nhưng các accessor
Swift của SimulatorKit cần **reproduce resilient method dispatch** (method descriptor/metadata cache),
không chỉ SwiftCC thường. Đây là spike sâu hơn (reverse-engineering ABI), không nên tiếp tục trong
process probe.

### Khuyến nghị chuyển hướng

Dùng **persistent XCUITest helper server** cho input/a11y: giữ một `xcodebuild test-without-building`
chạy dài hạn, test helper mở TCP server trên localhost, CLI gửi action và nhận kết quả. Simulator
không bị shutdown giữa các action, app state được giữ; đổi lại độ phức tạp nằm ở vòng đời helper
(timeout/cleanup) chứ không phải ABI private.

## Persistent helper server (đã dựng — 2026-10-20)

Đã thay one-shot `xcodebuild` bằng server dài hạn:

- Fixture `testHelperServer` kết nối TCP `127.0.0.1`, handshake `{"ready":true}`, nhận JSON line
  action, trả JSON response; `executionTimeAllowance = 3600`.
- `XCUITestHelperRunner` giữ một session cho mỗi `(device, bundleID)`, build `.xctestrun` một lần,
  mở xcodebuild một lần, giao tiếp qua socket; session kết thúc khi CLI thoát hoặc `shutdown`.
- Đo thật: startup + tree + tap + tree = **46–53 giây**; `tap` đổi counter `0 → 1` trong cùng
  session. Integration flow `testFixtureInputAccessibilityAndScreenshot` **PASS** (screenshot,
  tree/find, tap, type, long-press, swipe/pan, `ui act`).

Giới hạn còn lại:
- Mỗi lệnh CLI là một process/session riêng, nên state không qua được lệnh; `ui act` giữ state
  trong một batch, daemon Plan 3 sẽ giữ session giữa các lệnh.
- `simctl recordVideo` headless không dừng sau SIGINT (quá 10 giây, process còn sống); recording
  integration test skip. Cần framebuffer/AVAssetWriter hoặc display host (Plan 5/6).

## dtuhidd đã thay XCUITestInputService (2026-10-20)

`DTUHIDInputService` nối XPC tới `com.apple.coredevice.feature.remote.hid.digitizer` qua
`SimDevice.lookup` + các symbol `_4sim`; message `IndigoDigitizerEvent` / `IndigoKeyboardButtonEvent`
/ `IndigoButtonEvent`; toạ độ chuẩn hoá 0..1.

Đã xác minh thật:

| Input | Kết quả |
|---|---|
| Tap (preview click + CLI) | counter `0 → 1`, có ảnh framebuffer |
| Type `abc123`, `hello@example.com` | text field và label đúng |
| Swipe-left | `gesture=swipe-left` |
| Long press | `gesture=long-press` |
| Vertical scroll | nội dung cuộn |
| Home button | về Home screen |
| Integration flow | **PASS 43s**, không dùng XCUITest cho input |

Pinch/rotate hai ngón đã PASS (`canvas=scale:1.76...`, `rotation:1.48...`) sau khi đổi trục hai
ngón sang ngang như idb; `multiTouch`/`hardwareButtons` chuyển `available` trong gate.
XCUITest helper chỉ còn dùng cho accessibility tree/find; không còn là input path.

## Hướng khả thi

### A. DeviceKit/CoreDevice HID (khuyến nghị spike)

`/Applications/Xcode.app/Contents/SharedFrameworks/DeviceKit.framework` chứa đường input thật của
Device Hub:

- `SyntheticTouchEventProcessor` (ivars `digitizerFilter`, `hitMask`, `state`).
- `HIDServiceRegistry` với `eventSink: HIDEventEnqueueing`, `HIDLocalServiceLookup`,
  `Configuration(inputMode:simulateHardwareKeyboard:)`.
- `HIDManager.HIDEvent`: `.report(UniversalHID.HIDReport, CoreDevice.HIDServiceID)`,
  `.button(Int, Int, CoreDevice.HIDButtonState)`, `.scroll(...)`.
- `DigitizerState`, `DigitizerState.TouchResult`, `HIDEventGeometry`.
- `DeviceAccessibilityView` + `startAccessibility`/`stopAccessibility` (accessibility tree qua
  `_axRemoteDevice`).

Đây là Swift-only API không có header; cần một spike dựng được `HIDManager` cho device và gửi
`DigitizerReport`, rồi xác minh tap làm đổi counter ngay trong một session (không reboot).
Nếu thành công, thay `XCUITestInputService`/`XCUITestAccessibilityService` làm primary.

### B. Persistent XCUITest helper server (đã chọn và đã dựng)

Đã triển khai; xem mục "Persistent helper server" ở trên.

### C. macOS Accessibility (AXUIElement)

Có thể đọc tree và AXPress nhanh, nhưng `AXIsProcessTrusted()` trả `false`; cần người dùng cấp
quyền Accessibility cho process điều khiển. Không phù hợp mặc định agent-first.

## Việc chưa làm

- Task 15 integration gate, CLI smoke đầy đủ (tap → counter → type/gesture/record).
- `ui act` hiện gọi helper cho từng action; kể cả khi helper giữ state, batch cần một session riêng.

## Đề xuất

Dừng Plan 2 ở Task 14, chạy spike A (DeviceKit HID + accessibility) trước khi làm Task 15 và
Plan 3. Screenshot/record/info/CLI đã có đường thật; input/a11y là mảnh còn thiếu để sản phẩm
dùng được.
