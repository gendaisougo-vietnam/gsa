-- =============================================================
-- PHASE 8: Bảng pending_changes — Admin Approval Workflow
-- Mục đích: Edit/view user gửi yêu cầu thay vì ghi thẳng DB
--
-- Chạy toàn bộ file này trong Supabase SQL Editor → Run
-- =============================================================

-- Tạo bảng pending_changes
create table if not exists pending_changes (
  id          uuid default gen_random_uuid() primary key,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  table_name  text not null,         -- 'rows', 'groups', 'projects'
  operation   text not null,         -- 'insert', 'upsert', 'update', 'delete'
  record_id   text,                  -- id của record bị ảnh hưởng
  payload     jsonb,                 -- dữ liệu cần ghi (null cho delete)
  context     jsonb,                 -- { projectId, monthId, ... }
  submitted_by text,                 -- 'edit' hoặc 'view'
  status      text default 'pending',-- 'pending', 'approved', 'rejected'
  reviewed_at timestamptz,
  description text                   -- mô tả thân thiện: "Sửa qty → 5 | Dự án ABC"
);

-- Index để query nhanh
create index if not exists idx_pending_status on pending_changes(status);
create index if not exists idx_pending_created on pending_changes(created_at desc);

-- RLS
alter table pending_changes enable row level security;

create policy "anon_read_pending_changes"
  on pending_changes for select to anon using (true);

create policy "anon_write_pending_changes"
  on pending_changes for all to anon using (true) with check (true);

-- Bật Realtime cho bảng này
-- (Nếu chưa bật: Supabase Dashboard → Database → Replication → chọn pending_changes)
