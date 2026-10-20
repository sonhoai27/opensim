# OpenSim Plan 0 — Private API Spike Report

- Ngày chạy: 2026-10-20
- Máy: macOS 27.0.1, Xcode 27.1 (27A9275), arm64
- Device: iPhone Air, iOS 27.0, UDID `95B3747B-7065-447E-AB1E-53065142C3FC`
- Thời gian: khoảng 35 phút
- Phạm vi: chỉ `spike/`, không commit; không tải runtime; không sửa device ngoài phạm vi

## Kết quả

| Khả năng | Kết quả | Bằng chứng | Quyết định |
|---|---|---|---|
| Tìm device CoreSimulator | PASS | `SimServiceContext.sharedServiceContextForDeveloperDir:error:`, `defaultDeviceSetWithError:`, `devices`, `UDID/name/stateString` | Dùng CoreSimulator cho lifecycle |
| Render IOSurface | PASS | `SimDeviceScreen(screenID: 1).screen.framebufferSurface` → IOSurface 1260×2736; ảnh `artifacts/render-ios.png` | Đây là đường render live chính |
| `SimDisplayView` direct | FAIL | `renderableView` tồn tại nhưng `connectedScreen`/`pixelSize`/`unmaskedSurface` không expose; `surfaceLayer.contents=nil`; view capture đen | Không dùng `connectedScreen`; chỉ dùng làm NSView host nếu cần |
| Screenshot | PASS | `xcrun simctl io ... screenshot` → 1260×2736, Settings; `artifacts/render-ios-simctl.png` | Fallback/verification |
| Tap/type | BLOCKED | `NSApp sendEvent` và `mouseDown:` trên `SimDigitizerInputView` không đổi Settings; HID client gửi được message nhưng chưa map đúng `IndigoHIDTarget`; target 0 → Home, target 2/7 → black spinner, target 1/3/4/5/6/8 không đổi | Plan 2 dùng XCUITest helper; HID target mapping là follow-up |
| Accessibility tree | UNAVAILABLE | `SimDisplayRenderableView.accessibilityChildren = nil`; `SimAccessibilityManager` không có tree getter, chỉ có add/translation callback | Plan 2 dùng XCUITest helper |
| watchOS | BLOCKED | `WATCH_RUNTIME missing` | Plan 6 |
| tvOS | BLOCKED | `TV_RUNTIME missing` | Plan 6 |

## Số đo

- Pixel size: **1260×2736**.
- Surface: IOSurface, bytesPerElement `4`, bytesPerRow `5056`, pixel format `0x42475241` (BGRA).
- `maskedFramebufferSurface`: cũng 1260×2736.
- FPS: **chưa đo** — chưa implement damage-rectangle/polling loop; `framebufferSurface` là snapshot pass. Không suy đoán FPS.
- CPU/RSS của probe: **chưa đo** — probe ngắn, không chạy Instruments; không báo số ước lượng.
- Capture: `framebufferSurface` → PNG **thành công**; capture cửa sổ bằng `screencapture` **thất bại** (`could not create image from window/display`, thiếu Screen Recording permission). Không fake ảnh.
- Tap latency: **chưa đo** vì tap chưa tác động được device.

## API/selector hoạt động

- Device context: `SimServiceContext.sharedServiceContextForDeveloperDir:error:`.
- Device set: `SimDeviceSet.defaultDeviceSetWithError:`, `devices`.
- Screen: `SimDeviceScreen.initWithDevice:screenID:` với `screenID = 1`; `.screen` trả `ROCKRemoteProxy` conform `SimDisplayIOSurfaceRenderable`; `framebufferSurface`/`maskedFramebufferSurface` trả IOSurface.
- Display metadata: `displaySize`, `displayPitch`, `displaySizeInBytes` (protocol `SimDisplayRenderable`).
- Display view: `SimDisplayView.setDevice:`, `renderableView`; **không có** `connectedScreen`/`pixelSize` trên Xcode 27.1.
- Input: `SimDeviceLegacyHIDClient.initWithDevice:error:`, `sendWithMessage:freeWhenDone:completionQueue:completion:`; `IndigoHIDMessageForMouseNSEvent`/`IndigoHIDMessageForKeyboardNSEvent` load được. Chưa xác định `IndigoHIDTarget` cho digitizer; gọi Swift getter `ScreenInputDevice.digitizer` từ ObjC bị SIGBUS do ABI.
- Accessibility: `SimAccessibilityManager.addWithDisplayView:`/`addWithRenderableView:` và translation callbacks; không có getter tree. `SimDisplayRenderableView.accessibilityChildren` trả `nil`.

## Quyết định

- **Render:** dùng `SimDeviceScreen(screenID:).screen.framebufferSurface` + Core Image để lấy frame; app host trong NSView. `SimDisplayView` chỉ là host tùy chọn; không phụ thuộc `connectedScreen`/`pixelSize`/`unmaskedSurface`. Fallback cuối là `simctl io screenshot` polling.
- **Input:** chưa dùng private input làm primary. Plan 2 dùng XCUITest helper cho tap/type/swipe/button; HID target mapping là follow-up spike có timebox, không chặn Plan 1.
- **Accessibility:** dùng XCUITest helper; private tree không khả dụng.
- **watch/tv:** blocked vì thiếu runtime; Plan 6 chịu trách nhiệm cài runtime (có owner consent) và chạy lại render/input.
- **Plan 1:** có thể bắt đầu lifecycle/Core/Bridge/CLI vì device access, screenshot và render IOSurface đã có đường thật.
- **Plan 2:** phải sửa contract `DisplaySurface`/input/a11y trước khi implement: render từ `framebufferSurface`, input/a11y qua XCUITest helper. Spec đã ghi nhận kết quả Plan 0.

## Rủi ro còn lại

- IOSurface có thể thay đổi kích thước/format khi rotate hoặc đổi device; cần đọc lại `displaySize`/surface mỗi lần resize.
- `framebufferSurface` là snapshot; cần damage-rectangle callback hoặc polling có kiểm soát để tránh copy 1260×2736 mỗi frame.
- Chưa xác minh input HID target; nếu XCUITest helper quá chậm cho live interaction, mở spike riêng.
- `SimDisplayView` private API có thể khác giữa các bản Xcode; capability gate bắt buộc.

## Việc tiếp theo

1. Cập nhật Plan 2/spec cho `framebufferSurface` + XCUITest fallback (đã cập nhật spec; Plan 2 cần sửa).
2. Bắt đầu Plan 1 (Core + Bridge + lifecycle + CLI).
3. Follow-up spike HID target mapping nếu cần live input latency thấp; không chặn Plan 1.
