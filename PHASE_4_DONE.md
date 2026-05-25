# PHASE 4 — Write: Projects CRUD — DONE

**Ngày hoàn thành:** 2026-04-29  
**Syntax check:** PASS (python auto_test.py — 11 pass, 0 fail, 0 warn)

## Thay đổi đã thực hiện
- Thêm helper `_sbSaveProject(p, monthId, section)` (async, sau sbLoadAll)
- `confirmAddPj()`: gọi `_sbSaveProject` sau save()
- `confirmEditPj(id)`: gọi `_sbSaveProject` sau save()
- `deletePj(id)` → async: xóa trên Supabase trước, sau đó xóa khỏi D

## Verify kết quả
- auto_test.py PASS, 6/7 phase markers detected

## Vấn đề gặp phải
- Không có
