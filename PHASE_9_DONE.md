# Phase 9 — Cleanup: Xóa Code Cũ & Tổng kết Migration — DONE

**Ngày hoàn thành:** 2026-04-29  
**Syntax check:** PASS (python auto_test.py — 11 pass, 0 fail, 0 warn, 9/9 phases)

---

## Thay đổi Phase 9

### 1. Xóa hardcoded plaintext passwords
- **Trước:** `injectSyncPasswords()` ghi `s.editPw = '123456'` và `localStorage.setItem('sync_edit_pw', '123456')`
- **Sau:** Đổi thành `injectSyncHashes()`, chỉ inject SHA-256 hashes với guard `if (!s.adminHash)` để không ghi đè hashes từ Supabase
- **Trước:** `const SPLASH_PW = {'204290':'admin','123456':'edit','280510':'view'}` — plaintext visible trong source
- **Sau:** Xóa hoàn toàn, thay bằng comment giải thích

### 2. Dọn fallback plaintext trong `_splashLogin`
- Xóa dòng `if (!role) role = SPLASH_PW[pw] || null`
- Xóa comment "giữ SPLASH_PW làm fallback"
- Auth flow hiện tại: hash check local → hash check Supabase → fail

### 3. Cập nhật `renderStorageMeter()` — phản ánh Supabase là primary
- Không còn hiện "5MB limit" màu đỏ
- Hiện "Cache offline: X MB — Dữ liệu lưu trên Supabase ☁"
- Xóa nút "Dọn ảnh cũ" khỏi meter (ảnh đã ở Supabase Storage)

### 4. Cập nhật `checkStorageAndWarn()`
- Xóa ngưỡng cảnh báo 75% và nhắc nhở 60% (không còn cần thiết)
- Chỉ giữ ngưỡng 90% (nguy hiểm thực sự)
- Cập nhật thông điệp: "Cache offline gần đầy" thay vì "Bộ nhớ gần đầy"

### 5. Cập nhật `showStorageAlert()` và `openClearPhotosModal()`
- Cập nhật messaging: giải thích ảnh an toàn trên Supabase Storage
- Xóa "X MB / 5MB" progress bar từ openClearPhotosModal
- Thêm note xanh giải thích "Xóa cache không ảnh hưởng ảnh trên Supabase"

---

## Tổng kết toàn bộ Migration: localStorage → Supabase

### Trạng thái ban đầu (trước migration)
- Single HTML file ~770KB, 7584 dòng
- Toàn bộ data trong `D` object → localStorage JSON blob ~769KB
- Sync qua GitHub Gist (AES-GCM encrypt, 14-property SYNC object)
- Auth: 3 plaintext passwords hardcode trong source code
- Ảnh: base64 strings trong localStorage (~70% dung lượng)
- Không có collaboration real-time

### Trạng thái sau migration
- Supabase là primary storage (12 bảng + views)
- localStorage chỉ là offline cache
- Auth: SHA-256 hash check (local fallback → Supabase query)
- Ảnh: Supabase Storage bucket `project-photos` (public CDN URLs)
- GitHub Gist sync: đã xóa hoàn toàn (~600 dòng)
- Realtime: Supabase Realtime subscription (rows/projects/months/pending_changes)
- Admin approval workflow: edit/view tạo pending_changes → admin duyệt

### Kiến trúc sau migration

```
Browser (index.html)
│
├── D (global object)          ← nguồn render DUY NHẤT (giữ nguyên)
│   └── updated from Supabase on login + Realtime events
│
├── localStorage               ← OFFLINE CACHE chỉ
│   └── SK ("phoicanh_data")  ← snapshot D, ~750KB text
│
├── Auth
│   ├── injectSyncHashes()    ← SHA-256 defaults (no plaintext)
│   ├── hashPw() + D.settings.sync hashes ← local check
│   └── _sb.from('settings').select('sync_config') ← Supabase fallback
│
├── Supabase (kefwrfxeneropihedght.supabase.co)
│   ├── 12 tables: settings, months, projects, project_photos,
│   │              groups, rows, tl_tasks, ot_log,
│   │              staff, staff_leaves, staff_late_log, business_trips
│   ├── 1 table:   pending_changes (Phase 8)
│   ├── 3 views:   v_project_totals, v_staff_monthly_kpi, v_upcoming_deadlines
│   └── Storage:   bucket "project-photos" (public)
│
├── Write path
│   ├── Admin: ghi thẳng → Supabase → Realtime → all clients
│   └── Edit/View: → pending_changes → admin duyệt → execute write
│
└── Realtime
    ├── rows, projects, months → applyRowChange() / sbLoadAll()
    └── pending_changes INSERT → toast notify admin
```

### Các phase đã hoàn thành

| Phase | Tên | Ngày | Nội dung chính |
|-------|-----|------|----------------|
| 0 | Setup SDK | 2026-04-29 | Thêm Supabase CDN, createClient |
| 1 | Auth | 2026-04-29 | Hash check local + Supabase fallback |
| 2 | Read | 2026-04-29 | `sbLoadAll()` — fetch 11 bảng song song |
| 3 | Write Settings | 2026-04-29 | saveSettings, updateMonthTarget, doAddMonth |
| 4 | Write Projects | 2026-04-29 | confirmAddPj, confirmEditPj, deletePj |
| 5 | Write Rows | 2026-04-29 | updRow (debounce 1500ms), markRowDone, addGroup/Row, delGroup/Row |
| 6 | Write Staff | 2026-04-29 | saveStaffProfile, leave, lateLog, trips |
| 7 | Realtime | 2026-04-29 | startRealtimeSync, applyRowChange, morning notification, xóa Gist |
| 8 | Approval WF | 2026-04-29 | pending_changes, openPendingPanel, approveChange/rejectChange |
| 9 | Cleanup | 2026-04-29 | Xóa plaintext passwords, dọn storage messaging |

### Files quan trọng

| File | Mô tả |
|------|-------|
| `index.html` | App chính — 7430 dòng, 767KB |
| `SUPABASE_SCHEMA.sql` | Schema 12 bảng |
| `PHASE_8_SCHEMA.sql` | Bảng pending_changes |
| `FIX_RLS_ANON.sql` | RLS policies cho anon key |
| `migrate_to_supabase.js` | Script migration data lần đầu (đã chạy) |
| `upload_photos.js` | Script upload ảnh base64 → Storage (đã chạy, 30 ảnh) |
| `auto_test.py` | Test suite — 11 checks, 9 phase markers |
| `index_backup_20260429.html` | Bản gốc trước migration (788,202 bytes) |

### auto_test.py cuối cùng
```
11 pass, 0 fail, 0 warn
9/9 phases: Phase 0→9 đều PASS
Functions: 19/19 đủ
Syntax JS: OK (6,776 dòng JS)
File size: 785,146 bytes (767KB)
```

## Vấn đề gặp phải
- Không có vấn đề nào trong Phase 9
