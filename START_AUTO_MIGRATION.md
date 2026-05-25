# START AUTO MIGRATION — Hướng dẫn khởi động

## Chuẩn bị trước khi bắt đầu

Kiểm tra 3 điều sau trong thư mục này:

```
index_backup_20260429.html   → phải tồn tại (bản gốc để rollback)
SUPABASE_SCHEMA.sql          → schema đã chạy lên Supabase
CLAUDE.md                    → hướng dẫn cho Claude Code
```

Nếu thiếu bất kỳ file nào → DỪNG, không chạy migration.

---

## Lệnh khởi động chính xác

Mở Claude Code, gõ đúng lệnh này (copy-paste nguyên văn):

```
Đọc CLAUDE.md và MIGRATION_PLAN.md, sau đó thực hiện tuần tự từ Phase 0 đến Phase 6 trên file index.html. Sau mỗi phase: chạy python auto_test.py để verify, rồi tạo file PHASE_X_DONE.md ghi kết quả. Nếu gặp lỗi không xử lý được: dừng lại, ghi vào ERRORS.md, báo cáo cho tôi. Không hỏi thêm, tự thực hiện theo đúng CLAUDE.md.
```

---

## Những gì Claude Code sẽ tự làm

### Phase 0 — Setup SDK (~5 phút)
- Tìm thẻ `<head>` trong `index.html`
- Chèn thẻ `<script>` CDN Supabase JS trước script chính
- Khởi tạo `_sb = supabase.createClient(...)` và `window._sbReady = true`
- Chạy `python auto_test.py` → phải thấy Supabase CDN chuyển từ `[~~]` sang `[OK]`
- Tạo `PHASE_0_DONE.md`

### Phase 1 — Auth (~10 phút)
- Tìm hàm `_splashLogin` trong IIFE `initSplash` (dòng ~7503)
- Thêm logic kiểm tra hash password qua `_sb.from('settings')` TRƯỚC `SPLASH_PW[pw]`
- Giữ nguyên `SPLASH_PW` làm fallback offline
- Chạy `python auto_test.py` → PASS
- Tạo `PHASE_1_DONE.md`

### Phase 2 — Read data (~15 phút)
- Thêm hàm `sbLoadAll()` vào đầu script — fetch 7 bảng song song, reconstruct D object
- Sửa `_splashLogin()` để gọi `sbLoadAll()` sau login thành công
- Cache D vào localStorage sau khi fetch (`localStorage.setItem(SK, ...)`)
- Chạy `python auto_test.py` → PASS, kiểm tra `sbLoadAll` xuất hiện
- Tạo `PHASE_2_DONE.md`

### Phase 3 — Write settings & months (~10 phút)
- Sửa `saveSettings()` — thêm `_sb.from('settings').update(...)` sau `persistD()`
- Sửa `updateMonthTarget()` — thêm `_sb.from('months').update(...)`
- Sửa `doAddMonth()` — thêm `_sb.from('months').upsert(...)`
- Wrap mọi Supabase call trong `try/catch`
- Chạy `python auto_test.py` → PASS
- Tạo `PHASE_3_DONE.md`

### Phase 4 — Write projects (~15 phút)
- Thêm helper `_sbSaveProject(p, monthId, section)`
- Sửa `confirmAddPj()`, `confirmEditPj()`, `deletePj()`
- Xử lý cascade delete: xóa project trên Supabase trước (groups/rows tự cascade)
- Chạy `python auto_test.py` → PASS
- Tạo `PHASE_4_DONE.md`

### Phase 5 — Write groups & rows (~20 phút)
- Thêm `_sbRowDebounce` và `_sbSaveRowDebounced()` với delay 1500ms
- Thêm `_COL_MAP` mapping field JS → column Supabase
- Sửa 7 hàm: `addGroup`, `addRow`, `updRow`, `updGroup`, `markRowDone`, `delGroup`, `delRow`
- `markRowDone` ghi NGAY (không debounce) — quan trọng
- Chạy `python auto_test.py` → PASS
- Tạo `PHASE_5_DONE.md`

### Phase 6 — Write staff (~15 phút)
- Cache `window._sbStaffIdByName` map trong `sbLoadAll()`
- Sửa 6 hàm: `saveStaffProfile`, `addLateRecord`, `deleteLateRecord`,
  `confirmAddLeave`, `delLeave`, `addTrip`, `deleteTrip`
- Mọi call dùng `_sbStaffIdByName[name]` để lấy UUID
- Chạy `python auto_test.py` → PASS
- Tạo `PHASE_6_DONE.md`

**Tổng thời gian ước tính: 90–120 phút**

---

## Những file cần kiểm tra khi Claude Code báo xong

### 1. Các file PHASE_X_DONE.md (7 file)

```
PHASE_0_DONE.md   ← Phase 0 xong
PHASE_1_DONE.md   ← Phase 1 xong
PHASE_2_DONE.md   ← Phase 2 xong
PHASE_3_DONE.md   ← Phase 3 xong
PHASE_4_DONE.md   ← Phase 4 xong
PHASE_5_DONE.md   ← Phase 5 xong
PHASE_6_DONE.md   ← Phase 6 xong
```

Nếu thiếu file nào → phase đó chưa hoàn thành hoặc bị lỗi.

### 2. Kết quả auto_test.py cuối cùng

Mở terminal, chạy:
```
python auto_test.py
```

Kết quả mong đợi sau Phase 6 hoàn chỉnh:
```
[OK] Syntax JS
[OK] Functions quan trong        Du 17/17
[OK] Supabase CDN (Phase 0)      cdn.jsdelivr.net/...
[OK] Supabase createClient       _sb = createClient(...) tim thay
[OK] Supabase URL                kefwrfxeneropihedght.supabase.co
[OK] Backup file nguyen ven      788,202 bytes (dung)
[OK] Kich thuoc file index.html  (lon hon 788,202 do da them code)
[OK] Khong co type=module
[OK] localStorage van hoat dong  64+ lan goi
[OK] D object init block
[OK] Phase migration             7/7 phases
KET QUA: PASS  (11 pass, 0 fail, 0 warn)
```

### 3. Kiểm tra Supabase Dashboard

Vào `https://supabase.com` → project → **Table Editor**:

| Bảng | Kiểm tra |
|------|---------|
| `settings` | `sync_config` có adminHash, editHash, viewHash |
| `months` | Có dữ liệu tháng hiện tại |
| `projects` | Đủ 31 dự án |
| `rows` | Đủ 107 rows |
| `staff` | 10 nhân viên |

### 4. Kiểm tra app thực tế

Mở `index.html` trong trình duyệt:

- [ ] Màn hình splash hiện lên bình thường
- [ ] Nhập password `204290` → vào được với quyền Admin
- [ ] Dữ liệu load đúng (dự án, tháng, nhân viên)
- [ ] Thêm 1 dự án test → vào Supabase Table Editor → thấy row mới
- [ ] Xóa dự án test → row biến mất khỏi Supabase
- [ ] Thay đổi qty ô bất kỳ → sau 1.5 giây → Supabase rows cập nhật
- [ ] Bấm "✓ UP" → `done_at` cập nhật ngay trên Supabase

### 5. Kiểm tra ERRORS.md

Nếu file này tồn tại → có lỗi đã xảy ra trong quá trình migration.
Đọc nội dung để biết phase nào bị lỗi và lý do.

---

## Cách dùng restore.bat nếu có vấn đề

**Khi nào dùng:**
- App bị lỗi sau migration, không đăng nhập được
- `auto_test.py` báo FAIL nhiều test
- `ERRORS.md` có nội dung nghiêm trọng
- Muốn bắt đầu lại từ đầu

**Cách dùng:**

Double-click file `restore.bat` trong thư mục này.

Hoặc chạy lệnh trong terminal:
```
"E:\Dropbox\Bảng kết quả (Selective Sync Conflict)\restore.bat"
```

File sẽ:
1. Copy `index_backup_20260429.html` → `index.html`
2. Hiện thông báo xác nhận
3. Dừng (nhấn phím bất kỳ để thoát)

**Sau khi restore:**
- Xóa các file `PHASE_X_DONE.md` để bắt đầu lại sạch
- Xóa `ERRORS.md` nếu muốn
- Đọc `ERRORS.md` để hiểu lỗi trước khi chạy lại
- Chạy `python auto_test.py` → xác nhận PASS trước khi thử lại

**Lưu ý:** Restore KHÔNG ảnh hưởng đến dữ liệu trên Supabase.
Dữ liệu trên Supabase vẫn nguyên vẹn.

---

## Tóm tắt nhanh

```
Bước 1:  Mở Claude Code trong thư mục này
Bước 2:  Paste lệnh khởi động (mục trên)
Bước 3:  Chờ ~90-120 phút, không làm gián đoạn
Bước 4:  Kiểm tra 7 file PHASE_X_DONE.md
Bước 5:  Chạy python auto_test.py → PASS
Bước 6:  Mở index.html trong browser, test thực tế
Nếu lỗi: Double-click restore.bat → bắt đầu lại
```
