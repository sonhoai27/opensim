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

## Focused audit — Devices manager (screenshot 2026-10-20)

Bằng chứng đo trên màn Devices hiện tại (viewport 995×862):

| Chỉ số | Giá trị |
|---|---|
| Từ hiển thị | 123 |
| Phần tử chữ < 11px | 40 |
| Button có chữ | 12 |
| Badge/pill/tag toàn trang | 22 |
| Tab top-level + link Workspace | 4 + 4 (trùng 3 mục) |
| Device card / runtime card | 4 / 3 |
| “Booted” xuất hiện | 3 lần |
| “agent-42” xuất hiện | 2 lần |
| “runtime” xuất hiện | 4 lần |
| Nút Install / Open | 5 / 2 |

### Phase 1 — Critical

- **Điều hướng trùng**: 4 tab top-level (Devices/Storage/Performance/Activity) trùng với 4 link Workspace trong sidebar → sidebar là nguồn điều hướng duy nhất; bỏ hàng tab; header chỉ còn title + một primary action. Vì sao: người dùng phải chọn giữa hai nơi cho cùng một đích; macOS native dùng sidebar.
- **Thông tin trùng**: “Booted” xuất hiện ở titlebar pill, section header, card badge; “agent-42” ở titlebar, card, agent strip; “runtime” ở sidebar badge, card, runtime card, footer → mỗi loại thông tin chỉ giữ một chỗ: state trong row, agent trong một banner/Menu, runtime trong màn Runtimes. Vì sao: mắt không biết đâu là trạng thái chuẩn.
- **Primary action không rõ**: 12 button cùng hiện (Refresh, New Device, Open ×2, Boot, More ×4, Install ×5, Pause agent, Take control) → một primary “Open” cho device đang chọn, các action còn lại vào context menu/toolbar; Install chỉ ở màn Runtimes. Vì sao: mọi thứ nổi bật thì không thứ nào nổi bật.
- **Card quá nặng**: mỗi card có preview lớn + tên + iOS version + resolution + state badge + agent badge + CPU/RAM + nút Open + More; 4 card chiếm chỗ nhưng không quét nhanh được → dùng `Table`/`List` native (Name, State, Agent) + inspector cho preview/metadata; hoặc card compact 1 preview nhỏ + 2 dòng nếu muốn giữ ảnh. Vì sao: grid card là dashboard, không phải màn quản lý device.
- **Copy thừa**: subtitle “5 simulators · 2 booted · 1 agent controlling iPhone Air”; section “Booted / 2 devices · 1 lease”; card “iOS 27.0 · 1260 × 2736”, “Last boot 2h ago”, “Available”, “38% CPU · 2.4 GB”; agent strip “MCP · ui.tap on Search field · 18 ms · lease expires in 3:42” → bỏ subtitle/counts, card chỉ giữ tên + state; agent strip còn “agent-42 · 3:42” + Take control, chi tiết trong Activity; metadata trong inspector. Vì sao: 123 từ cho một màn chọn device là quá nhiều.
- **Runtimes trong màn chính**: 3 runtime card + 5 nút Install (cả card Watch) lặp lại “Manage Runtimes” ở sidebar → chuyển thành màn/section Runtimes riêng; device thiếu runtime hiện một trạng thái + action rõ trong row, không lặp card. Vì sao: runtime là cấu hình, không phải device.
- **Badge/màu/typography**: 22 badge, 40 chữ <11px, nhiều màu (xanh, cam, vàng, tím, xanh dương) cùng lúc → state bằng text + chấm nhỏ; agent dùng một accent; runtime missing dùng một warning; system text styles, không 8–9px. Vì sao: màu mất nghĩa khi dùng cho mọi thứ; chữ nhỏ không đọc được.

### Phase 2 — Refinement

- Sidebar native `List(selection:)` + `.listStyle(.sidebar)`; bỏ custom button hover/background.
- Main `Table`/`List` với selection + `.inspector`; search/toolbar native; một primary action.
- Agent strip thành banner chỉ khi có lease; một dòng ngắn; Pause/Take control trong `Menu`.
- Runtimes thành màn riêng; `Install`/`Delete` ở đó; device row thiếu runtime chỉ hiện một warning.
- Copy ngắn; bỏ count/subtitle/telemetry; `.help` cho shortcut.
- System text styles/semantic colors/SF Symbols; bỏ card gradients/pills/purple accent.

### Phase 3 — Polish

- Empty/loading/error native; selection restoration; keyboard focus; VoiceOver cho state dot.
- Dark mode tự động; hit target ≥28pt; không chỉ dùng màu.
- Inspector chỉ hiện khi cần; không mở rộng mặc định.

### Implementation notes (proto/Plan 4)

- `#view-devices`: bỏ subtitle, section count, runtime section, card badges/metrics; chọn Table/List hoặc card compact.
- `AppShell`/proto sidebar: bỏ top tabs; workspace chỉ còn Storage/Performance/Activity; bỏ duplicate New Device/Manage Runtimes nếu đã có toolbar.
- Agent: một banner/Menu; bỏ pill agent ở titlebar và badge “agent-42 controlling” trên card.
- Runtime: màn Runtimes riêng; bỏ 3 runtime card khỏi Devices; chỉ một Install action ở nơi thiếu runtime.
- Button: Open là primary; Boot/More vào context menu; Refresh/New Device ở toolbar.

## Focused audit — Storage (screenshot 2026-10-20)

Bằng chứng đo trên view Storage hiện tại (viewport 995×862):

| Chỉ số | Giá trị |
|---|---|
| Từ hiển thị | 172 |
| Phần tử chữ < 11px | 146 |
| Stat card | 4 |
| Legend item | 5 |
| Category row | 6 |
| Table row | 5 |
| Safety badge | 5 |
| Button | 2: Review clean plan, Reveal in Finder |
| Sample note | Có |
| Trạng thái scan/loading/empty/error/plan | Không có trong UI |

### Phase 1 — Critical

- **Cùng một dữ liệu được trình bày 4 lần**: 4 stat card + stacked bar/legend + category side list + table size; tất cả nói cùng “nhóm nào chiếm bao nhiêu” → một summary ngắn + một Table/List duy nhất. Vì sao: mắt phải đối chiếu 4 nguồn để trả lời một câu.
- **Hai kiểu selection chồng nhau**: row highlight để xem detail, checkbox để chọn clean; CTA “Review clean plan” nằm trong detail panel nên trông như chỉ dọn item đang xem, trong khi checkbox có thể chọn nhiều item → checkbox là **nguồn duy nhất** cho clean; row click chỉ đổi detail; CTA ghi rõ `Review clean plan (N items · X GB)` ở footer/toolbar. Vì sao: người dùng phải biết chắc cái gì sẽ bị xoá.
- **CTA chính bị chôn và không có ngữ cảnh**: “Review clean plan” là button xanh trong panel phải, không hiện số item/bytes sẽ dọn, không disable khi chưa chọn; `Reveal in Finder` cùng cấp → một primary ở footer gắn với selection; `Reveal in Finder` chỉ trong detail. Vì sao: destructive action phải có scope rõ.
- **Control giả**: category rows và checkbox là `div/span` không có handler; 2 button không có handler; category trông clickable nhưng không lọc → prototype có thể tĩnh, nhưng production phải implement hoặc bỏ; không để control trông bấm được mà không làm gì. Vì sao: niềm tin vào UI.
- **In-use/protected chưa bị chặn thật**: row “iPhone Air”/“iOS runtime” có badge In use nhưng checkbox vẫn hiện như item thường, chưa disabled, chưa có lý do trong row → lock icon + text, checkbox disabled, tooltip/detail nêu lý do; không truyền tải chỉ bằng màu. Vì sao: nguy cơ dọn dữ liệu đang chạy.
- **Thiếu toàn bộ state của scan/clean**: không có initial/no-scan, scanning, ready, applying, done, error, partial/inaccessible, scan/clean collision → dùng `ContentUnavailableView`, `ProgressView`, `.redacted`; CTA theo state. Vì sao: storage là tác vụ nền dài, người dùng cần biết đang ở đâu.
- **Text/màu custom**: 146 phần tử <11px; sample note, legend, size bar, safety pill và 5 màu category → system text styles; màu chỉ cho safety/selection; bỏ sample note khỏi production; size là số, không cần thanh màu. Vì sao: đọc nhanh và đúng.

### Phase 2 — Refinement

- Header `Storage`; toolbar: filter category, `Scan` secondary, `Clean Selected…` primary (disabled nếu chưa chọn safe item).
- Summary một dòng: `84.2 GB reclaimable · 70 GB free · APFS approximate`.
- `Table` hoặc `List` native: Item, Category, Size, Last Used, Safety; sortable; checkbox chỉ cho item safe; row click mở detail; category filter thay side list.
- Footer sticky: `N selected · X GB` + `Review clean plan`; action luôn thấy.
- Detail: metadata + lý do blocked + `Reveal in Finder`; không có primary clean.
- Clean sheet: danh sách item, tổng thu hồi, item blocked, plan token TTL, typed confirmation >20 GB, Apply; progress/result.
- Bỏ 4 stat card, stacked bar/legend, category side list, size bar, safety pill, sample note, warning dài trong panel.

### Phase 3 — Polish

- Empty/loading/error/partial states native; scan progress có percent/bytes; clean progress theo item.
- Disable scan khi clean và ngược lại; plan token expiry/reuse error có recovery.
- Accessibility: checkbox label, table sort, keyboard, VoiceOver cho lock/safety.
- Dark mode tự động; APFS approximate label; size format MB/GB.

### State / CTA matrix

| State | Thông tin | Primary CTA | Secondary |
|---|---|---|---|
| Chưa scan | Empty + lần scan gần nhất | **Scan Storage** | — |
| Scanning | Progress, kết quả cũ/partial | Disabled/Progress | Cancel nếu hỗ trợ |
| Ready, chưa chọn | Summary + bảng | **Clean disabled** | Scan Again |
| Ready, đã chọn safe item | N selected · X GB | **Review clean plan** | Scan Again |
| In use/protected | Lock + lý do; checkbox off | — | Reveal in Finder |
| Plan sheet | Items, blocked, total, TTL | **Apply clean** | Cancel |
| Applying | Progress từng item | Disabled | — |
| Done | Bytes reclaimed, kết quả | **Done** | Scan Again |
| Error | ContentUnavailableView + recovery | **Retry** | Doctor |
| Partial/inaccessible | Note root lỗi, dữ liệu partial | Retry | Reveal |
| Scan/clean collision | Busy | Disabled | — |
| Plan expired/apply failed | Error + lý do | Re-plan | Cancel |

### Implementation notes

- `StorageTabView` (Plan 5 Task 15): thay stat card/legend/category list/table/detail hiện tại bằng summary + `Table`/`List` + footer CTA + `ContentUnavailableView`; checkbox selection thật; in-use disabled; plan sheet.
- `StorageShellView` (Plan 4 Task 11): giữ state probe/loading/error nhưng message ngắn; không duplicate text.
- `StorageService` (Plan 5): state scan/clean tuần tự; UI chỉ hiển thị; mọi kích thước approximate theo APFS.
- Proto hiện tại chỉ là mock tĩnh; chưa nối scan/clean. Sau khi duyệt layout mới dựng proto Storage v2, không sửa plan/spec.

## Focused audit — Agent Activity (screenshot 2026-10-20)

Bằng chứng đo trên view Agent Activity hiện tại:

| Chỉ số | Giá trị |
|---|---|
| Từ hiển thị | 126 |
| Phần tử chữ < 11px | 54 |
| Feed item | 5 |
| Session card | 2 |
| Tag/pill | 6 |
| Filter button | 4: All/MCP/CLI/Human |
| Button | 7: filters + Pause agent + Take control + Release lease |
| Event detail / Open Device | Không có |
| State paused/empty/loading/error/history | Không có |

### Phase 1 — Critical

- **“Pause agent” sai nghĩa**: trong model, pause là dừng **ingest feed**, không phải dừng agent; label hiện tại khiến người dùng tưởng can thiệp vào agent → đổi thành **Pause feed** ở toolbar, có banner `Feed paused · N new` + Resume. Nếu muốn pause agent thật thì là feature riêng, không có trong spec.
- **“Release lease” sai scope**: session đang hiển thị thuộc agent-42; người dùng không phải owner. Release lease của session khác là hành động takeover/destructive, không được là nút đỏ trong card monitor → chỉ hiện khi app sở hữu lease; còn lại phải Take control qua confirmation.
- **Thiếu primary action thật**: không có **Open Device**. Activity là nơi thấy agent làm gì; hành động tiếp theo tự nhiên là mở device (observe) để xem, rồi mới Take control nếu cần → Open Device primary cho event/session đang chọn; Take control secondary + sheet confirm.
- **Không inspect được event**: feed row chỉ đọc, không selection/detail; payload, args, result, duration, ảnh không xem được. Cần `Table` + `.inspector` detail; thumbnail chỉ trong detail.
- **Tag/pill/color noise**: 6 tag (MCP/agent) và filter pill trong từng row; session cards tự tạo style; dùng cột Client/Result, 1 dot trạng thái, filter `Picker`; không pill mỗi dòng.
- **Session card trùng và nặng**: 2 card layout khác nhau, thông tin session đã có trong feed; dùng một session summary/table gọn (owner, client, device, lease, TTL); không card + nút riêng.
- **Thiếu state**: live/paused/queued, loading history, empty, error/disconnected, filter no results, lease expired, event selection, takeover confirmation; dùng native `ContentUnavailableView`/`ProgressView`/sheet.
- **Text/help dài**: 54 chữ <11px; note takeover dài trong card; đưa vào `.help`/sheet; system text styles.
- **Thiếu Open Audit Log**: note nhắc audit log nhưng không có action; thêm secondary trong toolbar.

### Phase 2 — Refinement

- Header `Agent Activity`; toolbar: Live/Paused indicator, filter `Picker` (All/MCP/CLI/Human), Pause/Resume feed, Open Audit Log.
- Main `Table`: Time, Session/Actor, Action, Target, Result, Duration; selection + `.inspector` detail (payload/args/result, session/lease, Open Device).
- Session summary/table gọn: owner/client/device/lease/TTL; không card.
- Primary `Open Device`; `Take control` secondary với confirmation sheet (owner, TTL, grace 3s); `Release` chỉ khi bạn là owner.
- Paused banner: `Feed paused · N new events` + Resume.
- Empty/loading/error/filter states native; search theo action/session/device nếu cần.
- Bỏ tag/pill per row, custom colors, note dài; system text styles/SF Symbols.

### Phase 3 — Polish

- Live update giữ selection; filter áp dụng cho live/history; paused buffer count.
- Audit history tải theo trang; copy payload; mở audit log; thumbnail trong detail.
- Lease expired/revoked, takeover grace, agent revoked, session closed, disconnected/retry.
- Keyboard: Return mở device; Search/Clear; VoiceOver cho result/time.

### State / CTA matrix

| State | Thông tin | Primary | Secondary |
|---|---|---|---|
| Live, chưa chọn | Feed/table live | Pause feed (toolbar) | Filter, Open Audit Log |
| Live, chọn event | Event payload/args/result | **Open Device** | Take control nếu session agent |
| Live, chọn session agent | Owner, TTL, device | **Open Device** (observe) | Take control (confirm) |
| Live, session của bạn | Lease TTL | **Open Device** | Release (confirm) |
| Paused | Banner + queued N | **Resume feed** | Filter |
| Empty | No activity yet | Open Devices | — |
| Loading history | ProgressView | — | — |
| Error/disconnected | ContentUnavailableView | **Retry** | Doctor |
| Filter no results | No matches | Clear filters | — |
| Lease expired/revoked | Session cập nhật | Open Device nếu booted | — |
| Takeover sheet | Owner, TTL, grace | **Take control** | Cancel (default) |

### Implementation notes

- `AgentActivityView`: bỏ HSplitView/feed card/session card; dùng `Table` + inspector + toolbar; session summary/table.
- `AgentActivityModel`: `isPaused` là pause feed; `pausedCount`; selection; filter; open device; không đổi thành pause agent.
- `ActivityRowView`: cột Time/Session/Action/Target/Result/Duration; không tag/pill; thumbnail chỉ detail.
- `ActivityDetailView`: payload/args/result, session/lease, Open Device, Take control (confirm).
- Session card: owner/TTL; Release chỉ khi app sở hữu; không Release lease của agent.
- Proto hiện tại là mock tĩnh; filter/Pause/Release chưa nối; dựng Activity v2 sau khi duyệt layout.

## Chờ duyệt

- Phase 1: duyệt hướng native table/list + bottom action bar + bỏ custom cards/pills/text.
- Nếu anh muốn giữ card grid hoặc dock ngoài window, ghi rõ để em điều chỉnh plan thay vì mặc định.
- Sau khi duyệt: cập nhật spec + Plan 4/5, gom 3 P0 adversarial, rồi chạy lại fact-check với scope hẹp.
