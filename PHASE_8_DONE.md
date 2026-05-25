# Phase 8 — Admin Approval Workflow — DONE

**Ngày hoàn thành:** 2026-04-29  
**Syntax check:** PASS (python auto_test.py — 11 pass, 0 fail, 0 warn, 9/9 phases)

## Mô tả

Khi nhân viên role `edit` hoặc `view` thực hiện thao tác thay đổi dữ liệu,
thay vì ghi thẳng vào Supabase, app tạo một **pending_changes** record.
Admin xem danh sách, duyệt hoặc từ chối từng yêu cầu.

## Thay đổi đã thực hiện

### SQL schema mới
- File `PHASE_8_SCHEMA.sql`: tạo bảng `pending_changes` với RLS cho anon
- Cần chạy trong Supabase SQL Editor trước khi dùng

### index.html — JS thêm mới
- `_needsApproval()` — kiểm tra role hiện tại có cần qua duyệt không
- `_sbQueueChange()` — gửi 1 pending_change lên Supabase
- `_sbQueueRowDebounced()` — debounce 1500ms, gộp nhiều field changes của 1 row thành 1 pending_change
- `refreshPendingBadge()` — cập nhật badge đếm số pending (admin only)
- `openPendingPanel()` — modal danh sách chờ duyệt với Approve/Reject mỗi item
- `approveChange(id)` — execute DB write thực tế + mark approved
- `rejectChange(id)` — mark rejected không ghi DB
- `approveAllChanges()` — duyệt tất cả cùng lúc

### index.html — Write functions đã sửa
| Hàm | Thay đổi |
|-----|---------|
| `updRow()` | edit/view → `_sbQueueRowDebounced()` thay vì `_sbSaveRowDebounced()` |
| `markRowDone()` | edit/view → `_sbQueueChange('rows', 'update', ...)` |
| `addGroup()` | edit/view → queue 2 pending_changes (group + first row) |
| `addRow()` | edit/view → queue 1 pending_change |
| `delGroup()` | edit/view → queue delete pending_change |
| `delRow()` | edit/view → queue delete pending_change |
| `confirmAddPj()` | edit/view → queue insert pending_change |
| `confirmEditPj()` | edit/view → queue upsert pending_change |
| `deletePj()` | edit/view → queue delete pending_change |

### index.html — Realtime subscription
- `startRealtimeSync()` thêm listener cho `pending_changes INSERT`
- Admin nhận toast notification tức thì khi có yêu cầu mới

### index.html — UI
- Header: thêm nút 📋 Duyệt (id=`pendingBtn`) — ẩn nếu không có pending
- Badge đỏ góc trên phải nút (id=`pendingBadge`) hiện số lượng pending
- `refreshPendingBadge()` được gọi sau login admin và sau session restore

### auto_test.py
- Thêm `openPendingPanel`, `approveChange` vào REQUIRED_FUNCTIONS (19/19)
- Thêm Phase 8 check: `_needsApproval` + `openPendingPanel` + `approveChange`
- Cập nhật count: 8 → 9 phases

## Cách hoạt động

```
[edit/view user]                [pending_changes table]        [admin]
     │                                   │                        │
     ├─ updRow() ─────────────────────── INSERT ──────────────────► toast 🔔
     ├─ markRowDone() ─────────────────► INSERT                   │
     ├─ addGroup() ─────────────────────► INSERT x2               │
     │                                   │              badge +1  │
     │                                   │            openPendingPanel()
     │                                   │                        ├─ Approve → execute write → Realtime → all clients update
     │                                   │                        └─ Reject  → mark rejected, no DB write
```

## Lưu ý

1. **Chạy PHASE_8_SCHEMA.sql** trong Supabase SQL Editor trước khi dùng
2. **Bật Replication** cho bảng `pending_changes` để Realtime notify admin
   (Dashboard → Database → Replication → chọn `pending_changes`)
3. **Optimistic update trong D vẫn hoạt động** — edit/view thấy thay đổi ngay trên UI
   nhưng DB chỉ cập nhật sau khi admin duyệt
4. Sau khi admin approve, Realtime sẽ broadcast change về các client khác

## Verify kết quả
- `python auto_test.py` → PASS 11/11, 9/9 phases
- Syntax JS: OK (6,811 dòng JS)
- Functions: 19/19 đủ (thêm openPendingPanel, approveChange)
- File size: 786,707 bytes (768 KB)

## Vấn đề gặp phải
- Không có
