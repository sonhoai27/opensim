# OpenSim Plan Author Brief

- Ngày: 2026-10-20
- Dành cho: các plan author agent
- Trạng thái: hướng dẫn chung, không phải spec

## Vai trò

Bạn là **plan author**, không phải implementation agent. Nhiệm vụ là viết tài liệu plan Markdown cho đúng phạm vi được giao. Không viết production code, không tạo source Swift, không sửa hệ thống.

## Đọc trước

1. Spec: `docs/superpowers/specs/2026-10-19-open-simulator-design.md`
2. Plan 0: `docs/superpowers/plans/2026-10-19-opensim-plan-0-private-api-spike.md`
3. Contract: `docs/superpowers/plans/2026-10-20-plan-map-and-interfaces.md`
4. Skill: `/Users/son/.qoder/plugins/cache/qoder-marketplace/superpowers/6.3.0/skills/writing-plans/SKILL.md`

Nếu plan khác chưa tồn tại, dùng contract + spec; không block.

## Quy tắc bắt buộc

- Chỉ dùng `Write` để tạo đúng file plan được giao. Không sửa spec, contract, Plan 0, plan của agent khác, `.gitignore`, hay file khác.
- Không commit. Main agent sẽ review và commit.
- Không chạy download, cài đặt, xoá file, hay lệnh destructive.
- Không dùng Chrome/browser automation. Chỉ đọc file local; có thể dùng `grep`, `sed`, `python3` để kiểm tra.
- Văn xuôi tiếng Việt; code, type, identifier, command tiếng Anh. Không ký tự CJK.
- Không placeholder: không `TBD`, `TODO`, `implement later`, `similar to Task N`, dấu ba chấm.
- Mọi task phải có: Files, Interfaces, các bước TDD (check đỏ trước, implement, check xanh), code snippet thật, lệnh chạy, expected output, commit step.
- Dùng đúng tên type/protocol/module trong contract. Có thể thêm type mới nhưng phải định nghĩa trong plan và ghi rõ.
- Plan 0 **chưa chạy**. Với private API, chỉ dùng selector/class đã nêu trong spec/Plan 0; nếu chưa chắc, dùng capability gate + fallback trong spec. Không bịa API.
- Mỗi plan phải có:
  - Header bắt buộc của writing-plans (Goal, Architecture, Tech Stack, Spec, Global Constraints).
  - File Structure.
  - Tasks.
  - Mục `Spec coverage` ánh xạ mục spec → task.
  - Mục `Exit criteria`.
- Tham chiếu plan khác bằng đường dẫn; không copy nội dung.
- Kết thúc bằng danh sách file đã tạo + tóm tắt 10 dòng.

## Kiểm tra trước khi kết thúc

Chạy các lệnh sau và sửa nếu có kết quả xấu:

```bash
grep -nE "TBD|TODO|implement later|similar to Task|\.\.\." <plan-file>
python3 - <<'PY'
p = "<plan-file>"
s = open(p, encoding="utf-8").read()
bad = sum(1 for ch in s if "\u4e00" <= ch <= "\u9fff" or "\u3040" <= ch <= "\u30ff" or "\uac00" <= ch <= "\ud7af")
print("CJK", bad)
PY
```

## Nguyên tắc chất lượng

- Task nhỏ, mỗi task có deliverable độc lập và test được.
- Không dạy lại kiến thức chung; viết đủ để kỹ sư không có context làm được.
- Nêu rõ dependency, rollback/fallback, error handling, security ở nơi liên quan.
- Không thêm feature ngoài spec; nếu cần, ghi là deferred và không đưa vào task.
- Không hứa API/behavior chưa được spike xác minh; ghi rõ giả định và điều kiện.
