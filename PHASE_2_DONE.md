# PHASE 2 — Load D từ Supabase — DONE

**Ngày hoàn thành:** 2026-04-29  
**Syntax check:** PASS (python auto_test.py — 11 pass, 0 fail, 0 warn)

## Thay đổi đã thực hiện
- Thêm hàm `sbLoadAll()` sau `const SK = 'phoicanh_v3'` (dòng 663)
  - Fetch 10 bảng song song (Promise.all)
  - Reconstruct D object từ Supabase rows
  - Cache `window._sbSettingsId` (Phase 3 prep)
  - Cache `window._sbStaffIdByName` (Phase 6 prep)
- Sửa `_splashLogin()`: gọi `sbLoadAll()` trước `renderAll()`
  - Lưu D vào localStorage sau khi fetch (offline cache)

## Verify kết quả
- auto_test.py PASS, 5/7 phase markers detected (Phase 0-3 + 6)

## Vấn đề gặp phải
- Không có
