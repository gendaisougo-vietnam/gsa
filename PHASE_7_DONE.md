# Phase 7 — Supabase Realtime + Remove GitHub Gist Sync — DONE

**Ngày hoàn thành:** 2026-04-29  
**Syntax check:** PASS (python auto_test.py — 11 pass, 0 fail, 0 warn, 8/8 phases)

## Thay đổi đã thực hiện

### Xóa code GitHub Gist sync
- Xóa `GIST_API` constant
- Simplified `SYNC` object: từ 14 properties → chỉ còn `role` getter/setter (sessionStorage)
- Xóa `triggerAutoSync()` call khỏi `persistD()`
- Xóa các hàm: `deriveKey()`, `encryptData()`, `decryptData()`, `compressBase64Photo()`, `buildSyncPayload()`, `syncPush()`, `syncPull()`, `quickSync()`, `syncBtnHold()`, `syncBtnRelease()`, `_syncHoldTimer`, `startPeriodicPull()`, `triggerAutoSync()`, `openSyncPanel()`, `showSyncSetup()`, `testGistConnection()`, `confirmSyncSetup()`, `syncDoLogin()`, `syncPullWithRole()`, `syncLogout()`, `toggleAutoSync()`, `showSyncStatus()`
- Xóa modal HTML của Sync panel (~19,000 chars)
- Thay `openSyncPanel()` bằng stub: `toast('ℹ Đồng bộ qua Supabase Realtime...')`
- Cập nhật `renderSettings()`: thay GitHub Gist config UI bằng thông báo Supabase Realtime

### Thêm Supabase Realtime
- Thêm `startRealtimeSync()`: subscribe `postgres_changes` trên bảng `rows`, `projects`, `months`
  - Rows: `applyRowChange(payload)` merge change vào D, gọi `renderContent()`
  - Projects INSERT/DELETE: full reload qua `sbLoadAll()`
  - Months UPDATE: cập nhật `targetNew`/`targetRev` trong D
  - Subscribe status → cập nhật sync badge: 🟢 Live / 🔴 Offline / ⏳
- Thêm `applyRowChange(payload)`: merge row-level DB changes vào D không reload toàn bộ
- Thêm `sbReloadData()`: full reload từ Supabase (bấm nút Live)
- Thêm `checkMorningNotification()`: popup 7-12h hiện danh sách UP hôm nay và nhân sự nghỉ

### Cập nhật Sync button
- Old: `onclick="quickSync()"` với hold/release handlers
- New: `onclick="sbReloadData()"` với label `Live`

### Cập nhật _splashLogin
- Login path: thay `syncPull('')` + `startPeriodicPull()` → `startRealtimeSync()` + `checkMorningNotification()`
- Session path (page reload): thêm `sbLoadAll()` → `D = sbData` → `renderAll()` → `startRealtimeSync()` + `checkMorningNotification()`

### Thêm photo loading từ Supabase Storage
- `sbLoadAll()`: thêm query `project_photos`, build `photosByPj` map, populate `pObj.photos` với Storage URLs
- `uploadPhoto()`: thêm Supabase Storage upload sau local save
- `delPhoto()`: thêm Supabase Storage delete

### Cập nhật auto_test.py
- Thay `syncPush`, `syncPull` → `startRealtimeSync`, `sbReloadData` trong `REQUIRED_FUNCTIONS`
- Thêm Phase 7 check: `startRealtimeSync` + `checkMorningNotification`
- Cập nhật count: 7 → 8 phases

## Verify kết quả
- `python auto_test.py` → **PASS 11/11, 8/8 phases**
- Syntax JS: OK (6,584 dòng JS)
- Functions: 17/17 đủ
- localStorage: 33 lần gọi (offline cache còn nguyên)
- File size: 773,733 bytes (756 KB) — hợp lý sau khi xóa ~600 dòng sync code
- Backup: 788,202 bytes (nguyên vẹn)

## Lưu ý cho Realtime hoạt động
Cần enable Replication trong Supabase Dashboard:
- Database → Replication → chọn bảng `rows`, `projects`, `months`

## Vấn đề gặp phải
- `syncPull` bị lỗi `parse_error: Unterminated string` do GitHub Gist data >1MB — đã xóa hoàn toàn
- `project_photos` RLS policy đã tồn tại từ FIX_RLS_ANON.sql trước đó — không cần tạo lại
- auto_test.py FAIL sau Phase 7 do check `syncPush`/`syncPull` đã bị xóa — đã update test
