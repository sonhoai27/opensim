# OpenSim — Design Spec

- Ngày: 2026-10-19
- Trạng thái: Draft để anh Sơn review
- Tên tạm: OpenSim (repo `open-simulator`, CLI `opensim`, app `OpenSim.app`)
- Owner: anh Sơn
- Môi trường tham chiếu: macOS 27.0.1, Xcode 27.1 (27A9275), runtime iOS 27.0

## 1. Bối cảnh

Xcode 27 bỏ `Simulator.app`; thay bằng Device Hub (`DeviceHub.app`, bundle `com.apple.dt.Devices`). Trên máy tham chiếu:

- `Simulator.app` không còn trong Xcode và `open -a Simulator` thất bại.
- `xcrun simctl` vẫn hoạt động đầy đủ cho lifecycle, install, launch, screenshot, record, log.
- `SimulatorKit.framework` và `CoreSimulator.framework` vẫn còn; `SimulatorKit` export các lớp `SimDisplayView`, `SimDeviceScreen`, `SimDeviceLegacyHIDClient` và các hàm C `IndigoHIDMessageFor*`.
- `simctl` không có lệnh tap, swipe, type, đọc accessibility tree. Đây là khoảng trống lớn nhất cho AI agent.

Mục tiêu của OpenSim là công cụ local, open-source, agent-first: một lõi điều khiển simulator của Apple, có CLI, MCP và app macOS đầy đủ, kèm quản trị dung lượng và tài nguyên. OpenSim không viết lại emulator; OpenSim điều khiển runtime Apple.

## 2. Mục tiêu

1. Một lõi duy nhất cho app, CLI và MCP; không lặp logic giữa các client.
2. Điều khiển đầy đủ simulator: device, runtime, app, screen, input, accessibility, log.
3. UI macOS full gesture parity: tap, swipe, long-press, drag, pinch, rotate, multi-touch, bàn phím, nút cứng, xoay máy.
4. Agent-first: JSON ổn định, lỗi có cấu trúc, UI tree ngữ nghĩa, lease rõ ràng, thao tác phá huỷ có xác nhận.
5. Quản trị dung lượng đĩa và CPU/RAM theo từng device.
6. Hỗ trợ iOS/iPadOS, watchOS, tvOS; visionOS là plan riêng sau.
7. Phân phối open-source qua Homebrew; yêu cầu full Xcode 27.1+.

## 3. Không mục tiêu

- Không viết lại simulator runtime hoặc nhân iOS.
- Không hỗ trợ Android.
- Không làm cloud device farm, multi-tenant remote server.
- Không phát hành qua Mac App Store (private API).
- Không thay thế Instruments: chỉ số liệu runtime, không có profiling sâu.
- Không hỗ trợ thiết bị thật trong phạm vi ban đầu; có plan riêng sau.
- Không hỗ trợ visionOS trong phạm vi ban đầu; có plan riêng sau.
- Không tích hợp LLDB/debugger trong phạm vi ban đầu; có plan riêng sau.

## 4. Quyết định phạm vi đã chốt

| Chủ đề | Quyết định |
|---|---|
| Runtime | Dùng CoreSimulator của Apple, không viết emulator |
| Nền tảng | iOS/iPadOS + watchOS/tvOS; visionOS sau |
| UI | Full gesture parity, nhiều cửa sổ, quick switch |
| Agent | CLI + MCP stdio + MCP HTTP loopback |
| Quản trị | Disk + CPU/RAM theo device |
| Phân phối | Open-source local, Homebrew, yêu cầu Xcode |
| Thiết bị thật | Kiến trúc sẵn abstraction, triển khai ở plan riêng |
| Ngôn ngữ UI | Native macOS (SwiftUI + AppKit), không web wrapper |

## 5. Kiến trúc

### 5.1 Các tầng

| Tầng | Trách nhiệm | Phụ thuộc |
|---|---|---|
| `OpenSimCore` | Domain model, protocol, command catalog, lease/session rules, storage rules, metrics aggregation | Không private API |
| `OpenSimBridge` | Duy nhất chạm CoreSimulator/SimulatorKit; dynamic loading; capability check; fallback `simctl` | `OpenSimCore` |
| `OpenSimDaemon` | Control plane: lifecycle, session, lease, event bus, storage scan, metrics; HTTP/SSE loopback | Core + Bridge |
| `OpenSimCLI` | `opensim` command line, JSON-first | Core + daemon client |
| `OpenSimMCP` | MCP stdio proxy + HTTP endpoint host | Core + daemon client |
| `OpenSimApp` | App macOS, render trực tiếp bằng Bridge, điều khiển qua daemon | Core + Bridge + daemon client |

`OpenSimCLI` và `OpenSimMCP` nằm trong cùng một executable `opensim` với subcommand `opensim mcp`; không cần binary riêng.

### 5.2 Mô hình process

- `OpenSimDaemon` chạy trong user session qua LaunchAgent `dev.opensim.daemon`.
- Một instance duy nhất được bảo vệ bằng lock file và health check.
- Daemon ghi state vào `~/Library/Application Support/OpenSim/daemon.json` (quyền `0600`):
  - `pid`, `port`, `token`, `version`, `xcodeVersion`, `startedAt`.
- CLI, MCP và app đọc state file để kết nối. Nếu daemon chưa chạy, CLI/app auto-start và chờ health check tối đa 5 giây.
- Đóng app không làm chết daemon; agent đang chạy tiếp tục làm việc.
- App render screen **in-process** bằng `SimDisplayView`; app không stream frame qua daemon.
- App lấy lifecycle/lease/audit qua daemon; input của người dùng được gửi trực tiếp bằng Bridge sau khi app giữ lease `control`.
- CLI/MCP thao tác input qua daemon; daemon dùng Bridge để inject HID.
- Nếu daemon chết, app hiển thị trạng thái mất kết nối và có nút restart; device đang boot vẫn tiếp tục ở CoreSimulator.

### 5.3 Session và lease

- `Session` đại diện cho một client (app, CLI invocation, MCP server, agent).
- `Lease` theo device, có hai mode:
  - `control`: tối đa một owner; cho phép input, install, launch, erase, delete.
  - `observe`: nhiều owner; chỉ đọc screenshot, tree, log, metrics.
- Lease có TTL mặc định 5 phút, gia hạn bằng heartbeat mỗi 30 giây; hết hạn tự giải phóng.
- App lấy `control` khi cửa sổ device được focus và chưa có owner khác. Nếu agent đang giữ, app hiện banner "Agent đang điều khiển" kèm nút `Take control`.
- `Take control` chuyển lease sau khi owner cũ đồng ý (app/CLI) hoặc sau grace period 3 giây đối với lease của agent; mọi lần chuyển ghi audit.
- Thao tác đọc không cần lease. Thao tác ghi không có lease trả lỗi `lease_required`; nếu lease thuộc owner khác trả `lease_conflict` kèm owner, mode, expiresAt.
- Ngoại lệ: thao tác toàn cục không gắn device (`device_create`, `runtime_download`, `runtime_install`, `runtime_delete`) cần session hợp lệ, confirm/audit theo loại thao tác, nhưng không cần device `control` lease.
- CLI tạo lease ngắn hạn tự động khi chạy một lệnh ghi, trừ khi truyền `--session`.
- MCP server giữ lease theo session và heartbeat tự động.

### 5.4 Ranh giới private API

Mọi private API nằm trong `OpenSimBridge`. Không target nào khác được import hoặc gọi trực tiếp.

| Nhu cầu | Đường chính | Fallback | Mức rủi ro |
|---|---|---|---|
| Device list/lifecycle | CoreSimulator ObjC (`SimServiceContext`, `SimDeviceSet`, `SimDevice`) | `simctl` | Thấp |
| Screenshot/video | `simctl io` | `SimDeviceScreen.unmaskedSurface` | Thấp |
| Live screen | `SimulatorKit.SimDisplayView` + `SimDeviceScreen` | IOSurface + view tự dựng, cuối cùng là screenshot polling | Cao |
| Tap/swipe/type/button | `SimDisplayView` digitizer; `IndigoHIDMessageFor*` + `SimDeviceLegacyHIDClient` | XCUITest helper (chậm, chỉ dùng khi HID fail) | Cao |
| Accessibility tree | `SimulatorKit.SimAccessibilityManager` | XCUITest helper trong plan 2 | Rất cao |
| Runtime install/delete | `simctl runtime add/delete`; `xcodebuild -downloadPlatform/-importPlatform` cho download/import | CoreSimulator ObjC | Thấp |
| Log | `simctl spawn booted log stream` | file log trong device data | Thấp |

Nguyên tắc:

1. Dynamic load bằng `dlopen`/`dlsym` và Objective-C runtime; không link cứng private framework ở build time.
2. Mỗi API có `respondsToSelector`/symbol check và capability record.
3. `simctl` được ưu tiên cho mọi thao tác có thể làm bằng `simctl`.
4. Private API chỉ dùng cho phần `simctl` không có: render, HID, accessibility.
5. Không dùng private API để vượt quyền hệ thống, không đọc dữ liệu ngoài simulator.
6. `opensim doctor` in ra bảng capability: `render`, `hid`, `a11y`, `screenshot`, `video`, `runtime`, `watch`, `tv`.

Đường dẫn:

- Developer dir: `xcode-select -p`, mặc định `/Applications/Xcode.app/Contents/Developer`.
- CoreSimulator: `/Library/Developer/PrivateFrameworks/CoreSimulator.framework`.
- SimulatorKit: `<Contents>/SharedFrameworks/SimulatorKit.framework`, với `<Contents>` là thư mục cha của Developer dir.
- Device data: `~/Library/Developer/CoreSimulator/Devices/<UDID>`.

Bridge chỉ chấp nhận developer dir nằm dưới `/Applications` hoặc `/Library/Developer`; từ chối path tùy ý từ client.

### 5.5 Luồng chính

**Boot device**

1. Client gửi `POST /v1/devices/{udid}/actions` với `{"action":"boot","wait":true}`.
2. Daemon xin lease `control`.
3. Bridge gọi `simctl boot` hoặc `SimDevice.boot`.
4. Daemon chờ trạng thái `Booted`, phát event `device.state.changed`.
5. Client nhận kết quả kèm screen descriptor.

**Agent thao tác**

1. MCP `session_acquire` lấy lease `control`.
2. `ui_tree` đọc cây ngữ nghĩa; agent chọn element.
3. `ui_tap` với tọa độ hoặc selector; daemon chuẩn hóa tọa độ theo screen scale/rotation.
4. Bridge inject HID; daemon chờ frame ổn định ngắn (tối đa 250 ms) nếu client yêu cầu `settle`.
5. Trả kết quả kèm screenshot tùy chọn.

**Người dùng giành quyền**

1. App mở cửa sổ device, gửi `POST /v1/leases` mode `control`.
2. Nếu agent đang giữ, daemon trả `lease_conflict`; app hiện banner và nút `Take control`.
3. Người dùng bấm `Take control`; daemon thu hồi lease cũ sau grace period, ghi audit, phát event.
4. App bật input; agent nhận lỗi `lease_revoked` ở lần gọi tiếp theo.

**Tạo device**

1. Client gửi `device_create` với `name`, `deviceType`, `runtime` (version cụ thể, không chỉ platform).
2. Daemon kiểm tra tên chưa tồn tại, runtime đã cài và cùng platform với device type.
3. Bridge tạo device ở trạng thái `Shutdown`; không auto-boot.
4. Daemon trả device mới, phát event `device.created`; UI chọn row mới và hiện CTA `Boot & Open`.

**Cài runtime (kể cả version cũ)**

1. Client chọn `runtime_download` (`platform`, `version`) hoặc `runtime_install` (`path` tới `.dmg`).
2. Daemon kiểm tra version: download chỉ dùng catalog Xcode hỗ trợ; file import dùng `simctl runtime add`.
3. Daemon phát progress event khi backend cung cấp; client có thể cancel trước khi hoàn tất. UI được phép hiển thị ProgressView indeterminate nếu chưa có percent.
4. Khi cài xong, device đang `Runtime missing` dùng đúng runtime đó chuyển sang `Shutdown`; UI và runtime picker của New Simulator cập nhật.
5. Xoá runtime bị chặn nếu còn device tham chiếu; nếu không còn device, xoá qua `simctl runtime delete`.

**Storage scan**

1. Client gọi `POST /v1/storage/scans`.
2. Daemon scan nền, trả `scanId`.
3. Client theo dõi qua SSE event `storage.scan.progress` hoặc poll `GET /v1/storage/scans/{id}`.
4. Kết quả có size approximate, lastUsed, category, safety flags.

**Metrics**

1. Daemon sample mỗi giây.
2. UI subscribe SSE khi Performance được bật và view Performance mở.
3. CLI/MCP đọc snapshot hoặc ring buffer 10 phút.

### 5.6 Tương thích

- macOS 27.0+; arm64.
- Xcode 27.1 là bản chính; Xcode 27.0 được hỗ trợ nếu fingerprint khớp.
- Kiểm tra phiên bản Xcode và fingerprint của SimulatorKit/CoreSimulator khi khởi động.
- Nếu fingerprint lạ: chuyển `compatMode=unknown`, tắt các tính năng private không chắc chắn, hiện cảnh báo trong `doctor` và UI.
- Không hỗ trợ Command Line Tools-only; app yêu cầu full Xcode.
- Xcode nâng cấp có thể làm hỏng private API; release notes ghi rõ version đã test.

## 6. Domain model

| Entity | Trường chính |
|---|---|
| `Device` | `udid`, `name`, `platform`, `deviceType`, `runtime`, `state`, `isAvailable`, `dataPath`, `lastBootedAt` |
| `Runtime` | `identifier`, `name`, `platform`, `version`, `build`, `isAvailable`, `path`, `sizeBytes?`, `source?` (`system` / `xcode-catalog` / `file`), `deviceCount?` |
| `App` | `bundleID`, `displayName`, `version`, `build`, `dataContainer`, `appContainer` |
| `Screen` | `screenID`, `width`, `height`, `scale`, `rotation`, `displayClass` |
| `Session` | `id`, `clientKind`, `clientName`, `createdAt`, `lastSeenAt` |
| `Lease` | `id`, `deviceUDID`, `sessionID`, `mode`, `ownerName`, `acquiredAt`, `expiresAt` |
| `UIElement` | `id`, `role`, `label`, `identifier`, `value`, `frame`, `enabled`, `selected`, `children` |
| `StorageItem` | `id`, `category`, `path`, `sizeBytes`, `lastUsedAt`, `safeToDelete`, `reason`, `children` |
| `MetricSample` | `deviceUDID`, `timestamp`, `cpuPercent`, `memoryBytes`, `processCount`, `diskReadBytes`, `diskWriteBytes` |
| `AuditEvent` | `id`, `timestamp`, `actor`, `sessionID`, `leaseID`, `action`, `target`, `result`, `durationMs` |

State machine device: `(new) -> Shutdown`; `Shutdown -> Booting -> Booted -> ShuttingDown -> Shutdown`; `Booted -> Erasing -> Shutdown`; `Shutdown -> Deleting`. Mọi transition phát event và ghi audit.

State machine runtime (operation, không phải field `isAvailable`): `available -> downloading -> installing -> installed -> removing -> unavailable`; lỗi/cancel từ `downloading`/`installing` trở về trạng thái trước đó. Runtime đã cài vẫn có thể `deviceCount > 0`; delete chỉ hợp lệ khi `deviceCount == 0`.

## 7. CLI `opensim`

### 7.1 Quy ước

- `--json` in envelope JSON; không có `--json` in bảng cho người.
- `--device <udid|name>` chọn device; nếu bỏ trống dùng device mặc định của session hoặc device booted duy nhất.
- `--session <id>` dùng session có sẵn; nếu không có, CLI tạo session ngắn hạn.
- `--wait` chờ trạng thái đích; `--timeout <seconds>` mặc định 60.
- Thao tác phá huỷ luôn cần `--yes` hoặc plan token; `--yes` chỉ bỏ prompt tương tác, không bỏ qua yêu cầu xác nhận của daemon.
- Exit code: `0` thành công, `2` usage, `3` not found, `4` conflict, `5` unsupported, `6` permission, `7` confirmation required, `10` internal.
- Envelope:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "data": {},
  "error": null,
  "meta": {
    "requestId": "01JB7YV6Z8K4Q2W9R3T5M1N0P8",
    "durationMs": 42
  }
}
```

- Lỗi:

```json
{
  "schemaVersion": 1,
  "ok": false,
  "data": null,
  "error": {
    "code": "lease_conflict",
    "message": "Device is controlled by another session",
    "details": {"owner": "agent-42", "expiresAt": "2026-10-19T17:00:00Z"},
    "recovery": "Take control or wait for the lease to expire",
    "retryable": true
  },
  "meta": {"requestId": "01JB7YV6Z8K4Q2W9R3T5M1N0P8", "durationMs": 12}
}
```

### 7.2 Lệnh

| Nhóm | Lệnh | Ghi chú |
|---|---|---|
| device | `list`, `get`, `create`, `clone`, `boot`, `shutdown`, `erase`, `delete`, `rename`, `status` | delete/erase cần xác nhận |
| device | `pair`, `unpair`, `location`, `appearance`, `privacy`, `push`, `openurl`, `pasteboard` | watch pair ở plan 6 |
| runtime | `list`, `download`, `install`, `delete`, `verify` | `download` nhận platform + version Xcode hỗ trợ; `install` nhận `.dmg`; delete chặn nếu còn device dùng |
| app | `list`, `install`, `uninstall`, `launch`, `terminate`, `info`, `container`, `data export`, `data import` | install nhận `.app`, `.ipa` đã giải nén |
| ui | `screenshot`, `record start`, `record stop`, `info` | record dùng `simctl io` |
| ui | `tap`, `swipe`, `long-press`, `drag`, `pinch`, `rotate`, `scroll`, `type`, `key`, `button`, `wait` | input qua daemon |
| ui | `tree`, `find`, `tap --on <selector>`, `act` | selector: `role=`, `label=`, `id=`, `text=` |
| log | `tail`, `stream`, `crash` | `tail` có cursor |
| session | `list`, `acquire`, `release`, `status` | |
| storage | `scan`, `list`, `clean`, `reveal` | clean có plan/apply |
| perf | `top`, `watch`, `stats` | |
| doctor | `doctor` | kiểm tra môi trường/capability |
| daemon | `start`, `stop`, `restart`, `status`, `logs` | |
| mcp | `mcp --stdio`, `mcp --http` | HTTP loopback |

Ví dụ:

```bash
opensim device boot --device "iPhone Air" --wait
opensim app install ./Build/MyApp.app --device "iPhone Air"
opensim app launch com.example.myapp --device "iPhone Air"
opensim ui screenshot --device "iPhone Air" --out /tmp/screen.png
opensim ui tree --device "iPhone Air" --json
opensim ui tap --on 'label=Login' --device "iPhone Air"
opensim ui type "hello@example.com" --device "iPhone Air"
opensim runtime download --platform iOS --version 26.4
opensim runtime install ~/Downloads/iOS_26.3_Simulator_Runtime.dmg
opensim storage scan --json
opensim perf top --device "iPhone Air"
opensim doctor --json
```

### 7.3 `ui act`

Gửi nhiều hành động trong một request để giảm round-trip:

```json
{
  "device": "95B3747B-7065-447E-AB1E-53065142C3FC",
  "steps": [
    {"type": "tap", "x": 195, "y": 422},
    {"type": "wait", "ms": 300},
    {"type": "type", "text": "hello@example.com"},
    {"type": "tap", "on": {"label": "Continue"}},
    {"type": "screenshot", "format": "jpeg", "scale": 0.5}
  ],
  "stopOnError": true
}
```

Mỗi step trả kết quả riêng; step lỗi dừng chuỗi nếu `stopOnError`. `ui act` dùng cùng engine với các lệnh đơn lẻ.

## 8. MCP

### 8.1 Transport và xác thực

- `opensim mcp --stdio`: JSON-RPC 2.0 trên stdin/stdout, log ra stderr.
- `opensim mcp --http`: Streamable HTTP tại `127.0.0.1:<daemon-port>/mcp`, dùng chung daemon; Bearer token đọc từ state file.
- Chỉ bind loopback. Kiểm tra `Host` và `Origin`; từ chối request không phải localhost.
- Protocol version thương lượng ở `initialize`; OpenSim hỗ trợ version 2025-06-18 và các version sau tương thích ngược. Không phụ thuộc SDK bên ngoài; tự implement JSON-RPC.
- MCP server stdio là proxy mỏng sang daemon; không tự gọi private API.

### 8.2 Tool catalog

Tool name dùng snake_case, ổn định. Mọi tool trả `structuredContent` theo schema và một text summary ngắn cho LLM.

| Tool | Mode | Tham số chính | Trả về |
|---|---|---|---|
| `device_list` | read | `platform?`, `state?` | danh sách device |
| `device_get` | read | `device` | chi tiết device |
| `device_create` | write | `name`, `deviceType`, `runtime?` | device mới |
| `device_clone` | write | `device`, `name` | device mới |
| `device_boot` | write | `device`, `wait?` | trạng thái |
| `device_shutdown` | write | `device`, `wait?` | trạng thái |
| `device_erase` | destructive | `device`, `confirm` | trạng thái |
| `device_delete` | destructive | `device`, `confirm` | trạng thái |
| `device_rename` | write | `device`, `name` | device |
| `device_status` | read | `device` | trạng thái + boot info |
| `device_pair` | write | `watch`, `phone` | cặp device |
| `device_set_location` | write | `device`, `latitude`, `longitude` | trạng thái |
| `device_appearance` | write | `device`, `mode` | trạng thái |
| `device_privacy` | write | `device`, `service`, `bundleID`, `action` | trạng thái |
| `device_push` | write | `device`, `bundleID`, `payload` | trạng thái |
| `device_open_url` | write | `device`, `url` | trạng thái |
| `device_pasteboard` | write | `device`, `text` hoặc `read: true` | nội dung |
| `runtime_list` | read | `platform?` | runtime đã cài + version catalog biết được |
| `runtime_download` | write | `platform`, `version` | runtime đang cài + progress event |
| `runtime_install` | write | `path` | runtime từ `.dmg` |
| `runtime_delete` | destructive | `identifier`, `confirm` | trạng thái; chặn nếu `deviceCount > 0` |
| `app_list` | read | `device`, `filter?` | danh sách app |
| `app_install` | write | `device`, `path` | app |
| `app_uninstall` | destructive | `device`, `bundleID`, `confirm` | trạng thái |
| `app_launch` | write | `device`, `bundleID`, `args?`, `env?` | pid |
| `app_terminate` | write | `device`, `bundleID` | trạng thái |
| `app_info` | read | `device`, `bundleID` | metadata |
| `app_container` | read | `device`, `bundleID`, `kind` | path |
| `app_data_export` | read | `device`, `bundleID`, `destination` | path |
| `app_data_import` | destructive | `device`, `bundleID`, `source`, `confirm` | trạng thái |
| `screen_info` | read | `device` | screen descriptors |
| `screen_screenshot` | read | `device`, `format?`, `scale?`, `quality?` | image content + metadata |
| `screen_record_start` | write | `device`, `path?`, `codec?` | recording id |
| `screen_record_stop` | write | `recordingID` | path + duration |
| `ui_tree` | read | `device`, `maxDepth?`, `maxNodes?` | cây element |
| `ui_find` | read | `device`, `selector` | danh sách element |
| `ui_tap` | write | `device`, `x,y` hoặc `on`, `settle?` | kết quả + optional screenshot |
| `ui_swipe` | write | `device`, `from`, `to`, `durationMs?` | kết quả |
| `ui_long_press` | write | `device`, `x,y`, `durationMs?` | kết quả |
| `ui_drag` | write | `device`, `from`, `to`, `durationMs?` | kết quả |
| `ui_pinch` | write | `device`, `center`, `scale`, `durationMs?` | kết quả |
| `ui_rotate` | write | `device`, `center`, `angle`, `durationMs?` | kết quả |
| `ui_scroll` | write | `device`, `deltaX`, `deltaY`, `at?` | kết quả |
| `ui_type` | write | `device`, `text` | kết quả |
| `ui_key` | write | `device`, `key`, `modifiers?` | kết quả |
| `ui_button` | write | `device`, `button` | kết quả |
| `ui_wait` | read | `device`, `selector?`, `idleMs?`, `timeoutMs` | kết quả |
| `ui_act` | write | `device`, `steps`, `stopOnError?` | kết quả từng step |
| `log_tail` | read | `device`, `cursor?`, `limit?`, `filter?` | log entries + cursor |
| `session_list` | read | không | sessions |
| `session_acquire` | write | `device`, `mode`, `ttlSeconds?` | lease |
| `session_release` | write | `leaseID` | trạng thái |
| `storage_scan` | read | `roots?`, `refresh?` | scanId + summary |
| `storage_list` | read | `scanId`, `parent?` | items |
| `storage_clean` | destructive | `scanId`, `itemIds`, `confirm` hoặc `planToken` | kết quả |
| `perf_devices` | read | `since?` | samples |
| `perf_processes` | read | `device` | process list |
| `doctor_report` | read | không | capability report |

Quy tắc:

- Tool read không cần lease; tool write theo device yêu cầu `session_acquire` hoặc CLI tự tạo lease. Tool toàn cục (`device_create`, runtime download/install/delete) cần session hợp lệ nhưng không cần device control lease.
- Tool destructive bắt buộc `confirm: true` hoặc `planToken` từ `storage_clean` plan; plan token hết hạn sau 5 phút và dùng một lần.
- `screen_screenshot` mặc định trả JPEG quality 80 scale 0.5 qua image content; `raw: true` trả PNG full. Kèm `path` để agent không phải giữ base64.
- `ui_tree` mặc định giới hạn 1.500 node và depth 30; nếu vượt, trả `truncated: true` và gợi ý dùng `ui_find`.
- Không tool nào nhận shell string; mọi path được validate.

### 8.3 Error contract

Lỗi MCP dùng JSON-RPC error code chuẩn cho protocol; lỗi nghiệp vụ nằm trong `structuredContent.error` theo cùng schema CLI. Các mã:

`xcode_not_found`, `unsupported_xcode`, `private_api_unavailable`, `a11y_unavailable`, `device_not_found`, `device_not_booted`, `device_busy`, `device_name_conflict`, `lease_required`, `lease_conflict`, `lease_revoked`, `runtime_version_unavailable`, `runtime_in_use`, `simctl_failed`, `input_failed`, `storage_scan_failed`, `storage_in_use`, `confirmation_required`, `invalid_argument`, `permission_denied`, `daemon_unavailable`, `internal`.

Mọi lỗi có `retryable` và `recovery` để agent quyết định bước tiếp theo.

## 9. UI macOS

### 9.1 Cửa sổ chính

- `NavigationSplitView` với sidebar `List(selection:)` `.listStyle(.sidebar)`; nhóm Devices/Runtimes/Storage/Activity; Performance chỉ xuất hiện khi `AppFeature.performance` bật (Plan 5); search; badge count dùng system.
- Detail `Devices`: `Table` cột Device/State/Agent; selected row mở `.inspector` cho preview, runtime, screen, last boot và agent; header có `New Device`; action theo state nằm trong inspector. Không grid card, preview card, badge hay button lặp trên từng dòng.
- Detail `Runtimes`: một row cho mỗi platform + version, không gộp nhiều version vào một platform; action `Install`, `Reveal`, `Remove`; header có `Add Runtime`.
- Storage/Activity là detail destination; dùng `Table`, `List` native; không dashboard card, treemap, sparkline hay feed card tự chế.
- Settings là cửa sổ `Settings` scene riêng, không phải sidebar destination.
- Sidebar là nguồn điều hướng duy nhất; không thêm top tab trùng với sidebar.

### 9.2 Cửa sổ device

- `SimDisplayView` render trực tiếp trong `NSViewRepresentable`, bên trong `WindowGroup` native; titlebar, traffic lights, material và shadow do macOS cung cấp.
- Primary action luôn thấy: Home, Capture, Record, Rotate, Keyboard trong bottom bar native (`ControlGroup` + `safeAreaInset(edge: .bottom)`, `.background(.bar)`). Lock/Volume/Side/Zoom/Gesture nằm trong `Menu` More. Mỗi action dùng `Label`/SF Symbol và `.help`.
- Agent status là `Menu`/`Label` trong titlebar, hiển thị lease và Take control; không pill tự tô màu, không inspector agent trong cửa sổ, không status bar thường trú.
- Gesture: tap, long-press, swipe, drag, pinch, rotate, multi-touch; bàn phím Mac ánh xạ vào simulator; paste hai chiều.
- Nhiều cửa sổ device cùng lúc; lease `control` lấy khi cửa sổ focus và giải phóng khi đóng/resign. Device luôn mở cửa sổ riêng; không chế độ nhúng tab và không top-level tab "Device Window".
- Input của app chỉ được gửi khi cửa sổ đang key và app còn giữ lease `control` chưa hết hạn. Khi lease conflict/revoked, overlay input bị disable và hiện banner; không có đường tắt nào gọi Bridge input mà bỏ qua lease.
- `Cmd+K` mở device palette dạng sheet native (`List` + `.searchable`); menu bar extra dùng SwiftUI native.
- Cửa sổ đóng thì giải phóng lease; device vẫn chạy.

### 9.3 Native-only UI constraints

- Chỉ dùng component SwiftUI/macOS: `NavigationSplitView`, `List`, `Table`, `Form`, `GroupBox`, `ControlGroup`, `Menu`, `Picker`, `ToolbarItemGroup`, `ContentUnavailableView`, `ProgressView`, `Chart`/`Gauge`.
- Typography: system text styles (`.title2`, `.headline`, `.subheadline`, `.caption`, `.caption2`), `.monospacedDigit()` cho số; không `font(.system(size:))`, không chữ 8–9px cố định.
- Color: semantic foreground styles, `accentColor`/`tint`; xanh/vàng/đỏ chỉ cho trạng thái có nghĩa; không hex, không `Color(red:green:blue:)`, không gradient, không custom shadow, không pill/badge tự chế.
- Icon: SF Symbols only; cùng weight/size; không SVG tự vẽ.
- States: `ContentUnavailableView` cho empty/unavailable, `ProgressView` cho loading, `.redacted` khi refresh, `confirmationDialog`/sheet native cho thao tác phá huỷ.
- Copy: ngắn, một câu trả lời cho việc người dùng cần làm; giải thích dài đưa vào `.help`, disclosure hoặc inspector; không lặp trạng thái.
- Accessibility: label đầy đủ, keyboard navigation, focus, VoiceOver, hit target ≥28pt; không truyền tải chỉ bằng màu.
- Prototype HTML chỉ là sketch bố cục; không port CSS, hex, gradient, shadow, dock chrome hay font cố định vào app.
- App dùng system appearance; dark mode tự động, không hardcode light/dark.

### 9.4 Devices và New Simulator

- `New Device` (`⌘N`) mở sheet native gồm `TextField` tên, `Picker` device type và `Picker` runtime; không tự boot sau khi tạo.
- Runtime picker lọc theo platform của device type và liệt kê **mọi version đã cài**, không chỉ bản mới nhất. Version chưa cài vẫn hiện kèm nhãn "Not installed", lý do và link mở Runtimes; `Create` bị disable.
- Tên rỗng hoặc trùng device hiện tại bị chặn bằng validation inline; device type/runtime khác platform bị chặn.
- `device_create` trả device `Shutdown`; app chọn row mới, inspector hiện `Boot & Open`, cập nhật count sidebar và deviceCount của runtime.
- Danh sách device không có button lặp trên từng row; CTA chính nằm trong inspector và đổi theo state (`Open Device` / `Boot & Open` / `Install Runtime`).

### 9.5 Runtimes theo version

- Mỗi runtime là một row theo platform + version, hiển thị installed/not installed, dung lượng, source và số device đang dùng. Không gộp iOS 27.0 và iOS 26.4 thành một row.
- `Install` chạy trong row với progress và `Cancel`; download chỉ dùng version Xcode 27 còn hỗ trợ. `Add Runtime` mở sheet native:
  - `Download`: chọn platform + version có trong catalog; version đã cài bị disable.
  - `From File`: chọn `.dmg`, import qua `simctl runtime add`.
- Danh sách version lịch sử là best-effort: OpenSim không hứa liệt kê hoặc tải được mọi version Apple từng phát hành. Version ngoài catalog phải do người dùng cung cấp file; DMG cũ có thể cần Apple ID.
- Cài xong runtime: device đang `Runtime missing` dùng runtime đó chuyển sang `Shutdown`; runtime picker của New Simulator cập nhật ngay.
- `Remove` bị chặn khi `deviceCount > 0` và hiện `Show Devices`; khi không còn device, xác nhận native rồi xoá. Không xoá im lặng.

### 9.6 Settings

- Cửa sổ `Settings` scene native, mở bằng gear trên titlebar hoặc `⌘,`; bốn tab `General`, `Daemon`, `Input`, `Capabilities` dùng `TabView`/`Form` native, không tab bar tự chế.
- General: connect automatically, client name, trạng thái daemon + Reconnect.
- Daemon: version/protocol/pid/port/Xcode/startedAt; CLI path override + Choose; Restart có progress và lỗi; Reveal log.
- Input: keyboard capture, paste `⌘V`, default gesture `Direct`/`Pinch`/`Rotate` (theo `GestureMode` của Plan 4), activity thumbnails, trạng thái HID.
- Capabilities: chạy Doctor, rows `render`/`hid`/`accessibility`/`screenshot`/`video`/`watch`/`tv` kèm source, daemon health, disk free, device/runtime count; loading, error + Retry, Copy JSON. Không hiển thị token hay secret.

### 9.7 Performance trong Plan 4

- `AppFeature.performance` mặc định `false` trong Plan 4; sidebar và view Performance bị ẩn hoàn toàn, không có shell rỗng hay tab chết.
- Plan 5 nối dữ liệu thật rồi bật flag; Performance vẫn nằm trong scope cuối, chỉ tạm ẩn trong giai đoạn app chưa có metrics.
- Khi flag tắt, daemon không cần sample metrics cho UI; sampler chỉ chạy khi có subscriber hoặc flag bật.

## 10. Storage manager

### 10.1 Nguồn dữ liệu

| Nhóm | Đường dẫn | Cách xoá |
|---|---|---|
| Simulator device | `~/Library/Developer/CoreSimulator/Devices/<UDID>` | `simctl erase/delete` sau shutdown |
| Simulator cache | `~/Library/Developer/CoreSimulator/Caches` | Trash khi không có device booted |
| Simulator log | `~/Library/Logs/CoreSimulator` | Trash |
| Runtime | `simctl runtime list`, volumes của CoreSimulator | `simctl runtime delete`; chặn nếu đang dùng |
| DerivedData | `~/Library/Developer/Xcode/DerivedData` | Trash |
| Archives | `~/Library/Developer/Xcode/Archives` | Trash |
| App container | Đường dẫn từ `simctl get_app_container` | `simctl uninstall` hoặc xoá data có xác nhận |

Trong phạm vi plan 5: runtime do người dùng cài và xoá được bằng `simctl runtime delete`. Ngoài phạm vi: runtime hệ thống cần quyền admin, `iOS DeviceSupport`, các thư mục Xcode không xác định; không xoá các mục này.

### 10.2 Scan

- Chạy nền trong daemon, có progress event.
- Dùng `URLResourceValues.totalFileAllocatedSize` và `fileAllocatedSize`; cộng dồn allocated size.
- Không đi theo symlink ra ngoài root; bỏ qua file đang mở nếu không đọc được; ghi `inaccessible` thay vì fail toàn bộ.
- APFS clone/hardlink làm size cộng dồn có thể lớn hơn dung lượng thực tế giải phóng; kết quả ghi `approximate: true` và UI ghi chú.
- Cache index tại `~/Library/Application Support/OpenSim/storage-index.json`; invalidate theo mtime của root; `refresh: true` buộc scan lại.
- Với DerivedData, đọc `info.plist` để lấy workspace/project name và last used.
- Với Archives, đọc `Info.plist` để lấy app name, version, build, creation date.
- Với device, hiển thị runtime, last booted, app count, data size; app detail lấy top app theo container size.

### 10.3 An toàn

- Không auto-delete, không dọn định kỳ.
- `storage_clean` luôn qua plan/apply:
  1. `plan` trả `planToken`, danh sách item, tổng size, item bị chặn.
  2. `apply` kiểm tra token, target còn tồn tại và không đổi trạng thái; thực thi; trả kết quả từng item.
- Item đang dùng hoặc thuộc device đang boot bị chặn với lý do rõ ràng.
- Xoá Xcode artifact bằng `FileManager.trashItem`; xoá simulator bằng `simctl`; audit mọi thao tác.
- Nếu dung lượng thu hồi > 20 GB, sheet xác nhận yêu cầu gõ tên nhóm (ví dụ `ARCHIVES`).
- Không xoá khi đang scan; scan và clean tuần tự.

## 11. Performance

- Sample mỗi giây từ daemon khi `AppFeature.performance` bật hoặc có subscriber; Plan 4 ẩn UI, Plan 5 bật sau khi nối dữ liệu thật.
- CPU: delta CPU time của process / wall time; chuẩn hoá theo số core.
- RAM: `rusage_info_v4.ri_phys_footprint` qua `proc_pid_rusage`.
- Process mapping:
  - `launchd_sim` có đường dẫn device trong argv; map theo UDID.
  - Process con của `launchd_sim` thuộc device đó.
  - `SIMULATOR_UDID` trong environment là nguồn phụ nếu đọc được.
  - Process không map được gom vào nhóm `unknown` và hiển thị riêng.
- Ring buffer 10 phút, sample 1 giây; UI chỉ subscribe khi Performance được bật và view mở.
- Ngưỡng cảnh báo mặc định: CPU > 150% trong 30 giây, RAM > 2 GB, disk free < 10 GB. Ngưỡng cấu hình được.
- Hành động terminate app/shutdown device thuộc device window/inspector, đi qua daemon operation với lease/audit; Performance tab chỉ đọc metrics và không gọi Bridge write trực tiếp. Kill process tùy ý không có trong UI mặc định.
- Giới hạn: không đo GPU, không thay Instruments; số liệu là ước lượng từ kernel.

## 12. Security và an toàn

- Daemon chỉ bind loopback; không mở mạng LAN.
- Bearer token ngẫu nhiên 32 byte, sinh mỗi lần daemon start; file `0600`, thư mục `0700`.
- Kiểm tra `Host`/`Origin`; từ chối request lạ để chống DNS rebinding.
- Không dùng shell string; mọi tiến trình chạy bằng `Process` với argument array.
- Validate UDID theo UUID, bundle ID theo regex, path theo allowlist root.
- Thao tác phá huỷ cần confirm/plan token; audit đầy đủ; không có "auto-clean".
- App tắt App Sandbox; bật Hardened Runtime; chỉ thêm `disable-library-validation` nếu spike chứng minh cần để load framework Apple.
- Ký Developer ID và notarize bản phát hành; không App Store.
- Không upload log/screenshot đi đâu; telemetry mặc định tắt.
- Log có thể chứa dữ liệu app; cảnh báo khi export.
- Private API là rủi ro chính sách; tài liệu README ghi rõ OpenSim chỉ dùng local, yêu cầu Xcode, không phân phối qua App Store.

## 13. Error model và observability

- `OpenSimError` dùng chung CLI/MCP/daemon; mã lỗi liệt kê ở mục 8.3.
- Log: OSLog subsystem `dev.opensim`, category theo module; daemon ghi thêm file `~/Library/Logs/OpenSim/daemon.log`, rotate 10 MB x 5.
- Audit: JSONL tại `~/Library/Application Support/OpenSim/audit.jsonl`, rotate 50 MB; ghi actor, session, lease, action, target, result, duration.
- `opensim doctor` kiểm tra:
  - macOS version, arm64.
  - Xcode path/version, full Xcode.
  - Sự tồn tại của CoreSimulator/SimulatorKit.
  - Capability render/hid/a11y/screenshot/video.
  - Daemon health, token permission.
  - Disk free, số device/runtime.
  - Kết quả JSON ổn định để agent đọc.
- Crash: app ghi crash log local; daemon restart tự động qua LaunchAgent; lease hết hạn; client nhận `daemon_unavailable` và retry.

## 14. Kiểm thử

### 14.1 Unit

- Domain model, state machine, selector parser, path validator, storage rules, envelope/error encoding.
- Command catalog: mọi operation có metadata, schema, lease requirement.
- Không mock private API ở tầng unit; dùng protocol giả ở tầng Core.

### 14.2 Integration

- Fixture app iOS/iPadOS: màn hình có button, text field, list, accessibility identifier ổn định.
- Fixture watchOS/tvOS: màn hình đơn giản có button và label.
- Test flow: create device → boot → install fixture → launch → screenshot → tap button → assert UI đổi → type text → assert value → terminate → shutdown → delete.
- Test input: tap theo tọa độ, tap theo selector, swipe, long-press, pinch/rotate (assert state hoặc screenshot diff), keyboard, hardware button.
- Test a11y: `ui_tree` chứa element với identifier đã biết; `ui_find` trả đúng.
- Test lease: hai session tranh control; observe đọc được; takeover; lease expiry.
- Test daemon: start/stop/restart, token sai, Host sai, SSE reconnect.
- Test device create: tên trùng, runtime chưa cài, sai platform; device mới ở `Shutdown`.
- Test runtime: import `.dmg` qua bridge giả hoặc fixture; version ngoài catalog trả `runtime_version_unavailable`; cài xong device `Runtime missing` chuyển `Shutdown`; delete bị chặn khi còn device.
- Test storage: scan fixture directories, size, safe flags, plan/apply, chặn item in-use.
- Test perf: process mapping với device booted; sample có dữ liệu; ngưỡng cảnh báo.
- Test CLI JSON golden và MCP contract (tools/list, tools/call, errors).

### 14.3 UI

- XCUITest cho app: mở device, boot, screenshot hiển thị, switch device, lease banner, storage sheet, performance tab (khi flag bật).
- XCUITest New Simulator: mở bằng `+`/`⌘N`, tạo device, validation tên trùng, runtime thiếu bị chặn, row mới được chọn.
- XCUITest Runtimes: cài version cũ có trong catalog, import từ file, cancel progress, Add Runtime; device chờ runtime chuyển `Shutdown`; Remove bị chặn khi còn device.
- XCUITest Settings: mở bằng `⌘,`/gear, bốn tab, Doctor loading/error/retry, không lộ token.
- XCUITest lease: khi harness giữ lease, mọi tap/key trong device window không tới Bridge và overlay bị disable.
- Checklist thị giác thủ công: từng màn, trạng thái rỗng/lỗi/đang tải; kiểm tra trên màn nhỏ và Retina.
- Đo fps/latency bằng instrument nội bộ và screenshot; ghi số thật vào báo cáo plan.

### 14.4 CI

- Unit/lint trên GitHub Actions macOS.
- Integration trên runner macOS 27 tự host có Xcode 27.1; chạy nightly và trước release.
- Ma trận: Xcode 27.0 (nếu có), 27.1; iOS 27 runtime; watch/tv smoke.
- Release gate: unit + integration + UI smoke + doctor trên máy sạch.

## 15. Đóng gói và phát hành

- SwiftPM cho Core/Bridge/Daemon/CLI; XcodeGen (`project.yml`) cho app; CI cài XcodeGen qua Homebrew.
- Dependencies: `swift-argument-parser`, `swift-log`, `Hummingbird` 2.x cho HTTP/SSE; không dùng MCP SDK; không dùng database.
- App bundle `OpenSim.app`, bundle ID `dev.opensim.app`; daemon bundle ID `dev.opensim.daemon`; CLI `opensim`.
- Homebrew tap `opensim` với cask app và formula CLI/daemon.
- Notarize bằng Developer ID; nếu chưa có tài khoản, phát hành source build + hướng dẫn `xcodebuild`.
- `opensim setup`: kiểm tra Xcode, cài LaunchAgent, in hướng dẫn cấp quyền nếu cần.
- `opensim doctor` là bước bắt buộc sau cài.
- Uninstall: `opensim uninstall` gỡ LaunchAgent, app, state; giữ device data trừ khi `--purge`.
- Update: `brew upgrade`; app kiểm tra version và hiện thông báo; không auto-update ngầm.
- License: MIT. Ghi chú private API và yêu cầu Xcode trong README.

## 16. Plans

Mỗi plan là một nhát cắt hoàn chỉnh có test và tài liệu; không cắt bớt tính năng khỏi phạm vi cuối.

| Plan | Nội dung | Điều kiện hoàn thành |
|---|---|---|
| 0 | Spike private API | Có số đo render/tap/type/a11y/watch/tv; chốt đường render/input/a11y hoặc fallback kèm chi phí |
| 1 | Core + Bridge + lifecycle + CLI nhóm device/runtime/app/log | CLI chạy trọn lifecycle trên device thật; golden JSON; doctor |
| 2 | Screen + input + UI tree + CLI `ui` | Tap/swipe/type/selector/screenshot/record/tree hoạt động; integration test |
| 3 | Daemon + session/lease + MCP stdio/HTTP | MCP contract test; đa session; auth; SSE; tài liệu tool |
| 4 | App macOS | Device windows, full gesture, quick switch, agent activity; Devices + New Simulator, Runtimes theo version + Add Runtime, Settings/Doctor; Storage shell; Performance ẩn sau flag và nối ở plan 5 |
| 5 | Storage + performance | Scan/plan/apply fail-closed; metric; CLI/MCP/UI đầy đủ; bật Performance flag; test |
| 6 | watchOS/tvOS parity | Ma trận iOS/iPadOS/watchOS/tvOS; fixture; input maps; test |
| 7 | Hardening + đóng gói + release simulator | Homebrew, notarize, docs, CI xanh, security review |
| 8 | visionOS | Platform adapter, fixture, render/input; test |
| 9 | Thiết bị thật qua CoreDevice | Pair, install, launch, screenshot, HID, log; test |

Phụ thuộc: 1 sau 0; 2 sau 1; 3 sau 1; 4 sau 2 và 3; 5 sau 1 và 3; 6 sau 2; 7 sau 1-6; 8 sau 7; 9 sau 3 và 7.

Quy tắc plan:

- Plan 0 là spike, code vứt đi; kết quả là báo cáo quyết định.
- Plan 1-2 có thể chạy CLI trực tiếp qua Bridge nếu daemon chưa có; khi daemon xuất hiện, CLI chuyển sang client mà không đổi lệnh.
- Plan 4 không dùng mock; Storage có shell và trạng thái lỗi trước plan 5. Performance bị ẩn hoàn toàn sau `AppFeature.performance=false`; Plan 5 nối dữ liệu thật và bật flag.
- Plan 6 không đụng kiến trúc lõi; chỉ thêm platform adapter và fixture.
- Plan 7 chỉ bắt đầu khi acceptance criteria của plan 1-6 đạt.
- Plan 8 và 9 là sau release simulator; không chặn phạm vi release 1-7.

## 17. Acceptance criteria

### 17.1 Kịch bản end-to-end

1. Máy sạch có macOS 27 + Xcode 27.1: cài qua Homebrew, `opensim doctor` pass.
2. `opensim device boot --device "iPhone Air" --wait` thành công.
3. `opensim app install` + `launch` fixture app thành công.
4. `opensim ui tree` trả element có identifier ổn định.
5. `opensim ui tap --on 'id=fixture-primary-button'` đổi UI; `opensim ui type` nhập được text.
6. `opensim ui screenshot` trả ảnh đúng trạng thái.
7. MCP client kết nối stdio và HTTP, thực hiện lại được chuỗi trên.
8. Hai agent cùng lúc: một agent giữ control, agent kia nhận `lease_conflict` rõ ràng; observer vẫn đọc được.
9. Mở app: thấy device, boot, live screen, gesture, switch device, take control từ agent; khi agent giữ lease, input trong device window bị chặn.
10. New Simulator tạo device từ runtime đã cài; tên trùng/runtime thiếu bị chặn rõ ràng; device mới ở `Shutdown`.
11. Runtimes cài được version cũ có trong catalog và import được `.dmg`; device chờ runtime chuyển `Shutdown`; Remove bị chặn khi còn device.
12. Settings mở bằng `⌘,`/gear; Doctor chạy được, lỗi có Retry; không lộ token.
13. Storage scan báo size; clean plan/apply dọn đúng, chặn item in-use; inventory lỗi thì không cho clean.
14. Performance (khi flag bật) hiển thị CPU/RAM của device đang chạy; ngưỡng cảnh báo hoạt động.
15. watchOS/tvOS: boot, render, screenshot, tap fixture thành công.
16. `opensim doctor` phát hiện đúng khi thiếu Xcode hoặc Xcode sai version.

### 17.2 Chỉ số mục tiêu

- Live screen: 60 fps ở scale 100% trên iPhone 17e với Apple Silicon; fallback IOSurface tối thiểu 30 fps; fallback screenshot polling tối thiểu 10 fps và ghi rõ trong doctor.
- Input latency p95 ≤ 50 ms ở đường SimDisplayView/IndigoHID; ≤ 150 ms ở fallback.
- `ui_tree` trả trong ≤ 500 ms cho màn hình thông thường (≤ 1.500 node).
- MCP overhead (không tính action) ≤ 20 ms qua loopback.
- Storage scan 100 GB trong ≤ 60 giây khi cache nguội; size lệch ≤ 5% so với allocated size.
- Daemon idle CPU < 1%, RAM < 150 MB; app với 2 live device < 600 MB.
- Không có memory leak phát hiện sau 30 phút chạy liên tục với 2 device.

## 18. Rủi ro và giảm thiểu

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| SimulatorKit đổi API private | Cao | Dynamic loading, capability check, fallback, matrix Xcode, doctor |
| Swift method không expose qua ObjC | Cao | Spike xác minh; fallback IOSurface + IndigoHID; cuối cùng screenshot polling |
| Accessibility private không dùng được | Cao | XCUITest helper ở plan 2; nếu vẫn fail, trả `a11y_unavailable` và dùng screenshot + tọa độ |
| Multi-touch/pinch/rotate không chính xác | Trung bình | Dùng digitizer của SimDisplayView; test fixture; so sánh với Device Hub |
| watchOS/tvOS khác biệt input/render | Trung bình | Platform adapter riêng; fixture; plan 6 |
| Entitlement/TCC khi load private framework | Trung bình | Tắt sandbox, Hardened Runtime, test trên máy sạch; notarize |
| Daemon chết hoặc race lease | Trung bình | LaunchAgent, health check, lock, test conflict/expiry |
| Storage size sai do APFS clone | Thấp | Allocated size + ghi approximate; so sánh trong test |
| Process mapping thiếu UDID | Trung bình | argv `launchd_sim`, env, process tree; nhóm unknown |
| Xcode update phá vỡ | Cao | Version gate, compat mode, release notes, test matrix |
| Runtime version cũ không tương thích Xcode 27 | Trung bình | Catalog best-effort; import DMG qua `simctl runtime add` có verify; UI ghi source; không hứa mọi version lịch sử |
| Chính sách Apple với private API | Trung bình | Local/open-source, không App Store, README rõ; tư vấn pháp lý trước release |
| Phạm vi phình | Cao | Plans, non-goals, acceptance criteria; mọi tính năng mới cần spec bổ sung |

## 19. Quyết định đã chốt

- Tên tạm OpenSim; CLI `opensim`; app `OpenSim.app`.
- License MIT.
- macOS 27.0+, arm64; Xcode 27.1+ (27.0 best-effort).
- Swift 6 language mode; SwiftPM; XcodeGen cho app.
- Dependencies: swift-argument-parser, swift-log, Hummingbird 2.x; không MCP SDK, không DB.
- Daemon HTTP loopback, port động, token file `0600`; không Unix socket.
- Metrics 1 giây, ring 10 phút.
- Screenshot MCP mặc định JPEG 80 scale 0.5; raw PNG khi cần.
- Lease TTL 5 phút, heartbeat 30 giây, takeover grace 3 giây.
- Storage clean plan token TTL 5 phút, dùng một lần.
- Release simulator gồm iOS/iPadOS/watchOS/tvOS (plan 7). visionOS (plan 8) và thiết bị thật (plan 9) là các plan sau release.
- UI native-only; Settings là `Settings` scene riêng, mở bằng gear và `⌘,`; không tab bar tự chế.
- Performance giữ trong scope nhưng ẩn sau `AppFeature.performance=false` ở Plan 4, bật ở Plan 5.
- Runtime hỗ trợ nhiều version song song: download version Xcode hỗ trợ hoặc import `.dmg`; danh sách lịch sử là best-effort, không hứa đầy đủ.
- Xoá runtime bị chặn khi còn device tham chiếu. New Simulator luôn tạo device `Shutdown`.
- Default gesture của app là `Direct` / `Pinch` / `Rotate`, khớp `GestureMode` của Plan 4.

## 20. Bằng chứng môi trường

Ghi nhận ngày 2026-10-19 trên máy owner:

- `sw_vers`: macOS 27.0.1, build 26A434.
- Xcode 27.1, build 27A9275; `xcode-select -p` trỏ `/Applications/Xcode.app/Contents/Developer`.
- `Simulator.app` không tồn tại; `DeviceHub.app` bundle `com.apple.dt.Devices` tồn tại.
- Runtime iOS 27.0 (24A434), device iPhone Air booted.
- `xcrun simctl` có đủ lifecycle, install, launch, io screenshot/recordVideo/enumerate, log, push, privacy, status_bar.
- `SimulatorKit.framework` export `SimDisplayView`, `SimDeviceScreen`, `SimDeviceLegacyHIDClient`, `IndigoHIDMessageFor*`.
- `CoreSimulator.framework` export `SimServiceContext`, `SimDeviceSet`, `SimDevice`, `SimDeviceIOClient`.
- `launchd_sim` argv chứa đường dẫn `~/Library/Developer/CoreSimulator/Devices/<UDID>`, dùng được cho process mapping.
- `simctl io enumerate` trả display ports, gồm `com.apple.framebuffer.display` và `com.apple.display.captureservice`.
- Các thư mục `Devices`, `DerivedData`, `Archives`, `Logs/CoreSimulator` tồn tại; dung lượng trống tại thời điểm kiểm tra khoảng 70 GiB.
- `idb` có trong Homebrew nhưng client Python đang thiếu module `six`; OpenSim không phụ thuộc idb. idb chỉ dùng làm tham chiếu hành vi.
