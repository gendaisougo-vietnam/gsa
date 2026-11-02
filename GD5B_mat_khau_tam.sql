-- ═══════════════════════════════════════════════════════════════════════════
-- GĐ5B — MẬT KHẨU TẠM + BẮT BUỘC ĐỔI Ở LẦN ĐĂNG NHẬP ĐẦU
-- AN TOÀN: chỉ thêm 2 cột và sửa/thêm hàm. Không xoá dữ liệu, không khoá quyền.
-- Chạy ở: Supabase Dashboard → SQL Editor → Run
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Hai cột mới trên bảng accounts ──
alter table public.accounts add column if not exists must_change_pw boolean not null default false;
alter table public.accounts add column if not exists pw_changed_at  timestamptz;

comment on column public.accounts.must_change_pw is 'true = đang dùng mật khẩu tạm, phải đổi ngay khi đăng nhập';
comment on column public.accounts.pw_changed_at  is 'lần người dùng tự đổi mật khẩu gần nhất';

-- ── 2. app_login: trả thêm cờ "phải đổi mật khẩu" ──
create or replace function public.app_login(p_pw text, p_acc text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_ip text; v_fail int; v_h text; v_role text; v_acc record;
        v_token uuid; v_perms jsonb := '{}'::jsonb; v_name text; v_code text;
        v_must boolean := false;
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
      v_must  := coalesce(v_acc.must_change_pw, false);
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
    'perms', v_perms, 'display_name', v_name, 'code', v_code,
    'must_change_pw', v_must);
end $$;

-- ── 3. app_session: F5 cũng trả cờ -> không lách được bằng cách tải lại trang ──
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
      'display_name', coalesce(a.display_name, a.code), 'code', a.code,
      'must_change_pw', coalesce(a.must_change_pw, false));
  end if;
  return jsonb_build_object('ok', true, 'role', s.role, 'perms', '{}'::jsonb,
    'display_name', s.display_name, 'code', null, 'must_change_pw', false);
end $$;

-- ── 4. Tạo / sửa tài khoản: mật khẩu do admin đặt LUÔN là mật khẩu tạm ──
create or replace function public.app_account_save(
  p_token uuid, p_id uuid, p_code text, p_name text, p_role text, p_perms jsonb, p_pw text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if not _is_admin_token(p_token) then raise exception 'Không có quyền'; end if;
  if p_id is null then
    if p_pw is null or length(p_pw) < 4 then raise exception 'Tài khoản mới cần mật khẩu'; end if;
    insert into accounts(code, display_name, role, permissions, is_active, pass_hash, pass_plain,
                         must_change_pw, pw_changed_at)
      values (p_code, p_name, coalesce(p_role,'custom'), coalesce(p_perms,'{}'::jsonb), true,
              encode(digest(p_pw || 'pc_salt', 'sha256'), 'hex'), null, true, null)
      returning id into v_id;
  else
    update accounts set display_name = p_name, role = coalesce(p_role,'custom'),
      permissions = coalesce(p_perms,'{}'::jsonb), updated_at = now(), pass_plain = null,
      pass_hash = case when p_pw is null or p_pw = '' then pass_hash
                       else encode(digest(p_pw || 'pc_salt', 'sha256'), 'hex') end,
      -- admin đặt lại mật khẩu => lại là mật khẩu tạm, người dùng phải tự đổi
      must_change_pw = case when p_pw is null or p_pw = '' then must_change_pw else true end,
      pw_changed_at  = case when p_pw is null or p_pw = '' then pw_changed_at  else null end
      where id = p_id returning id into v_id;
    if p_pw is not null and p_pw <> '' then
      delete from app_sessions where acc_code = p_code;        -- đổi mật khẩu là mất phiên cũ
    end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- ── 5. Admin cấp lại mật khẩu tạm (người dùng quên mật khẩu) ──
create or replace function public.app_account_reset_pw(p_token uuid, p_id uuid, p_newpw text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_code text;
begin
  if not _is_admin_token(p_token) then raise exception 'Không có quyền'; end if;
  if p_newpw is null or length(p_newpw) < 4 then raise exception 'Mật khẩu tạm quá ngắn'; end if;
  update accounts
     set pass_hash = encode(digest(p_newpw || 'pc_salt', 'sha256'), 'hex'),
         pass_plain = null, must_change_pw = true, pw_changed_at = null, updated_at = now()
   where id = p_id
   returning code into v_code;
  if v_code is null then raise exception 'Không tìm thấy tài khoản'; end if;
  delete from app_sessions where acc_code = v_code;            -- buộc đăng nhập lại
  return jsonb_build_object('ok', true, 'code', v_code);
end $$;

-- ── 6. Người dùng tự đặt mật khẩu riêng (màn bắt buộc đổi) ──
create or replace function public.app_change_my_password(p_token uuid, p_new text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s record; v_h text;
begin
  select * into s from app_sessions where token = p_token and expires_at > now();
  if not found then return jsonb_build_object('ok', false, 'message', 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.'); end if;
  if s.acc_code is null then
    return jsonb_build_object('ok', false, 'message', 'Tài khoản quản trị chung đổi mật khẩu ở mục "Đổi mật khẩu đăng nhập chung".');
  end if;
  if p_new is null or length(p_new) < 6 then
    return jsonb_build_object('ok', false, 'message', 'Mật khẩu mới phải từ 6 ký tự trở lên.');
  end if;
  v_h := encode(digest(p_new || 'pc_salt', 'sha256'), 'hex');
  if exists (select 1 from accounts where code = s.acc_code and pass_hash = v_h) then
    return jsonb_build_object('ok', false, 'message', 'Mật khẩu mới phải khác mật khẩu đang dùng.');
  end if;
  update accounts set pass_hash = v_h, pass_plain = null, must_change_pw = false,
                      pw_changed_at = now(), updated_at = now()
   where code = s.acc_code;
  delete from app_sessions where acc_code = s.acc_code and token <> p_token;   -- các máy khác phải đăng nhập lại
  return jsonb_build_object('ok', true);
end $$;

-- ── 7. Cho phép gọi bằng khoá công khai (bên trong đã tự kiểm quyền/token) ──
grant execute on function public.app_login(text, text)                         to anon, authenticated;
grant execute on function public.app_session(uuid)                             to anon, authenticated;
grant execute on function public.app_account_save(uuid, uuid, text, text, text, jsonb, text) to anon, authenticated;
grant execute on function public.app_account_reset_pw(uuid, uuid, text)        to anon, authenticated;
grant execute on function public.app_change_my_password(uuid, text)            to anon, authenticated;

-- ── Kiểm tra nhanh sau khi chạy ──
-- select code, display_name, must_change_pw, pw_changed_at from accounts order by created_at;

-- ═══════════════════════════════════════════════════════════════════════════
-- HOÀN TÁC (nếu cần quay lại như cũ)
-- ═══════════════════════════════════════════════════════════════════════════
-- update public.accounts set must_change_pw = false;
-- drop function if exists public.app_change_my_password(uuid, text);
-- drop function if exists public.app_account_reset_pw(uuid, uuid, text);
-- (app_login / app_session / app_account_save: chạy lại GD5A_buoc1_them_xac_thuc_server.sql)
