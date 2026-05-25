-- SECURITY_FEATURES.sql
-- Hai bảng mới: user_sessions + audit_log
-- Chạy trên Supabase SQL Editor: https://supabase.com/dashboard/project/kefwrfxeneropihedght/sql
-- Ngày tạo: 2026-05-04

-- ─────────────────────────────────────────────────────────────────────────────
-- BẢNG 1: user_sessions — theo dõi phiên đăng nhập và trạng thái online
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.user_sessions (
  id         uuid         default gen_random_uuid() primary key,
  role       text         not null,
  login_at   timestamptz  default now(),
  last_seen  timestamptz  default now(),
  logout_at  timestamptz,
  ip_hint    text         default '',
  user_agent text         default ''
);

comment on table  public.user_sessions             is 'Phiên đăng nhập — heartbeat mỗi 30 giây';
comment on column public.user_sessions.role        is 'admin / edit / view';
comment on column public.user_sessions.last_seen   is 'Cập nhật mỗi 30 giây. Online = last_seen > now()-2min AND logout_at IS NULL';
comment on column public.user_sessions.logout_at   is 'NULL nếu còn online hoặc đóng tab đột ngột (timeout sau 2 phút)';
comment on column public.user_sessions.user_agent  is 'navigator.userAgent (tối đa 200 ký tự)';

-- RLS: anon key có thể insert (tạo session) + update (heartbeat) + select (admin xem)
alter table public.user_sessions enable row level security;

create policy "anon_insert_sessions"
  on public.user_sessions for insert to anon
  with check (true);

create policy "anon_update_own_session"
  on public.user_sessions for update to anon
  using (true);

create policy "anon_select_sessions"
  on public.user_sessions for select to anon
  using (true);

-- Index để query nhanh (admin xem online users + hôm nay)
create index if not exists idx_user_sessions_last_seen
  on public.user_sessions (last_seen desc);

create index if not exists idx_user_sessions_login_at
  on public.user_sessions (login_at desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- BẢNG 2: audit_log — ghi lại ai sửa gì
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.audit_log (
  id          uuid        default gen_random_uuid() primary key,
  role        text        not null,
  action      text        not null,   -- create / update / delete
  table_name  text        default '',
  record_id   text        default '',
  description text        default '',
  created_at  timestamptz default now()
);

comment on table  public.audit_log             is 'Lịch sử thay đổi dữ liệu — ai sửa gì, lúc mấy giờ';
comment on column public.audit_log.action      is 'create / update / delete';
comment on column public.audit_log.role        is 'admin / edit / view';
comment on column public.audit_log.table_name  is 'Tên bảng Supabase bị thay đổi';
comment on column public.audit_log.record_id   is 'ID của bản ghi bị thay đổi';
comment on column public.audit_log.description is 'Mô tả thân thiện: "Thêm dự án XYZ", "Xóa nhân sự ABC"';

-- RLS: anon key có thể insert (ghi log khi thao tác) + select (admin xem)
alter table public.audit_log enable row level security;

create policy "anon_insert_audit"
  on public.audit_log for insert to anon
  with check (true);

create policy "anon_select_audit"
  on public.audit_log for select to anon
  using (true);

-- Index để filter nhanh theo ngày và role
create index if not exists idx_audit_log_created_at
  on public.audit_log (created_at desc);

create index if not exists idx_audit_log_role
  on public.audit_log (role, created_at desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY: kiểm tra 2 bảng đã tồn tại
-- ─────────────────────────────────────────────────────────────────────────────
select
  table_name,
  (select count(*) from information_schema.columns c where c.table_name = t.table_name and c.table_schema = 'public') as column_count
from information_schema.tables t
where table_schema = 'public'
  and table_name in ('user_sessions', 'audit_log')
order by table_name;
