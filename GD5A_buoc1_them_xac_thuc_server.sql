-- ═══════════════════════════════════════════════════════════════════════════
-- GĐ5A — BƯỚC 1: Thêm xác thực phía server
-- AN TOÀN: chỉ THÊM bảng/hàm mới, KHÔNG khoá gì, app cũ vẫn chạy y nguyên.
-- Chạy ở: Supabase Dashboard → SQL Editor → Run
-- ═══════════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto with schema extensions;

-- ── Kho mã băm mật khẩu chung (admin / edit / view) — anon KHÔNG đọc được ──
create table if not exists public.auth_master (
  role       text primary key,
  pass_hash  text not null,
  updated_at timestamptz not null default now()
);
alter table public.auth_master enable row level security;   -- không policy = anon mù hoàn toàn

-- Nạp mã băm hiện hành để không ai bị khoá ngoài khi chuyển đổi
insert into public.auth_master(role, pass_hash) values
  ('admin','970070237e5196d1b06394f5a0c5036bbd8c785a738e1af9babe4f7fb4f2d58b'),
  ('edit', '7c3bf372304f2d2b762dd40bccc87b62d8c0accd79341bdd83fb89c8913d4b5e'),
  ('view', '0b49c05e4db93fd3339c046285587ca5563531e46ed12dc6ed3f3dfe2bcc8363')
on conflict (role) do nothing;

-- ── Phiên đăng nhập (token do server cấp) ──
create table if not exists public.app_sessions (
  token        uuid primary key default gen_random_uuid(),
  role         text not null,
  acc_code     text,
  display_name text,
  perms        jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  last_seen    timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '14 days'
);
alter table public.app_sessions enable row level security;

-- ── Nhật ký đăng nhập (để chặn dò mật khẩu) ──
create table if not exists public.login_attempts (
  id  bigserial primary key,
  at  timestamptz not null default now(),
  ip  text, acc text, ok boolean not null
);
alter table public.login_attempts enable row level security;
create index if not exists login_attempts_at_idx on public.login_attempts(at desc);

-- ── Đăng nhập: so mã băm NGAY TRÊN SERVER, giới hạn số lần sai ──
create or replace function public.app_login(p_pw text, p_acc text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_ip text; v_fail int; v_h text; v_role text; v_acc record;
        v_token uuid; v_perms jsonb := '{}'::jsonb; v_name text; v_code text;
begin
  begin
    v_ip := coalesce(split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1), 'unknown');
  exception when others then v_ip := 'unknown'; end;

  select count(*) into v_fail from login_attempts
   where ok = false and at > now() - interval '15 minutes' and ip = v_ip;
  if v_fail >= 15 then
    return jsonb_build_object('ok', false, 'error', 'locked',
      'message', 'Nhập sai quá nhiều lần. Vui lòng thử lại sau 15 phút.');
  end if;

  v_h := encode(digest(p_pw || 'pc_salt', 'sha256'), 'hex');

  select role into v_role from auth_master where pass_hash = v_h limit 1;
  if v_role is null then
    select * into v_acc from accounts
      where pass_hash = v_h and is_active = true and (p_acc is null or code = p_acc)
      order by created_at limit 1;
    if found then
      v_role  := case when v_acc.role = 'admin' then 'admin' else 'custom' end;
      v_perms := coalesce(v_acc.permissions, '{}'::jsonb);
      v_name  := coalesce(v_acc.display_name, v_acc.code);
      v_code  := v_acc.code;
    end if;
  end if;

  if v_role is null then
    insert into login_attempts(ip, acc, ok) values (v_ip, p_acc, false);
    return jsonb_build_object('ok', false, 'error', 'bad_password');
  end if;

  insert into login_attempts(ip, acc, ok) values (v_ip, p_acc, true);
  insert into app_sessions(role, acc_code, display_name, perms)
       values (v_role, v_code, v_name, v_perms) returning token into v_token;

  delete from login_attempts where at < now() - interval '7 days';
  delete from app_sessions   where expires_at < now();

  return jsonb_build_object('ok', true, 'role', v_role, 'token', v_token,
    'perms', v_perms, 'display_name', v_name, 'code', v_code);
end $$;

-- ── Kiểm tra phiên (F5 / định kỳ): tài khoản bị Tắt thì phiên hết hiệu lực ──
create or replace function public.app_session(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s record; a record;
begin
  select * into s from app_sessions where token = p_token and expires_at > now();
  if not found then return jsonb_build_object('ok', false); end if;
  update app_sessions set last_seen = now() where token = p_token;
  if s.acc_code is not null then
    select * into a from accounts where code = s.acc_code;
    if not found or a.is_active = false then
      delete from app_sessions where token = p_token;
      return jsonb_build_object('ok', false, 'error', 'disabled');
    end if;
    return jsonb_build_object('ok', true,
      'role', case when a.role = 'admin' then 'admin' else 'custom' end,
      'perms', coalesce(a.permissions, '{}'::jsonb),
      'display_name', coalesce(a.display_name, a.code), 'code', a.code);
  end if;
  return jsonb_build_object('ok', true, 'role', s.role, 'perms', '{}'::jsonb,
    'display_name', s.display_name, 'code', null);
end $$;

create or replace function public.app_logout(p_token uuid)
returns void language sql security definer set search_path = public as $$
  delete from app_sessions where token = p_token;
$$;

create or replace function public._is_admin_token(p_token uuid)
returns boolean language sql security definer set search_path = public as $$
  select exists(select 1 from app_sessions
                 where token = p_token and expires_at > now() and role = 'admin');
$$;

-- ── Quản lý tài khoản (chỉ admin, qua token — không ai đọc được mã băm) ──
create or replace function public.app_accounts_list(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not _is_admin_token(p_token) then raise exception 'Không có quyền'; end if;
  return coalesce((select jsonb_agg(to_jsonb(a) - 'pass_hash' - 'pass_plain' order by a.created_at)
                     from accounts a), '[]'::jsonb);
end $$;

create or replace function public.app_account_save(
  p_token uuid, p_id uuid, p_code text, p_name text, p_role text, p_perms jsonb, p_pw text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if not _is_admin_token(p_token) then raise exception 'Không có quyền'; end if;
  if p_id is null then
    if p_pw is null or length(p_pw) < 4 then raise exception 'Tài khoản mới cần mật khẩu'; end if;
    insert into accounts(code, display_name, role, permissions, is_active, pass_hash, pass_plain)
      values (p_code, p_name, coalesce(p_role,'custom'), coalesce(p_perms,'{}'::jsonb), true,
              encode(digest(p_pw || 'pc_salt', 'sha256'), 'hex'), null)
      returning id into v_id;
  else
    update accounts set display_name = p_name, role = coalesce(p_role,'custom'),
      permissions = coalesce(p_perms,'{}'::jsonb), updated_at = now(), pass_plain = null,
      pass_hash = case when p_pw is null or p_pw = '' then pass_hash
                       else encode(digest(p_pw || 'pc_salt', 'sha256'), 'hex') end
      where id = p_id returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.app_account_set_active(p_token uuid, p_id uuid, p_active boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not _is_admin_token(p_token) then raise exception 'Không có quyền'; end if;
  update accounts set is_active = p_active, updated_at = now() where id = p_id;
  if not p_active then delete from app_sessions
    where acc_code = (select code from accounts where id = p_id); end if;   -- tắt là mất phiên ngay
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.app_account_delete(p_token uuid, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not _is_admin_token(p_token) then raise exception 'Không có quyền'; end if;
  delete from app_sessions where acc_code = (select code from accounts where id = p_id);
  delete from accounts where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- Link ?acc=<mã> chỉ cần hiện TÊN, không lộ gì khác
create or replace function public.app_account_name(p_code text)
returns text language sql security definer set search_path = public as $$
  select display_name from accounts where code = p_code and is_active = true limit 1;
$$;

-- ── Đổi mật khẩu đăng nhập chung (admin/edit/view) ──
create or replace function public.app_set_master_password(p_token uuid, p_role text, p_newpw text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  if not _is_admin_token(p_token) then raise exception 'Không có quyền'; end if;
  if p_role not in ('admin','edit','view') then raise exception 'Vai trò không hợp lệ'; end if;
  if p_newpw is null or length(p_newpw) < 8 then raise exception 'Mật khẩu phải từ 8 ký tự trở lên'; end if;
  insert into auth_master(role, pass_hash)
    values (p_role, encode(digest(p_newpw || 'pc_salt', 'sha256'), 'hex'))
    on conflict (role) do update set pass_hash = excluded.pass_hash, updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

-- ── Lương: chỉ admin đọc/ghi, qua token ──
create or replace function public.app_staff_salaries(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not _is_admin_token(p_token) then raise exception 'Không có quyền'; end if;
  return coalesce((select jsonb_object_agg(full_name,
            jsonb_build_object('g', salary_gross, 'n', salary_net)) from staff), '{}'::jsonb);
end $$;

create or replace function public.app_staff_set_salary(p_token uuid, p_name text, p_gross numeric, p_net numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not _is_admin_token(p_token) then raise exception 'Không có quyền'; end if;
  update staff set salary_gross = p_gross, salary_net = p_net, updated_at = now()
   where full_name = p_name;
  return jsonb_build_object('ok', true);
end $$;

-- ── Cho phép gọi các hàm trên bằng khoá công khai (bên trong đã tự kiểm quyền) ──
grant execute on function public.app_login(text,text)                         to anon, authenticated;
grant execute on function public.app_session(uuid)                            to anon, authenticated;
grant execute on function public.app_logout(uuid)                             to anon, authenticated;
grant execute on function public.app_accounts_list(uuid)                      to anon, authenticated;
grant execute on function public.app_account_save(uuid,uuid,text,text,text,jsonb,text) to anon, authenticated;
grant execute on function public.app_account_set_active(uuid,uuid,boolean)    to anon, authenticated;
grant execute on function public.app_account_delete(uuid,uuid)                to anon, authenticated;
grant execute on function public.app_account_name(text)                       to anon, authenticated;
grant execute on function public.app_set_master_password(uuid,text,text)      to anon, authenticated;
grant execute on function public.app_staff_salaries(uuid)                     to anon, authenticated;
grant execute on function public.app_staff_set_salary(uuid,text,numeric,numeric) to anon, authenticated;
revoke execute on function public._is_admin_token(uuid) from public, anon, authenticated;

select 'BƯỚC 1 XONG — chưa khoá gì, app cũ vẫn chạy bình thường' as ket_qua;
