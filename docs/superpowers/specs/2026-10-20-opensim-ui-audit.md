# DESIGN AUDIT RESULTS — OpenSim macOS UI

- Ngày: 2026-10-20
- Phạm vi: Plan 4 (app macOS), các UI task của Plan 5 (Storage/Performance), đối chiếu với prototype HTML.
- Nguồn bằng chứng: `docs/superpowers/plans/2026-10-20-opensim-plan-4-macos-app.md`, `docs/superpowers/plans/2026-10-20-opensim-plan-5-storage-performance.md`, `proto/ui/index.template.html`, `proto/ui/shot-devices2.png`, `proto/ui/shot-light.png`.
- Lưu ý: prototype HTML chỉ là bằng chứng bố cục. App production chưa có code; mọi thay đổi dưới đây áp vào Plan 4/5 và spec trước khi thi công.

## Overall Assessment

Plan 4 có kiến trúc native đúng hướng (`NavigationSplitView`, `WindowGroup`, `List`, `ContentUnavailableView`), nhưng UI vẫn bị phủ bởi component tự chế và copy giải thích dài. Prototype càng nặng hơn: 133 mã màu hex, 41 gradient/shadow, 15 cỡ chữ, 463 phần tử chữ dưới 11px, 28 badge và 57 button (55 button có chữ). Đây là nguồn của cảm giác “dashboard/AI”. Hướng đúng không phải thêm theme mới, mà là xoá custom chrome, dùng đúng SwiftUI/macOS có sẵn: `List`, `Table`, `Form`, `ControlGroup`, `ContentUnavailableView`, system text styles, semantic colors và materials.

## Bằng chứng định lượng

| Chỉ số | Giá trị | Ý nghĩa |
|---|---|---|
| Màu hex duy nhất trong prototype | 133 | Quá nhiều token màu tự chế; production phải dùng semantic colors |
| Gradient + shadow | 41 | Trang trí không mang thông tin |
| Cỡ chữ | 15 | Mất hierarchy; nhiều cỡ 8–9.5px |
| Phần tử chữ < 11px | 463 | Khó đọc, không ổn định với Dynamic Type |
| Badge/pill/tag | 28 | Nhiễu thị giác, cạnh tranh với trạng thái chính |
| Button | 57, trong đó 55 có chữ | Quá nhiều hành động cùng cấp |
| Từ hiển thị trong một trạng thái | 215 | Copy dài so với không gian |

Ở Plan 4, mức custom thấp hơn prototype (1 `RoundedRectangle`, 5 `.background(`, 5 `.font(`), nhưng vẫn có các lớp tự chế: sidebar button thủ công, grid card, `StatusBadge`, toolbar 11+ control, activity feed, và các message dài/trùng lặp.

---

## PHASE 1 — Critical

- **Main shell (`AppShell.swift`)**: đang dựng sidebar bằng `VStack` + `ForEach` + `Button`, tự tô `.background(Color.accentColor.opacity(0.14))`, `.clipShape(RoundedRectangle(cornerRadius: 7))`, kèm `Text("OpenSim")` thủ công → thay bằng `List(selection: $tab)` + `Label(...).tag(...)` + `.listStyle(.sidebar)` + `.navigationTitle("OpenSim")` → hành vi chọn, focus, VoiceOver và dark mode do hệ thống lo; bớt một lớp chrome tự chế. Đây là lỗi hierarchy/consistency, không phải thẩm mỹ.

- **Devices screen (`DevicesOverviewView.swift`, `DeviceCardView.swift`)**: sidebar đã là danh sách device, nhưng detail lại là grid card có preview, tên, runtime, state badge, lease owner, metrics và hai button; cùng một device xuất hiện hai nơi → dùng một `Table` native (Name, State, Runtime, Agent, CPU, Memory) với selection và `.inspector` cho preview/metadata; action nằm ở toolbar/context menu → một nguồn sự thật, ít chữ, đúng pattern macOS. Đây là thay đổi interaction, cần anh duyệt.

- **Device window toolbar (`DeviceToolbar.swift`, `DeviceWindowRoot.swift`)**: 11+ control trong `ToolbarItemGroup(placement: .primaryAction)` (Home, Lock, Side, Volume, Rotate L/R, Screenshot, Record, Keyboard, Gesture, Zoom) → giữ 5 primary action có nhãn (Home, Capture, Record, Rotate, Keyboard) trong một bottom bar native bằng `ControlGroup`/`Button`/`Label` + `safeAreaInset(edge: .bottom)`; Lock/Volume/Side/Zoom/Gesture đưa vào `Menu` More; agent status là `Menu`/`Label`, không phải pill tự tô màu → primary action luôn thấy, không nhồi toolbar.

- **Text duplication (`ServiceShellModel.swift`, `StorageShellView.swift`, `PerformanceShellView.swift`)**: `unavailableMessage` dài khoảng 200 ký tự và bị in hai lần (description của `ContentUnavailableView` và một `Text` riêng), cộng thêm `Button Retry` và padding thủ công → dùng một `ContentUnavailableView` với title ngắn, description một câu, một Retry; bỏ `Text` trùng và `VStack` tự dựng. Copy dài/trùng là dấu hiệu rõ nhất của “quá nhiều chữ”.

- **Text ngắn nhưng thừa (`DeviceBootRequiredView.swift`, `DeviceRowView.swift`, `DeviceCardView.swift`)**: “`<name>` is `<state>`”, “Boot the device to open a live screen.”, runtime + state + lease + metric + action trên mỗi card/row → title ngắn + một trạng thái + action; metadata chuyển vào inspector/context menu/`.help`. Mỗi chỗ chỉ giữ một câu trả lời cho “tôi cần biết gì ngay bây giờ?”.

- **Badges/pills tự chế (`StatusBadge.swift`, agent status, runtime cards)**: pill màu theo state và nhiều badge cạnh nhau (28 trong prototype) → dùng `Text` + chấm trạng thái nhỏ hoặc `.badge` của hệ thống; màu không phải tín hiệu duy nhất, luôn có text/`accessibilityLabel` → giảm nhiễu, tăng accessibility.

- **Typography quá nhỏ và quá nhiều cỡ (prototype + Plan 4 snippets)**: 15 cỡ chữ, 463 phần tử dưới 11px, nhiều 8–9.5px, `font(.system(size: 20, weight: .semibold))` trong `AppShell` → dùng system text styles (`.title2`, `.headline`, `.subheadline`, `.caption`, `.caption2`), `.monospacedDigit()` cho số; không đặt cỡ pixel cố định → đọc được, ổn định Dynamic Type, hierarchy rõ.

- **Storage/Performance dashboards (Plan 5 Task 15/16)**: `PerformanceDeviceCard` + sparkline, stat cards/legend/treemap và các nhãn giải thích → dùng `Table` cho device/process, `Chart`/`Gauge` native cho một device được chọn, summary một dòng; bỏ card/legend/bar tự chế → native, ít chữ, cùng một hệ component.

- **Activity screen (`AgentActivityView.swift`, `ActivityRowView.swift`)**: HSplitView + feed card + tag + detail JSON + filter + pause + open audit log cùng lúc → `Table`/`List` với cột Time/Actor/Action/Result/Duration, filter `Picker` ở toolbar, detail trong `.inspector`; JSON để trong disclosure → giảm mật độ và copy.

**Review:** các mục trên sửa đúng ba gốc: (1) hai nguồn điều hướng/selection, (2) action không có hierarchy, (3) copy và màu tự chế. Sửa typography/badge trước sẽ chỉ làm đẹp cái cấu trúc sai.

---

## PHASE 2 — Refinement

- **Typography**: bỏ mọi `font(.system(size:))`; dùng `.font(.headline/.subheadline/.caption)`; section label dùng `.font(.caption.weight(.semibold)).foregroundStyle(.secondary)`, không uppercase tự chế; số dùng `.monospacedDigit()`.
- **Color**: chỉ dùng `.primary`, `.secondary`, `.tertiary`, `.accentColor`, `.tint`; xanh/vàng/đỏ chỉ cho trạng thái có nghĩa; không hex, không gradient, không custom shadow; nền bar dùng `.background(.bar)`/`Material`.
- **Spacing & alignment**: dùng mặc định của `List`/`Table`/`Form`; padding chuẩn 8/12/16; bỏ các giá trị lẻ 7/9/11/13 trong prototype.
- **Iconography**: chỉ SF Symbols, cùng weight/size; primary action dùng `Label` để icon và chữ đi cùng nhau; không SVG tự vẽ.
- **Window chrome**: dùng window native của macOS; không traffic light tự vẽ, không gradient/shadow tự chế; `WindowGroup` + `.defaultSize` + `.windowResizability`; device screen host là phần duy nhất cần custom vì là bridge.
- **Quick switch**: dùng `.sheet`/`Window` với `List` + `.searchable` + keyboard selection; không overlay tự dựng.
- **Copy**: tiêu đề ngắn; mô tả dài chuyển vào `.help`, disclosure hoặc inspector; bỏ “No mock data is shown.”, “owned by the storage service”, các câu giải thích kiến trúc khỏi UI.

---

## PHASE 3 — Polish

- **States**: một pattern duy nhất cho loading (`ProgressView`), empty/unavailable (`ContentUnavailableView`), error (`ContentUnavailableView` + Retry); dùng `.redacted` khi refresh; confirmation bằng `confirmationDialog`/sheet native.
- **Accessibility**: `.accessibilityLabel` cho status dot/icon-only; `.help` cho icon; focus và keyboard shortcut mặc định của List/Table/Button; vùng chạm tối thiểu 28pt; không truyền tải chỉ bằng màu.
- **Dark mode**: để hệ thống tự đổi; test semantic colors/material ở cả hai appearance; không hardcode light/dark.
- **Motion**: dùng animation mặc định; không hiệu ứng trang trí; capture flash/record chỉ là phản hồi ngắn, không loop.
- **Window & menu**: `.commands`/`CommandMenu` native cho Home/Lock/Rotate/Capture; window restoration; không custom menu bar icon nếu không cần.
- **Prototype retirement**: `proto/ui` là sketch; không port CSS, hex, shadow, dock chrome vào app. Chỉ giữ composition đã duyệt (primary action rõ, dock/bottom bar, screen là hero).

---

## DESIGN_SYSTEM UPDATES REQUIRED

- **Không thêm token màu/spacing/font tự chế.** Design system của app là SwiftUI/macOS:
  - Typography: system text styles; `.monospacedDigit()` cho metrics.
  - Color: semantic foreground styles + `accentColor`/`tint`; status chỉ dùng system green/orange/red.
  - Surface: `.bar`, `.regularMaterial`, window background; không gradient/shadow.
  - Controls: `NavigationSplitView`, `List(selection:)`, `Table`, `Form`, `GroupBox`, `ControlGroup`, `Menu`, `Picker`, `ToolbarItemGroup`, `ContentUnavailableView`, `ProgressView`, `Chart`/`Gauge`.
  - Icon: SF Symbols; một weight/size.
- **Ban list trong App code**: hex colors, `Color(red:green:blue:)`, gradient, custom shadow, `RoundedRectangle` tự chế cho control, pill/badge tự chế, `font(.system(size:))`, fixed 8–9px text.
- **Cập nhật spec/Plan 4/5**: thêm “Native-only UI constraints” vào Global Constraints; thay UI task descriptions/snippets; Plan 5 Task 15/16 dùng `Table`/`Chart`.
- **Guard**: thêm bước CI grep/check trong Plan 7 cho các pattern bị ban; fail ở release gate.

---

## IMPLEMENTATION NOTES FOR BUILD AGENT

- `App/Sources/OpenSimApp/App/AppShell.swift`:
  - Xoá `Text("OpenSim")` header, `ForEach` + `Button` + `.background(Color.accentColor.opacity(0.14))` + `.clipShape(RoundedRectangle(cornerRadius: 7))`.
  - Dùng `List(selection: $tab) { ForEach(AppTab.allCases) { item in Label(item.title, systemImage: item.systemImage).tag(item) } }` + `.listStyle(.sidebar)` + `.navigationTitle("OpenSim")`.
- `App/Sources/OpenSimApp/Devices/DevicesOverviewView.swift` và `DeviceCardView.swift`:
  - Thay grid/card bằng `Table` (Name, State, Runtime, Agent, CPU, Memory); selected row mở `.inspector` với preview/metadata; actions ở toolbar/context menu.
  - Xoá `DeviceCardView` hoặc đổi thành row; không preview card, badge, metric và hai button trên mỗi card.
- `App/Sources/OpenSimApp/Shared/StatusBadge.swift`:
  - Thay pill màu bằng `Text(state)` + `.foregroundStyle(.secondary)` + chấm nhỏ; hoặc `.badge` cho count; luôn có accessibility label.
- `App/Sources/OpenSimApp/Windows/DeviceToolbar.swift` và `DeviceWindowRoot.swift`:
  - Bỏ 11+ control khỏi `.primaryAction`.
  - Thêm `DeviceActionBar` mới: 5 `Button` có `Label` (Home, Capture, Record, Rotate, Keyboard) trong `ControlGroup`, đặt bằng `.safeAreaInset(edge: .bottom)`; `.background(.bar)`; `Menu` More cho Lock/Volume/Side/Zoom/Gesture; agent status là `Menu`/`Label`.
  - Xoá custom colors/pills; giữ identifier cho UI test.
  - Ghi chú: “dock ngoài window” của prototype không phải pattern SwiftUI native. Nếu thật sự cần nằm ngoài cửa sổ, phải thêm một `NSPanel`/window và đồng bộ vị trí — đây là thay đổi kiến trúc, không còn “thuần SwiftUI”.
- `App/Sources/OpenSimApp/Shared/ServiceShellModel.swift`, `Storage/StorageShellView.swift`, `Performance/PerformanceShellView.swift`:
  - Rút `unavailableMessage` còn một câu ngắn.
  - Một `ContentUnavailableView` + một Retry; xoá `Text` lặp và `VStack`/padding thủ công.
- `App/Sources/OpenSimApp/Activity/AgentActivityView.swift`, `ActivityRowView.swift`:
  - Thay HSplitView/feed card/tag bằng `Table`/`List` + `.inspector`; filter `Picker` toolbar; JSON trong disclosure; bỏ thumbnail khỏi row nếu không cần.
- Plan 5 Task 15/16:
  - `StorageTabView`: `Table` cột Name/Size/Last Used/Safety; summary `LabeledContent`; clean `confirmationDialog`/sheet; bỏ stat cards/legend/treemap/bar.
  - `PerformanceTabView`: `Table` device/process; `Chart` hoặc `Gauge` cho device được chọn; system colors; bỏ `PerformanceDeviceCard`/sparkline.
- Global:
  - Tất cả text dùng system text styles; không fixed pixel font.
  - Tất cả màu dùng semantic/system; không hex/gradient/shadow.
  - Tất cả primary action dùng `Label` + `Button`; icon-only phải có `.help` + accessibility label.
  - Thêm grep guard ở Plan 7 cho ban list.

## Functional Changes Flagged

1. Grid card → `Table` thay đổi interaction của Devices; cần duyệt.
2. Bottom action bar trong window là native; dock ngoài window cần `NSPanel` + đồng bộ, ngoài phạm vi “thuần SwiftUI”.
3. Bỏ/move runtime section khỏi Devices detail; không đổi API.
4. P0 lease gating (Plan 4 F2 trong review adversarial) và các P0 Plan 3/5 là lỗi chức năng, không nằm trong audit thị giác; phải sửa trước thi công.

## Chờ duyệt

- Phase 1: duyệt hướng native table/list + bottom action bar + bỏ custom cards/pills/text.
- Nếu anh muốn giữ card grid hoặc dock ngoài window, ghi rõ để em điều chỉnh plan thay vì mặc định.
- Sau khi duyệt: cập nhật spec + Plan 4/5, gom 3 P0 adversarial, rồi chạy lại fact-check với scope hẹp.
