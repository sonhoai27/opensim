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

### B. Persistent XCUITest helper server

Giữ một `xcodebuild test-without-building` chạy dài hạn; test helper mở TCP server trên localhost
và nhận lệnh từ runner. Simulator không shutdown giữa các lệnh, state giữ nguyên, latency thấp.
Nhược điểm: phức tạp, phụ thuộc test runner sống lâu, cần cơ chế cleanup/timeout.

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
