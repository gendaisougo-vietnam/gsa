-- =============================================================
-- FIX RLS: Thêm policy cho anon role
-- Vấn đề: Schema chỉ có policy for 'authenticated'
-- App dùng anon key → cần thêm policy for 'anon'
--
-- Chạy toàn bộ file này trong Supabase SQL Editor
-- =============================================================

-- ── SELECT policies (anon được đọc tất cả bảng) ──────────────
create policy "anon_read_settings"
  on settings for select to anon using (true);

create policy "anon_read_months"
  on months for select to anon using (true);

create policy "anon_read_projects"
  on projects for select to anon using (true);

create policy "anon_read_groups"
  on groups for select to anon using (true);

create policy "anon_read_rows"
  on rows for select to anon using (true);

create policy "anon_read_tl_tasks"
  on tl_tasks for select to anon using (true);

create policy "anon_read_staff"
  on staff for select to anon using (true);

create policy "anon_read_staff_leaves"
  on staff_leaves for select to anon using (true);

create policy "anon_read_staff_late_log"
  on staff_late_log for select to anon using (true);

create policy "anon_read_business_trips"
  on business_trips for select to anon using (true);


-- ── WRITE policies (anon được ghi — app auth bằng password riêng) ──
create policy "anon_write_settings"
  on settings for all to anon using (true) with check (true);

create policy "anon_write_months"
  on months for all to anon using (true) with check (true);

create policy "anon_write_projects"
  on projects for all to anon using (true) with check (true);

create policy "anon_write_groups"
  on groups for all to anon using (true) with check (true);

create policy "anon_write_rows"
  on rows for all to anon using (true) with check (true);

create policy "anon_write_tl_tasks"
  on tl_tasks for all to anon using (true) with check (true);

create policy "anon_write_staff"
  on staff for all to anon using (true) with check (true);

create policy "anon_write_staff_leaves"
  on staff_leaves for all to anon using (true) with check (true);

create policy "anon_write_staff_late_log"
  on staff_late_log for all to anon using (true) with check (true);

create policy "anon_write_business_trips"
  on business_trips for all to anon using (true) with check (true);

-- ── project_photos table (thêm sau khi upload ảnh) ──────────
create policy "anon_read_project_photos"
  on project_photos for select to anon using (true);

create policy "anon_write_project_photos"
  on project_photos for all to anon using (true) with check (true);

-- ── Storage bucket "project-photos" — cho phép anon upload/delete ──
-- Chạy trong Supabase SQL Editor:
create policy "anon_upload_photos"
  on storage.objects for insert to anon
  with check (bucket_id = 'project-photos');

create policy "anon_delete_photos"
  on storage.objects for delete to anon
  using (bucket_id = 'project-photos');
