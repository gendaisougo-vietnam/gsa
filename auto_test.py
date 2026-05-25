"""
auto_test.py — Kiểm tra index.html sau mỗi phase migration

Chạy: python auto_test.py
"""

import os, re, sys, time
import esprima

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INDEX_PATH = os.path.join(SCRIPT_DIR, 'index.html')
PATH = INDEX_PATH

PASS = "PASS"
FAIL = "FAIL"
results = []

def check(name, ok, detail=""):
    status = PASS if ok else FAIL
    results.append((status, name, detail))

# ─────────────────────────────────────────────────────────────
# Đọc file
# ─────────────────────────────────────────────────────────────
try:
    with open(PATH, encoding="utf-8") as f:
        html = f.read()
except Exception as e:
    print(f"[ERROR] Khong doc duoc file: {e}")
    sys.exit(1)

lines = html.split("\n")
total_lines = len(lines)

# ─────────────────────────────────────────────────────────────
# TEST 1 — Syntax JS
# ─────────────────────────────────────────────────────────────
def preprocess_js(js):
    js = re.sub(r'\|\|=', '=', js)
    js = re.sub(r'&&=', '=', js)
    js = re.sub(r'\?\?=', '=', js)
    js = re.sub(r'\?\?', '||', js)
    js = re.sub(r'\?\.\[', '[', js)
    js = re.sub(r'\?\.', '.', js)
    js = re.sub(r'\?\.\(', '(', js)
    js = re.sub(r'(\d)_(\d)', r'\1\2', js)
    js = re.sub(r'#(\w)', r'_\1', js)
    return js

scripts = re.findall(r"<script(?:[^>]*)>([\s\S]*?)</script>", html, re.IGNORECASE)
inline  = [s for s in scripts if s.strip()]

syntax_errors = []
for i, js in enumerate(inline):
    preprocessed = preprocess_js(js)
    try:
        result = esprima.parseScript(preprocessed, tolerant=True)
        for err in (result.errors or []):
            lineno = err.get("lineNumber")
            desc   = err.get("description", str(err))
            orig   = js.split("\n")[lineno-1].strip() if lineno else ""
            syntax_errors.append(f"Block {i+1} Line {lineno}: {desc} | {orig[:80]}")
    except esprima.Error as e:
        syntax_errors.append(f"Block {i+1}: {e}")

check(
    "Syntax JS",
    len(syntax_errors) == 0,
    f"{len(syntax_errors)} loi" if syntax_errors else f"OK ({sum(len(s.split(chr(10))) for s in inline):,} dong JS)"
)
for err in syntax_errors[:5]:
    print(f"         >> {err}")

# ─────────────────────────────────────────────────────────────
# TEST 2 — Các function quan trọng vẫn còn
# ─────────────────────────────────────────────────────────────
REQUIRED_FUNCTIONS = [
    "persistD",
    "save",
    "renderAll",
    "startRealtimeSync",
    "sbReloadData",
    "renderDashboard",
    "renderContent",
    "renderSidebar",
    "renderStaffPage",
    "addGroup",
    "addRow",
    "updRow",
    "markRowDone",
    "saveStaffProfile",
    "exportBackup",
    "freshData",
    "_splashLogin",
    "openPendingPanel",
    "approveChange",
    "handleSearch",
    "navigateToResult",
]

missing = []
found   = []
for fn in REQUIRED_FUNCTIONS:
    # Khớp cả 2 kiểu khai báo:
    #   function foo(       → khai bao thong thuong
    #   window.foo = function(  → gan vao window (vi du _splashLogin)
    #   foo = function(         → bien function
    pattern = rf'(?:function\s+{re.escape(fn)}\s*\(|(?:window\.)?{re.escape(fn)}\s*=\s*(?:async\s+)?function\s*\()'
    if re.search(pattern, html):
        found.append(fn)
    else:
        missing.append(fn)

check(
    "Functions quan trong",
    len(missing) == 0,
    f"Du {len(found)}/{len(REQUIRED_FUNCTIONS)}" if not missing else f"THIEU: {', '.join(missing)}"
)

# ─────────────────────────────────────────────────────────────
# TEST 3 — Supabase SDK da duoc them chua
# ─────────────────────────────────────────────────────────────
has_cdn     = "supabase-js" in html and "cdn.jsdelivr.net" in html
has_client  = "_sb" in html and "createClient" in html
has_url     = "kefwrfxeneropihedght.supabase.co" in html

# Supabase checks: WARN neu chua co (Phase 0 chua chay), PASS neu co
# Khong FAIL cung toan bo vi day la kiem tra trang thai migration, khong phai loi
def check_warn(name, ok, ok_msg, warn_msg):
    """Ket qua PASS neu ok, WARN (khong FAIL) neu chua co."""
    status = PASS if ok else "WARN"
    results.append((status, name, ok_msg if ok else warn_msg))

check_warn(
    "Supabase CDN (Phase 0)",
    has_cdn,
    "cdn.jsdelivr.net/npm/@supabase/supabase-js",
    "Chua them - can thuc hien Phase 0"
)
check_warn(
    "Supabase createClient (Phase 0)",
    has_client,
    "_sb = createClient(...) tim thay",
    "Chua co - can thuc hien Phase 0"
)
check_warn(
    "Supabase URL (Phase 0)",
    has_url,
    "kefwrfxeneropihedght.supabase.co",
    "Chua co - can thuc hien Phase 0"
)

# ─────────────────────────────────────────────────────────────
# TEST 4 — Backup file nguyen ven
# ─────────────────────────────────────────────────────────────
BACKUP_PATH = os.path.join(SCRIPT_DIR, 'index_backup_20260429.html')
BACKUP_EXPECTED_SIZE = 788202

backup_ok = False
backup_detail = ""
if os.path.exists(BACKUP_PATH):
    size = os.path.getsize(BACKUP_PATH)
    backup_ok = (size == BACKUP_EXPECTED_SIZE)
    backup_detail = f"{size:,} bytes {'(dung)' if backup_ok else f'(SAI! Can {BACKUP_EXPECTED_SIZE:,})'}"
else:
    backup_detail = "FILE KHONG TON TAI!"

check("Backup file nguyen ven", backup_ok, backup_detail)

# ─────────────────────────────────────────────────────────────
# TEST 5 — Kich thuoc file hop ly
# ─────────────────────────────────────────────────────────────
file_size = os.path.getsize(PATH)
size_ok   = file_size >= 700_000  # khong nho hon 700KB (tranh truong hop bi xoa nhieu)
check(
    "Kich thuoc file index.html",
    size_ok,
    f"{file_size:,} bytes ({file_size/1024:.0f} KB)"
)

# ─────────────────────────────────────────────────────────────
# TEST 6 — Kiem tra khong co type=module trong script chinh
# ─────────────────────────────────────────────────────────────
# Script chinh la script lon nhat, khong duoc co type="module"
# (chi Supabase CDN script la ok vi no la external)
main_script_blocks = re.findall(r'<script([^>]*)>([\s\S]{1000,}?)</script>', html, re.IGNORECASE)
has_bad_module = any(
    'type="module"' in attrs or "type='module'" in attrs
    for attrs, _ in main_script_blocks
)
check(
    "Khong co type=module trong script chinh",
    not has_bad_module,
    "OK - script chinh khong dung module" if not has_bad_module else "NGUY HIEM: script chinh co type=module se pha vo global scope!"
)

# ─────────────────────────────────────────────────────────────
# TEST 7 — localStorage van duoc su dung (chua bi xoa)
# ─────────────────────────────────────────────────────────────
ls_count = len(re.findall(r'localStorage\.(setItem|getItem)', html))
check(
    "localStorage van hoat dong",
    ls_count >= 10,
    f"{ls_count} lan goi localStorage (offline cache con nguyen)"
)

# ─────────────────────────────────────────────────────────────
# TEST 8 — D object init block con nguyen
# ─────────────────────────────────────────────────────────────
has_d_init = "let D = (() =>" in html or "let D=(" in html
check(
    "D object init block",
    has_d_init,
    "let D = (() => { ... })() tim thay" if has_d_init else "MISSING: khoi tao D object bi mat!"
)

# ─────────────────────────────────────────────────────────────
# TEST 9 — Phase markers (Supabase additions)
# ─────────────────────────────────────────────────────────────
phase_checks = {
    "Phase 0 - SDK tag"       : "Supabase SDK" in html or "_sbReady" in html,
    "Phase 1 - sbAuth logic"  : "_sbReady" in html,
    "Phase 2 - sbLoadAll"     : "sbLoadAll" in html,
    "Phase 3 - settings write": "_sbSettingsId" in html or "settings').update" in html,
    "Phase 4 - project write" : "_sbSaveProject" in html,
    "Phase 5 - row write"     : "_sbSaveRowDebounced" in html or "_COL_MAP" in html,
    "Phase 6 - staff write"   : "_sbStaffIdByName" in html,
    "Phase 7 - Realtime"      : "startRealtimeSync" in html and "checkMorningNotification" in html,
    "Phase 8 - Approval WF"   : "_needsApproval" in html and "openPendingPanel" in html and "approveChange" in html,
}
phases_done = [name for name, done in phase_checks.items() if done]
phases_todo = [name for name, done in phase_checks.items() if not done]

check(
    "Phase migration da thuc hien",
    True,  # khong fail, chi bao cao
    f"{len(phases_done)}/9 phases: {', '.join(phases_done) if phases_done else 'Chua co phase nao'}"
)
if phases_todo:
    print(f"         >> Chua co: {', '.join(phases_todo)}")

# ─────────────────────────────────────────────────────────────
# TEST 10 — Security Features: Online Presence + Audit Log
# ─────────────────────────────────────────────────────────────
security_checks = {
    "AuditLog func"      : "_sbAuditLog" in html,
    "SessionCreate func" : "_sbSessionCreate" in html,
    "SessionEnd func"    : "_sbSessionEnd" in html,
    "OnlineBadge func"   : "refreshOnlineBadge" in html,
    "OnlinePanel func"   : "openOnlinePanel" in html,
    "AuditLogPanel func" : "openAuditLogPanel" in html,
    "onlineBtn element"  : 'id="onlineBtn"' in html,
    "audit_log table"    : "audit_log" in html,
    "user_sessions table": "user_sessions" in html,
    "beforeunload"       : "beforeunload" in html and "_sbSessionEnd" in html,
    "Heartbeat interval" : "_heartbeatTimer" in html,
    "Audit hooks projects": "_sbAuditLog('create', 'projects'" in html
                           and "_sbAuditLog('update', 'projects'" in html
                           and "_sbAuditLog('delete', 'projects'" in html,
    "Audit hooks groups" : "_sbAuditLog('create', 'groups'" in html
                           and "_sbAuditLog('delete', 'groups'" in html,
    "Audit hooks staff"  : "_sbAuditLog('update', 'staff'" in html
                           and "_sbAuditLog('create', 'staff_leaves'" in html,
}

sec_done    = [k for k, v in security_checks.items() if v]
sec_missing = [k for k, v in security_checks.items() if not v]

check(
    "Security features (Online+Audit)",
    len(sec_missing) == 0,
    f"{len(sec_done)}/{len(security_checks)} checks OK" if not sec_missing
    else f"THIEU: {', '.join(sec_missing)}"
)
if sec_missing:
    for m in sec_missing:
        print(f"         >> Missing: {m}")

# ─────────────────────────────────────────────────────────────
# TEST 11 — Photo Storage Restructure
# ─────────────────────────────────────────────────────────────
photo_checks = {
    "getMonthForPj func"       : "function getMonthForPj" in html,
    "_sbCopyMonthPhotos func"  : "_sbCopyMonthPhotos" in html,
    "uploadPhoto new path"     : "getMonthForPj(pjId)" in html and "month_id: _upMid" in html,
    "delPhoto smart path"      : "_cached.startsWith(_BASE)" in html,
    "_pjIdMap capture"         : "_pjIdMap.push" in html and "prevId: p.id" in html,
    "copy slot_0 only"         : "slot_0.jpg" in html and "download(srcPath)" in html,
    "cleanup retention"        : "(nY - mY) * 12 + (nM - mM) <= PHOTO_RETENTION_MONTHS" in html and "const PHOTO_RETENTION_MONTHS" in html,
    "PHOTO_MIGRATION.sql"      : os.path.exists(os.path.join(SCRIPT_DIR, 'PHOTO_MIGRATION.sql')),
    "migrate_photos.js"        : os.path.exists(os.path.join(SCRIPT_DIR, 'migrate_photos.js')),
}

photo_done    = [k for k, v in photo_checks.items() if v]
photo_missing = [k for k, v in photo_checks.items() if not v]

check(
    "Photo Storage Restructure",
    len(photo_missing) == 0,
    f"{len(photo_done)}/{len(photo_checks)} checks OK" if not photo_missing
    else f"THIEU: {', '.join(photo_missing)}"
)
if photo_missing:
    for m in photo_missing:
        print(f"         >> Missing: {m}")

# ─────────────────────────────────────────────────────────────
# IN KET QUA
# ─────────────────────────────────────────────────────────────
print()
print("=" * 60)
print(f"  AUTO TEST - index.html ({total_lines:,} dong, {file_size/1024:.0f} KB)")
print(f"  {time.strftime('%Y-%m-%d %H:%M:%S')}")
print("=" * 60)

pass_count = sum(1 for s, _, _ in results if s == PASS)
fail_count = sum(1 for s, _, _ in results if s == FAIL)

for status, name, detail in results:
    icon = "OK" if status == PASS else ("~~" if status == "WARN" else "!!")
    pad  = max(0, 38 - len(name))
    print(f"  [{icon}] {name}{' ' * pad}{detail}")

print("-" * 60)
warn_count = sum(1 for s, _, _ in results if s == "WARN")
overall = PASS if fail_count == 0 else FAIL
print(f"  KET QUA: {overall}  ({pass_count} pass, {fail_count} fail, {warn_count} warn)")
print("=" * 60)

sys.exit(0 if fail_count == 0 else 1)
