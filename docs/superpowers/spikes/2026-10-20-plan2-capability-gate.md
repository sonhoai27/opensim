# Plan 2 capability gate — 2026-10-20

## Môi trường

- macOS 27.0.1 (26A434), arm64.
- Xcode 27.1 (27A9275).
- Runtime: iOS 27.0 (24A434), `com.apple.CoreSimulator.SimRuntime.iOS-27-0`.
- Device dùng cho Plan 0/2: iPhone Air `95B3747B-7065-447E-AB1E-53065142C3FC`.

## Lệnh chạy

```bash
swift test --filter Plan2CapabilityGateTests
OPENSIM_GATE=1 swift test --filter Plan2GateProbeTests
```

## Kết quả thật

```text
PLAN2_GATE={"accessibility":"unavailable","hardwareButtons":"unknown","input":"unavailable","multiTouch":"unknown","notes":{"accessibility":"unavailable","indigoSymbolCount":"17","input":"unavailable","legacyHIDSendSelectors":"sendWithMessage:freeWhenDone:completionQueue:completion:","render":"ioSurface"},"render":"ioSurface"}
PLAN2_INDIGO=IndigoHIDMessageForButton,IndigoHIDMessageForDeviceMotionLiteEvent,IndigoHIDMessageForDigitalCrownEvent,IndigoHIDMessageForDigitalDialEvent,IndigoHIDMessageForGameControllerEvent,IndigoHIDMessageForHIDArbitrary,IndigoHIDMessageForKeyboardArbitrary,IndigoHIDMessageForKeyboardNSEvent,IndigoHIDMessageForModifierKeyBit,IndigoHIDMessageForMouseNSEvent,IndigoHIDMessageForPointerEventFromHIDEventRef,IndigoHIDMessageForPressureEvent,IndigoHIDMessageForScrollEvent,IndigoHIDMessageForScrollEventFromHIDEventRef,IndigoHIDMessageForTrackpadEventFromHIDEventRef,IndigoHIDMessageForTrackpadMoveEvent,IndigoHIDMessageForWatchGesture
PLAN2_SEND=sendWithMessage:freeWhenDone:completionQueue:completion:
PLAN2_SCREEN_SEL=initWithDevice:screenID:,screen,screenID
PLAN2_DISPLAY_SEL=
PLAN2_PROXY_CLASS=Optional(ROCKRemoteProxy)
PLAN2_PROXY_FRAMEBUFFER=false
PLAN2_LOOKUP=95B3747B-7065-447E-AB1E-53065142C3FC
```

`CoreSimulatorDeviceLookup.device` đã lấy được đúng `SimDevice` từ UDID của device đang boot
(`PLAN2_LOOKUP`), nên đường render IOSurface có đủ device context cho Task 9.

`helperConfigured: false` trong probe vì XCUITest helper chưa được cấu hình ở Task 6.

Sau Task 10/12: `input` chuyển sang **`dtuhid`** khi CoreSimulator >= 1155.4 (Xcode 27); XCUITest
chỉ còn cho `accessibility`. Integration Task 15 xác nhận tap/type/swipe/long-press qua dtuhidd và
tree/find qua XCUITest.

## Diễn giải

| Mục | Kết quả | Bằng chứng |
|---|---|---|
| Render | `ioSurface` | `SimDeviceScreen.initWithDevice:screenID:` + `.screen` tồn tại; proxy `ROCKRemoteProxy` nhận `framebufferSurface` qua dynamic forwarding (Plan 0). |
| Input | `unavailable` khi helper chưa cấu hình | Không có `SimDisplayView.connectedScreen`/`pixelSize`; HID target chưa map. Task 10 dùng XCUITest helper. |
| Accessibility | `unavailable` khi helper chưa cấu hình | `SimAccessibilityManager` không có getter tree; Plan 0 trả `nil`. Task 10 dùng XCUITest. |
| Multi-touch | `unknown` | 17 symbol `IndigoHIDMessageFor*` tồn tại; chưa có bằng chứng gửi thành công tới device. |
| Hardware buttons | `unknown` | `sendWithMessage:freeWhenDone:completionQueue:completion:` tồn tại; chưa kiểm chứng tác động. |

## Sai khác so với plan

Plan Task 6 kiểm tra `SimDeviceScreen.unmaskedSurface`. Trên Xcode 27.1 class này chỉ khai báo
`initWithDevice:screenID:`, `screen`, `screenID`; `unmaskedSurface` không tồn tại. Gate được sửa
thành `SimDeviceScreen.screen`. Bản thân proxy không khai báo `framebufferSurface`
(`responds` trả `false`) nhưng Plan 0 đã gọi thành công và lấy IOSurface 1260×2736, nên gate chỉ
xác nhận selector `screen`; Task 9 sẽ kiểm tra surface thật khi chạy.

`multiTouch`/`hardwareButtons` chỉ chuyển `available` sau integration Task 15; report này không
suy diễn thành có sẵn.

## Rủi ro

- `ROCKRemoteProxy` là class nội bộ; có thể đổi tên/forwarding giữa các bản Xcode. Capability gate
  và fallback `screenshotPolling` vẫn giữ.
- `SimDisplayView.connectedScreen`/`pixelSize` không tồn tại trên Xcode 27.1; nhánh
  `simDisplayView` chỉ dành cho bản Xcode cũ và không được chọn ở đây.
- Input/a11y phụ thuộc XCUITest helper; nếu helper không chạy được, service phải trả
  `capability_unavailable` thay vì giả lập thành công.
