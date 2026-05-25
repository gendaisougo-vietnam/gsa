# PHASE 6 — Write: Staff — DONE

**Ngày hoàn thành:** 2026-04-29  
**Syntax check:** PASS (python auto_test.py — 11 pass, 0 fail, 0 warn, 7/7 phases)

## Thay đổi đã thực hiện
- `saveStaffProfile(name, field, val)` → async, thêm Supabase update (COL_STAFF mapping)
- `addLateRecord(name, date, minutes, note)` → async, upsert staff_late_log
- `deleteLateRecord(name, date)` → async, delete staff_late_log
- `addTrip(name)` → async, insert business_trips
- `deleteTrip(name, id)` → async, delete business_trips
- `confirmAddLeave(name)` → async, insert staff_leaves
- `delLeave(staffName, leaveId)` → async, delete staff_leaves

## Verify kết quả
- auto_test.py PASS, 11 pass, 0 fail, 0 warn, 7/7 phases

## Vấn đề gặp phải
- Không có
