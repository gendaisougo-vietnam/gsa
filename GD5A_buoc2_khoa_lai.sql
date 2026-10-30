-- ═══════════════════════════════════════════════════════════════════════════
-- GĐ5A — BƯỚC 2: KHOÁ LẠI
-- ⚠ CHỈ CHẠY SAU KHI: đã chạy Bước 1, đã deploy app mới, và ĐÃ ĐĂNG NHẬP THỬ THÀNH CÔNG.
-- Sau bước này: mã băm mật khẩu và lương KHÔNG còn đọc được bằng khoá công khai.
-- Gỡ lại: xem khối "HOÀN TÁC" ở cuối file.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. settings: ẩn sync_config (đang chứa mã băm mật khẩu chung) ──
revoke select, update on public.settings from anon;
grant select (id, staff_list, type_list, type_list_vn, type_list_intl, contact_list,
              contact_list_vn, holidays, active_month, created_at, updated_at, leaving_warn_days)
  on public.settings to anon;
grant update (staff_list, type_list, type_list_vn, type_list_intl, contact_list,
              contact_list_vn, holidays, active_month, updated_at, leaving_warn_days)
  on public.settings to anon;

-- Xoá luôn mã băm khỏi settings (đã chuyển sang auth_master ở Bước 1)
update public.settings set sync_config = '{}'::jsonb;

-- ── 2. staff: ẩn lương ──
revoke select, update, insert on public.staff from anon;
grant select (id, full_name, short_name, office, role, contract_end, sort_order, is_active,
              created_at, updated_at, status, leave_date, avatar_url, emp_type,
              probation_start, probation_end) on public.staff to anon;
grant update (full_name, short_name, office, role, contract_end, sort_order, is_active,
              updated_at, status, leave_date, avatar_url, emp_type,
              probation_start, probation_end) on public.staff to anon;
grant insert (id, full_name, short_name, office, role, contract_end, sort_order, is_active,
              status, leave_date, avatar_url, emp_type, probation_start, probation_end)
  on public.staff to anon;

-- ── 3. accounts: không ai đọc/ghi trực tiếp nữa (chỉ qua hàm app_account_*) ──
revoke all on public.accounts from anon;
update public.accounts set pass_plain = null;   -- xoá mật khẩu dạng chữ còn sót

select 'BƯỚC 2 XONG — mã băm mật khẩu và lương đã khoá khỏi khoá công khai' as ket_qua;

-- ═══════════════════════════════════════════════════════════════════════════
-- HOÀN TÁC (chỉ chạy nếu có sự cố, để quay lại như trước Bước 2)
-- ═══════════════════════════════════════════════════════════════════════════
-- grant select, update on public.settings to anon;
-- grant select, update, insert on public.staff to anon;
-- grant all on public.accounts to anon;
