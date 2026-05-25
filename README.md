# Gendai Sougo VN — Design Studio Performance Management

Ứng dụng quản lý dự án phối cảnh kiến trúc JP/VN. Single-page app, không cần server, deploy thẳng lên GitHub Pages.

---

## Deploy lên GitHub Pages

### Bước 1 — Tạo GitHub repository

```
1. Vào https://github.com/new
2. Tên repo: phoicanh (hoặc bất kỳ)
3. Visibility: Private (khuyến nghị — app có anon key Supabase)
4. Bấm "Create repository"
```

### Bước 2 — Push file lên GitHub

Chỉ cần đúng 1 file: `index.html`

```bash
# Tạo thư mục mới và init git
git init phoicanh-deploy
cd phoicanh-deploy

# Copy index.html vào
cp "E:\Dropbox\Bảng kết quả (Selective Sync Conflict)\index.html" .

# Commit và push
git add index.html
git commit -m "Deploy Gendai Sougo VN app"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/phoicanh.git
git push -u origin main
```

### Bước 3 — Bật GitHub Pages

```
1. Vào repo trên GitHub → Settings → Pages
2. Source: "Deploy from a branch"
3. Branch: main / (root)
4. Bấm Save
5. Chờ ~1 phút → URL xuất hiện:
   https://YOUR_USERNAME.github.io/phoicanh/
```

### Bước 4 — Thêm URL vào Supabase CORS whitelist

> ⚠ Bước này bắt buộc — nếu bỏ qua, app không kết nối được Supabase.

```
1. Vào https://supabase.com/dashboard
2. Chọn project: kefwrfxeneropihedght
3. Authentication → URL Configuration
4. Mục "Site URL":
   Nhập: https://YOUR_USERNAME.github.io
5. Mục "Additional Redirect URLs":
   Thêm: https://YOUR_USERNAME.github.io/phoicanh/
6. Bấm Save
```

**Lý do:** Supabase kiểm tra `Origin` header của request. Nếu domain chưa được whitelist, browser block request theo policy CORS.

### Bước 5 — Kiểm tra

```
1. Mở https://YOUR_USERNAME.github.io/phoicanh/
2. Đăng nhập bằng password admin
3. Mở DevTools (F12) → Console
4. Xác nhận không có lỗi CORS hay Supabase connection
5. Dữ liệu load được từ Supabase → migration thành công
```

---

## Cấu trúc deploy

```
GitHub Pages repo
└── index.html          ← toàn bộ app trong 1 file (766 KB)
                           HTML + CSS + JS + SVG icons
                           Kết nối Supabase qua CDN
```

Không cần:
- `package.json`, `node_modules`
- Build step
- Server-side code
- Database file (data trên Supabase)

---

## Cấu hình Supabase đầy đủ

### URL & Key (đã có trong app)
```
URL:      https://kefwrfxeneropihedght.supabase.co
ANON KEY: sb_publishable__B9f2R2Y1JMsvQ2NkmTU9Q_T8f4McGZ
```

### Các bảng cần thiết (đã tạo)
```
settings · months · projects · project_photos
groups · rows · tl_tasks · ot_log
staff · staff_leaves · staff_late_log · business_trips
pending_changes
```

Nếu chưa có bảng `pending_changes` → chạy file `PHASE_8_SCHEMA.sql` trong Supabase SQL Editor.

### RLS Policies
Đã có — xem file `FIX_RLS_ANON.sql`. Nếu gặp lỗi 403 khi đọc/ghi data → chạy lại file này.

### Realtime (cho sync đa thiết bị)
```
Supabase Dashboard → Database → Replication
Bật cho các bảng: rows, projects, months, pending_changes
```

---

## Thêm domain vào Supabase CORS — hướng dẫn chi tiết

Supabase cho phép REST API từ bất kỳ origin nào khi dùng anon key **trừ khi** project bật chế độ restrict origins.

### Cách kiểm tra và thêm:

**Authentication → URL Configuration:**

| Field | Giá trị |
|-------|---------|
| Site URL | `https://YOUR_USERNAME.github.io` |
| Additional Redirect URLs | `https://YOUR_USERNAME.github.io/phoicanh/` |

**Nếu dùng custom domain:**

| Field | Giá trị |
|-------|---------|
| Site URL | `https://yourdomain.com` |
| Additional Redirect URLs | `https://yourdomain.com/` |

> App này không dùng Supabase Auth (dùng hệ thống password riêng với anon key), nên phần "Redirect URLs" chủ yếu là cho CORS policy của Supabase JS client.

---

## Update app sau khi sửa

Mỗi lần sửa `index.html`:

```bash
cd phoicanh-deploy
cp "E:\Dropbox\Bảng kết quả (Selective Sync Conflict)\index.html" .
git add index.html
git commit -m "Update app $(date +%Y-%m-%d)"
git push
```

GitHub Pages tự deploy sau ~1 phút.

---

## Đăng nhập

| Role | Password | Quyền |
|------|----------|-------|
| admin | 204290 | Toàn quyền + duyệt yêu cầu |
| edit | 123456 | Nhập liệu (cần admin duyệt) |
| view | 280510 | Chỉ xem |

> Passwords được so sánh qua SHA-256 hash, không lưu plaintext trong source code.

---

## Troubleshooting

**Lỗi CORS khi gọi Supabase:**
→ Kiểm tra bước 4 — thêm GitHub Pages URL vào Supabase URL Configuration

**App load nhưng data trống:**
→ Kiểm tra Console lỗi. Có thể RLS block anon — chạy `FIX_RLS_ANON.sql`

**Realtime không hoạt động:**
→ Bật Replication trong Supabase Dashboard cho bảng `rows`, `projects`, `months`

**Ảnh không hiện:**
→ Kiểm tra bucket `project-photos` là Public trong Supabase Storage

**Nút "Duyệt" không xuất hiện cho admin:**
→ Chạy `PHASE_8_SCHEMA.sql` để tạo bảng `pending_changes`
