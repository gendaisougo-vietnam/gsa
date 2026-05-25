# PHASE 1 — Auth via Supabase — DONE

**Ngày hoàn thành:** 2026-04-29  
**Syntax check:** PASS (python auto_test.py — 11 pass, 0 fail, 0 warn)

## Thay đổi đã thực hiện
- `window._splashLogin` đổi thành `async function`
- Thêm Supabase hash check trước SPLASH_PW (dòng ~7513–7530)
- Logic: hashPw(pw) → check D.settings.sync hashes → fallback Supabase settings.sync_config → fallback SPLASH_PW

## Verify kết quả
- auto_test.py PASS, syntax OK, 17/17 functions còn đủ

## Vấn đề gặp phải
- Không có
