# PHASE 5 — Write: Groups & Rows — DONE

**Ngày hoàn thành:** 2026-04-29  
**Syntax check:** PASS (python auto_test.py — 11 pass, 0 fail, 0 warn, 7/7 phases)

## Thay đổi đã thực hiện
- Thêm `_sbRowDebounce`, `_sbSaveRowDebounced()`, `_COL_MAP`
- `addGroup(pjId)` → async: insert group + first row vào Supabase
- `addRow(pjId, gid2)` → async: insert row vào Supabase
- `delGroup(pjId, gid2)` → async: delete group từ Supabase trước
- `delRow(pjId, gid2, rid)` → async: delete row từ Supabase trước
- `updGroup(pjId, gid2, field, val)` → async: update type trên Supabase
- `updRow(pjId, gid2, rid, field, val)`: thêm `_sbSaveRowDebounced` (1500ms)
- `markRowDone(pjId, gId, rId)` → async: ghi done_at + up_score ngay (không debounce)

## Verify kết quả
- auto_test.py PASS, 7/7 phase markers detected

## Vấn đề gặp phải
- Không có
