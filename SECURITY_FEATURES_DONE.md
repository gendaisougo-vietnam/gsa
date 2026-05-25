# Security Features — Online Presence + Audit Log — DONE

**Ngày hoàn thành:** 2026-05-04  
**Auto test:** PASS (12 pass, 0 fail, 0 warn — 14/14 security checks)

---

## Tổng quan

Thêm 2 tính năng bảo mật vào app Studio Design mà không phá vỡ bất kỳ tính năng cũ nào.

---

## TÍNH NĂNG 1 — Online Presence + Access Log

### Bảng Supabase mới: `user_sessions`
File: `SECURITY_FEATURES.sql`
- `id` (uuid PK), `role`, `login_at`, `last_seen`, `logout_at`, `ip_hint`, `user_agent`
- RLS: anon insert + update + select
- Index: `idx_user_sessions_last_seen`, `idx_user_sessions_login_at`

### JavaScript functions mới (sau `openPendingPanel`)
| Function | Mô tả |
|---|---|
| `_sbSessionCreate(role)` | Tạo session row khi đăng nhập, bắt đầu heartbeat 30 giây |
| `_sbSessionEnd()` | Cập nhật `logout_at` khi đóng tab (keepalive fetch) |
| `refreshOnlineBadge()` | Cập nhật badge số người online trên header |
| `openOnlinePanel()` | Modal hiển thị ai đang online + lượt truy cập hôm nay |

### Tích hợp vào login flow
- `_splashLogin()` (login mới): Gọi `_sbSessionCreate(role)` sau `startRealtimeSync()`
- `initSplash` (session cũ): Gọi `_sbSessionCreate(sessionRole)` sau `refreshPendingBadge()`

### Header badge `#onlineBtn`
- Nút "👁 Online" (ẩn mặc định) hiện cạnh "📋 Duyệt"
- Badge đỏ hiện số người online nếu > 1
- `applyRoleUI(admin)` hiện nút, bắt đầu poll `refreshOnlineBadge` mỗi 30 giây

### beforeunload handler
```js
window.addEventListener('beforeunload', function() {
  try { _sbSessionEnd(); } catch(e) {}
});
```

### Modal "Đang trực tuyến"
- Bảng 1: Ai đang online (role, giờ vào, heartbeat cuối)
- Bảng 2: Lượt truy cập hôm nay (role, giờ vào, giờ ra/trạng thái)
- Nút "🔄 Làm mới" reload data từ Supabase

---

## TÍNH NĂNG 2 — Audit Log

### Bảng Supabase mới: `audit_log`
File: `SECURITY_FEATURES.sql`
- `id` (uuid PK), `role`, `action` (create/update/delete), `table_name`, `record_id`, `description`, `created_at`
- RLS: anon insert + select
- Index: `idx_audit_log_created_at`, `idx_audit_log_role`

### Helper function
```js
async function _sbAuditLog(action, tableName, recordId, description)
```
Fire-and-forget, không block UI.

### Audit hooks (14 hooks tổng cộng)
| Function | Action | Mô tả log |
|---|---|---|
| `confirmAddPj()` | create/projects | Thêm dự án: "tên" |
| `confirmEditPj(id)` | update/projects | Sửa dự án: "tên" |
| `deletePj(id)` | delete/projects | Xóa dự án: "tên" |
| `addGroup(pjId)` | create/groups | Thêm hạng mục cho "dự án" |
| `delGroup(pjId, gid2)` | delete/groups | Xóa hạng mục trong "dự án" |
| `saveStaffProfile(name, field, val)` | update/staff | Sửa nhân sự: name — field |
| `confirmAddLeave(name)` | create/staff_leaves | Thêm nghỉ phép cho name (ngày) |
| `addTrip(name)` | create/business_trips | Thêm công tác cho name (từ → đến) |

### Panel trong Settings (admin only)
- Thêm card "🔐 Bảo mật & Giám sát" ở cuối trang Settings
- Bộ lọc: theo ngày + theo role
- Auto-load khi mở Settings (setTimeout 400ms)
- Nút "👁 Xem ai online" mở `openOnlinePanel()`
- `openAuditLogPanel(dateFilter, roleFilter)` render vào `#auditLogContent`

---

## Files đã thay đổi

| File | Thay đổi |
|---|---|
| `SECURITY_FEATURES.sql` | **Tạo mới** — SQL cho 2 bảng + RLS + index |
| `index.html` | +238 dòng — header badge, 6 functions, 8 audit hooks, 2 session hooks, Settings panel |
| `auto_test.py` | +43 dòng — TEST 10 với 14 security checks |
| `SECURITY_FEATURES_DONE.md` | **File này** |

## Dòng số thay đổi trong index.html
- L629–631: Thêm `#onlineBtn` + `#onlineBadge` vào header
- L1027–1200: Thêm 6 security functions (sau `openPendingPanel`)
- L4575: `_sbAuditLog('create', 'groups', ...)` trong `addGroup`
- L4628: `_sbAuditLog('delete', 'groups', ...)` trong `delGroup`
- L4731: `_sbAuditLog('create', 'projects', ...)` trong `confirmAddPj`
- L4770: `_sbAuditLog('update', 'projects', ...)` trong `confirmEditPj`
- L5096: `_sbAuditLog('delete', 'projects', ...)` trong `deletePj`
- L5655: `_sbAuditLog('update', 'staff', ...)` trong `saveStaffProfile`
- L5884: `_sbAuditLog('create', 'business_trips', ...)` trong `addTrip`
- L5958: `_sbAuditLog('create', 'staff_leaves', ...)` trong `confirmAddLeave`
- L6806–6830: Card bảo mật trong `renderSettings()`
- L7628–7638: `applyRoleUI` hiện `#onlineBtn` cho admin
- L7730: `_sbSessionCreate(role)` trong login flow mới
- L7768: `_sbSessionCreate(sessionRole)` trong login flow đã có session
- L7736–7738: `beforeunload` listener

## Vấn đề gặp phải
- Không có vấn đề nào
