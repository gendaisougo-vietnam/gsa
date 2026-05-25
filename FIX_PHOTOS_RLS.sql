-- =============================================================
-- FIX PHOTOS: Thêm RLS policy cho bảng project_photos + Storage
-- Vấn đề: project_photos chỉ có policy cho 'authenticated'
-- App dùng anon key → phải thêm policy cho 'anon'
--
-- Chạy toàn bộ file này trong Supabase SQL Editor → Run
-- =============================================================

-- 1. Cho anon đọc bảng project_photos
create policy "anon_read_project_photos"
  on project_photos for select to anon using (true);

-- 2. Cho anon ghi vào bảng project_photos (upsert khi upload ảnh mới)
create policy "anon_write_project_photos"
  on project_photos for all to anon using (true) with check (true);

-- 3. Cho anon upload file lên Storage bucket "project-photos"
create policy "anon_upload_photos"
  on storage.objects for insert to anon
  with check (bucket_id = 'project-photos');

-- 4. Cho anon xóa file trong Storage bucket "project-photos"
create policy "anon_delete_photos"
  on storage.objects for delete to anon
  using (bucket_id = 'project-photos');
