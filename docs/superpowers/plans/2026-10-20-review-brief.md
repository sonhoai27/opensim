# OpenSim Plan Review Brief

- Ngày: 2026-10-20
- Dành cho: fact-check reviewer và adversarial reviewer
- Trạng thái: hướng dẫn review, không phải spec

## Phạm vi đọc

1. Spec: `docs/superpowers/specs/2026-10-19-open-simulator-design.md`
2. Spike plan: `docs/superpowers/plans/2026-10-19-opensim-plan-0-private-api-spike.md`
3. Contract: `docs/superpowers/plans/2026-10-20-plan-map-and-interfaces.md`
4. Author brief: `docs/superpowers/plans/2026-10-20-author-brief.md`
5. Toàn bộ plan:
   - `2026-10-20-opensim-plan-1-core-bridge-cli.md`
   - `2026-10-20-opensim-plan-2-screen-input-a11y.md`
   - `2026-10-20-opensim-plan-3-daemon-session-mcp.md`
   - `2026-10-20-opensim-plan-4-macos-app.md`
   - `2026-10-20-opensim-plan-5-storage-performance.md`
   - `2026-10-20-opensim-plan-6-watchos-tvos.md`
   - `2026-10-20-opensim-plan-7-release.md`
   - `2026-10-20-opensim-plan-8-visionos.md`
   - `2026-10-20-opensim-plan-9-physical-devices.md`

Plan 4 và Plan 9 có thể chưa hoàn tất khi reviewer bắt đầu; nếu thiếu file hoặc file chưa có đủ section, ghi `BLOCKED_MISSING_PLAN` và không suy diễn nội dung.

## Quy tắc

- Chỉ đọc và báo findings. Không sửa spec, contract, plan, code.
- Không chạy download, cài đặt, xoá file, lệnh destructive, hay browser automation.
- Không dùng Chrome.
- Có thể dùng `grep`, `python3`, `sed`, `wc` để kiểm tra cấu trúc.
- Mọi finding phải có bằng chứng: file + dòng (nếu xác định được), trích dẫn ngắn, và đề xuất sửa cụ thể.
- Không khen chung chung; không báo "looks good" thay cho findings.
- Phân loại:
  - `P0`: plan không thể thi công, mâu thuẫn spec, thiếu dependency, lệnh sai, phá vỡ an toàn.
  - `P1`: task không test được, API/type không tồn tại hoặc không khớp contract, thiếu failure path quan trọng, thứ tự plan sai.
  - `P2`: thiếu chi tiết, trùng lặp, quá dài, wording mơ hồ, test yếu nhưng không chặn thi công.
- Nếu không tìm thấy vấn đề ở một mục, ghi rõ mục đó đã kiểm và không có finding.

## Fact-check reviewer

Kiểm tra:

1. **Spec coverage:** mỗi mục 2-17 của spec có task tương ứng trong ít nhất một plan không; ghi các mục bị bỏ.
2. **Contract names:** type/protocol/module/tool name có khớp contract không; liệt kê mọi tên lệch.
3. **Dependency order:** Plan 1 → 2/3 → 4/5 → 6 → 7 → 8/9 có đúng không; task nào dùng file/API chưa được tạo.
4. **File paths:** path trong plan có nằm đúng repo layout không; path test/fixture/build có tồn tại trong kế hoạch của plan trước không.
5. **Commands:** lệnh build/test/simctl/xcodebuild/brew/notarize có cú pháp hợp lý, đúng môi trường macOS 27/Xcode 27.1 không.
6. **Private API:** chỉ dùng selector/class đã có trong spec/Plan 0; không có claim chưa được xác minh; fallback có thật.
7. **Safety:** destructive operations có plan/confirm, path allowlist, lease, audit, no shell string, token `0600`, loopback-only, không auto-download runtime.
8. **Tests:** mỗi task có check đỏ → implement → check xanh → commit; integration test có fixture và skip/fail rõ ràng khi thiếu runtime/hardware.
9. **Plan hygiene:** required header, Spec coverage, Exit criteria, không placeholder, không CJK, không copy lặp quá mức.
10. **Plan size:** plan > 3.000 dòng phải được đánh dấu để rà trùng lặp; không tự động coi là lỗi P0.

## Adversarial reviewer

Giả định các plan sai. Tìm:

1. Race condition session/lease, takeover, daemon restart, CLI/MCP cùng thiết bị.
2. Mất dữ liệu khi storage clean, token reuse/expiry, item in-use, APFS size sai, Trash lỗi.
3. Process mapping sai device, đọc env bị chặn, CPU/RAM nhiễu, sample làm chậm simulator.
4. UI app không có dữ liệu thật, trạng thái loading/error/empty rỗng, gesture không parity, multi-window/lease UX mâu thuẫn.
5. Plan 4 dùng `SimulatorScreenView` không khớp API Plan 2; Plan 5 mở rộng daemon/UI không khớp Plan 3/4.
6. Plan 6/8/9 xâm phạm core type/protocol hoặc hứa API chưa xác minh.
7. Release plan bỏ sót notarization, entitlements, Homebrew, rollback, clean-Mac install, compatibility Xcode.
8. Test giả: assert không chạy, skip quá nhiều, mock private API, test không chạm nhánh thật.
9. Scope creep hoặc feature ngoài spec.
10. Các giả định về watchOS/tvOS/visionOS/physical device không có bằng chứng.

## Output

Ghi findings vào file được giao:

- Fact-check: `docs/superpowers/plans/2026-10-20-review-factcheck.md`
- Adversarial: `docs/superpowers/plans/2026-10-20-review-adversarial.md`

Format:

```markdown
# Review Findings

- Reviewer: fact-check | adversarial
- Ngày: 2026-10-20
- Scope: Plan 0-9

## Tổng quan

- P0: <số>
- P1: <số>
- P2: <số>
- BLOCKED_MISSING_PLAN: <danh sách nếu có>

## Findings

| ID | Severity | Plan | Location | Finding | Evidence | Proposed fix |
|---|---|---|---|---|---|---|
| F1 | P0 | Plan 3 | `...:123` | ... | ... | ... |

## Mục đã kiểm, không có finding

- ...
```

Không sửa plan. Không commit. Kết thúc response bằng số lượng finding theo severity và file đã ghi.
