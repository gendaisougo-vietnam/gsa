# MIGRATION PLAN: localStorage → Supabase

## Tổng quan kiến trúc hiện tại

```
index.html (single file, 7584 dòng)
│
├── D (global object)          ← toàn bộ state trong RAM
│   ├── D.settings             ← staffList, typeList, sync hashes...
│   ├── D.months[YYYY-MM]      ← projects[], projectsVN[], targets
│   │   └── projects[]         ← groups[] → rows[] (rate0-13, doneAt...)
│   └── (activeMonth)
│
├── localStorage               ← nơi persist D (JSON blob ~769 KB)
│   ├── SK ("phoicanh_data")   ← D object serialize
│   ├── sync_gh_token          ← GitHub token
│   ├── phoicanh_backup_*      ← auto-backup hàng ngày (7 bản)
│   └── ...10 keys khác
│
├── Auth (hiện tại)            ← hardcode 3 password → admin/edit/view
│   └── SPLASH_PW = {'204290':'admin','123456':'edit','280510':'view'}
│
├── Sync (hiện tại)            ← GitHub Gist, AES-GCM encrypt
│   ├── syncPush()             ← serialize D → encrypt → PUT Gist
│   └── syncPull()             ← GET Gist → decrypt → D = data
│
└── Render cycle
    └── renderAll() → đọc từ D → innerHTML (không async)
```

## Chiến lược migration: Hybrid → Full Supabase

Không rewrite một lần (quá rủi ro). Migration **9 phase**, mỗi phase
app vẫn chạy được độc lập. D vẫn là nguồn render — Supabase thay thế
dần localStorage và GitHub Gist.

```
Phase 0  Setup          — thêm SDK, không đổi logic
Phase 1  Auth           — login qua Supabase thay SPLASH_PW hardcode
Phase 2  Read (full)    — load D từ Supabase khi login
Phase 3  Write settings — save settings/months lên Supabase
Phase 4  Write projects — CRUD dự án qua Supabase
Phase 5  Write rows     — ghi row/group (hotpath, nhiều nhất)
Phase 6  Write staff    — profile, leave, late, trips
Phase 7  Realtime       — subscribe thay periodic pull
Phase 8  Photos         — base64 → Supabase Storage
Phase 9  Cleanup        — xóa GitHub Gist sync, xóa localStorage
```

---

## PHASE 0 — Setup SDK (½ ngày)

**Mục tiêu:** Thêm Supabase vào HTML, không thay đổi logic nào.

### Việc cần làm

**0.1** Thêm vào `<head>` của `index.html` (trước `<script>` chính):

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
<script>
  const SUPABASE_URL     = 'https://kefwrfxeneropihedght.supabase.co'
  const SUPABASE_ANON_KEY = 'sb_publishable__B9f2R2Y1JMsvQ2NkmTU9Q_T8f4McGZ'
  const _sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
</script>
```

**0.2** Kiểm tra console không có lỗi, app vẫn chạy bình thường.

### Không thay đổi gì khác.

---

## PHASE 1 — Auth (1 ngày)

**Mục tiêu:** Thay `SPLASH_PW` hardcode bằng Supabase custom auth
(vẫn dùng 3 password, nhưng hash lưu trong DB thay vì code).

### Vấn đề hiện tại

```js
// index.html:722 — password hardcode trong source code
const SPLASH_PW = {'204290':'admin','123456':'edit','280510':'view'}
```

Ai xem source HTML đều thấy password.

### Giải pháp

Tạo **Supabase Edge Function** `verify-password` nhận hash → trả role.
Hash passwords vẫn lưu trong bảng `settings.sync_config`.

### Các bước

**1.1** Thêm vào bảng `settings` (SQL Editor Supabase):

```sql
-- Lưu password hashes vào settings đã tạo
update settings set sync_config = jsonb_build_object(
  'adminHash', 'c9ac2173f7a9dfb94f1b4827f35d74f1b73a6f2299d61cb41645842ea24b9d1a',
  'editHash',  '8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92',
  'viewHash',  '813f7512db1c116c5d706c0fcf98a3b7fd14fcba7a89b08fd1727dd16de8d3e7'
);
```

**1.2** Thay thế hàm `_splashLogin` trong `index.html`:

```js
// THAY THẾ: const SPLASH_PW = {'204290':'admin',...}
// BẰNG:
async function _splashLogin() {
  const pw    = (document.getElementById('splashPwInput').value || '').trim()
  const errEl = document.getElementById('splashError')
  if (!pw) { errEl.textContent = 'Vui lòng nhập mật khẩu'; return }

  // Hash password (đã có hàm hashPw() trong app)
  const h = await hashPw(pw)

  // Kiểm tra local trước (fast path — D đã load)
  const sc = D.settings?.sync_config || D.settings?.sync || {}
  let role = null
  if (h === sc.adminHash) role = 'admin'
  else if (h === sc.editHash) role = 'edit'
  else if (h === sc.viewHash) role = 'view'

  // Fallback: query Supabase (thiết bị mới chưa có D)
  if (!role) {
    const { data } = await _sb.from('settings').select('sync_config').single()
    const cfg = data?.sync_config || {}
    if (h === cfg.adminHash) role = 'admin'
    else if (h === cfg.editHash) role = 'edit'
    else if (h === cfg.viewHash) role = 'view'
  }

  if (!role) {
    errEl.textContent = 'Mật khẩu không đúng'
    return
  }

  sessionStorage.setItem('splash_role', role)
  SYNC.role = role
  // ... phần còn lại giữ nguyên
}
```

**1.3** Lưu role vào `sessionStorage` — giữ nguyên như cũ.

### Test
- Đăng nhập đúng 3 password → đúng role
- Sai password → báo lỗi
- Không cần internet → dùng local hash trong D

---

## PHASE 2 — Read: Load D từ Supabase (2 ngày)

**Mục tiêu:** Khi login, fetch toàn bộ data từ Supabase thay vì
`JSON.parse(localStorage.getItem(SK))`.

### Luồng hiện tại

```
trang load → D = JSON.parse(localStorage) → renderAll()
```

### Luồng sau migration

```
trang load → show loading splash
  → login()
  → D = await sbLoadAll()   ← fetch 7 bảng song song
  → renderAll()
  → subscribe realtime (Phase 7)
```

### Hàm cần viết: `sbLoadAll()`

Thêm vào phần đầu script của `index.html` (sau Phase 0):

```js
async function sbLoadAll() {
  // Fetch song song để nhanh
  const [
    { data: settingsRows },
    { data: monthRows },
    { data: projectRows },
    { data: groupRows },
    { data: rowRows },
    { data: tlTaskRows },
    { data: staffRows },
    { data: leaveRows },
    { data: lateRows },
    { data: tripRows },
  ] = await Promise.all([
    _sb.from('settings').select('*').single(),
    _sb.from('months').select('*'),
    _sb.from('projects').select('*').order('sort_order'),
    _sb.from('groups').select('*').order('sort_order'),
    _sb.from('rows').select('*').order('sort_order'),
    _sb.from('tl_tasks').select('*').order('sort_order'),
    _sb.from('staff').select('*').order('sort_order'),
    _sb.from('staff_leaves').select('*'),
    _sb.from('staff_late_log').select('*'),
    _sb.from('business_trips').select('*'),
  ])

  // Reconstruct D object (format giống localStorage)
  const D = {
    activeMonth: settingsRows?.active_month || '',
    settings: {
      staffList:      settingsRows?.staff_list || [],
      typeList:       settingsRows?.type_list || [],
      typeListVN:     settingsRows?.type_list_vn || [],
      contactList:    settingsRows?.contact_list || [],
      contactListVN:  settingsRows?.contact_list_vn || [],
      holidays:       settingsRows?.holidays || [],
      sync:           settingsRows?.sync_config || {},
      staffProfiles:  {},
    },
    months: {},
  }

  // Build staffProfiles từ staff + leaves + lateLog + trips
  const staffById = {}
  for (const s of (staffRows || [])) {
    staffById[s.id] = s
    D.settings.staffProfiles[s.full_name] = {
      role: s.role, salaryGross: s.salary_gross, salaryNet: s.salary_net,
      contractEnd: s.contract_end || '', order: s.sort_order,
      leaves: [], lateLog: [], trips: [],
    }
  }
  for (const l of (leaveRows || [])) {
    const name = staffById[l.staff_id]?.full_name
    if (name && D.settings.staffProfiles[name])
      D.settings.staffProfiles[name].leaves.push({
        from: l.date_from, to: l.date_to, reason: l.reason, session: l.session
      })
  }
  for (const l of (lateRows || [])) {
    const name = staffById[l.staff_id]?.full_name
    if (name && D.settings.staffProfiles[name])
      D.settings.staffProfiles[name].lateLog.push({
        date: l.late_date, minutes: l.minutes, note: l.note
      })
  }
  for (const t of (tripRows || [])) {
    const name = staffById[t.staff_id]?.full_name
    if (name && D.settings.staffProfiles[name])
      D.settings.staffProfiles[name].trips.push({
        id: t.id, from: t.date_from, to: t.date_to, note: t.destination
      })
  }

  // Build months → projects → groups → rows
  const groupsByProject = {}
  for (const g of (groupRows || [])) {
    if (!groupsByProject[g.project_id]) groupsByProject[g.project_id] = []
    groupsByProject[g.project_id].push(g)
  }
  const rowsByGroup = {}
  for (const r of (rowRows || [])) {
    if (!rowsByGroup[r.group_id]) rowsByGroup[r.group_id] = []
    rowsByGroup[r.group_id].push(r)
  }
  const tlByProject = {}
  for (const t of (tlTaskRows || [])) {
    if (!tlByProject[t.project_id]) tlByProject[t.project_id] = []
    tlByProject[t.project_id].push(t)
  }

  for (const m of (monthRows || [])) {
    D.months[m.id] = { projects: [], projectsVN: [], targetNew: m.target_new, targetRev: m.target_rev }
  }
  for (const p of (projectRows || [])) {
    if (!D.months[p.month_id]) continue
    const groups = (groupsByProject[p.id] || []).map(g => ({
      id: g.id, type: g.type, tlTaskId: g.tl_task_id,
      rows: (rowsByGroup[g.id] || []).map(r => ({
        id: r.id, staff: r.staff, status: r.status, qty: r.qty,
        dateFrom: r.date_from || '', dateTo: r.date_to || '',
        upTime: r.up_time || '', doneAt: r.done_at || '',
        upScore: r.up_score, note: r.note, ot: r.ot, otNote: r.ot_note,
        rate0:r.rate0,rate1:r.rate1,rate2:r.rate2,rate3:r.rate3,
        rate4:r.rate4,rate5:r.rate5,rate6:r.rate6,rate7:r.rate7,
        rate8:r.rate8,rate9:r.rate9,rate10:r.rate10,
        rate11:r.rate11,rate12:r.rate12,rate13:r.rate13,
      }))
    }))
    const pObj = {
      id: p.id, nameVN: p.name_vn, nameJP: p.name_jp,
      office: p.office, contact: p.contact, mainStaff: p.main_staff,
      notes: p.notes, _carryover: p.is_carryover,
      groups, photos: [], otLog: [],
      tlTasks: (tlByProject[p.id] || []).map(t => ({
        id: t.id, lv: t.lv, name: t.name, start: t.start_date,
        end: t.end_date, upDate: t.up_date, actual: t.actual_date,
        content: t.content, progress: t.progress, status: t.status,
        dep: t.dep, staff: t.staff, note: t.note, parentGroup: t.parent_group
      }))
    }
    if (p.section === 'vn') D.months[p.month_id].projectsVN.push(pObj)
    else D.months[p.month_id].projects.push(pObj)
  }

  return D
}
```

**2.2** Sửa phần khởi động (`initSplash` → sau login thành công):

```js
// Trong _splashLogin(), thay vì chỉ gọi renderAll():
setSyncStatus('syncing', 'Đang tải dữ liệu…')
try {
  D = await sbLoadAll()
  // Vẫn cache vào localStorage để dùng offline
  try { localStorage.setItem(SK, JSON.stringify(D)) } catch(e) {}
} catch(e) {
  // Offline fallback: dùng localStorage cache
  console.warn('Supabase offline, dùng cache:', e.message)
}
setSyncStatus('synced', role === 'admin' ? '✓ Admin' : '✓ ' + role)
renderAll()
```

### Test
- Login → data load từ Supabase
- Tắt internet → fallback localStorage cache
- Data đúng với màn hình dashboard

---

## PHASE 3 — Write: Settings & Months (1 ngày)

**Mục tiêu:** Khi thay đổi settings hoặc target tháng, ghi lên Supabase.

### Các hàm cần sửa

**3.1** `saveSettings()` (dòng 6038):

```js
async function saveSettings() {
  // ... validate logic giữ nguyên ...

  // Ghi lên Supabase
  await _sb.from('settings').update({
    staff_list:      D.settings.staffList,
    type_list:       D.settings.typeList,
    type_list_vn:    D.settings.typeListVN,
    contact_list:    D.settings.contactList,
    contact_list_vn: D.settings.contactListVN,
    holidays:        D.settings.holidays,
  }).eq('id', window._settingsId)  // cache settings.id khi sbLoadAll()

  persistD()  // vẫn giữ localStorage sync
  toast('✓ Đã lưu')
}
```

**3.2** `updateMonthTarget(field, val)` (dòng 2050):

```js
async function updateMonthTarget(field, val) {
  const m = curMonth()
  m[field] = +val
  // Supabase
  const col = field === 'targetNew' ? 'target_new' : 'target_rev'
  await _sb.from('months').update({ [col]: +val }).eq('id', D.activeMonth)
  save()
  refreshHeroTargetDisplay()
}
```

**3.3** `addMonth()` → `doAddMonth()` (dòng 966):

```js
// Trong doAddMonth(), sau khi tạo D.months[newMid]:
await _sb.from('months').upsert({
  id: newMid, target_new: 0, target_rev: 0
})
```

---

## PHASE 4 — Write: Projects CRUD (1-2 ngày)

**Mục tiêu:** Các thao tác thêm/sửa/xóa dự án ghi thẳng lên Supabase.

### Hàm helper

Thêm vào đầu script:

```js
async function sbSaveProject(p, monthId, section) {
  await _sb.from('projects').upsert({
    id: p.id, month_id: monthId, section,
    name_vn: p.nameVN || '', name_jp: p.nameJP || '',
    office: p.office || '', contact: p.contact || '',
    main_staff: p.mainStaff || '', notes: p.notes || '',
    is_carryover: !!p._carryover,
  }, { onConflict: 'id' })
}
```

### Các hàm cần sửa

**4.1** `confirmAddPj()` (dòng 4134): thêm `await sbSaveProject(pj, D.activeMonth, activeSection)` trước `save()`.

**4.2** `confirmEditPj(id)` (dòng 4180): thêm `await sbSaveProject(p, D.activeMonth, activeSection)` trước `save()`.

**4.3** `deletePj(id)` (dòng 4435):

```js
async function deletePj(id) {
  if (!confirm('Xóa dự án này?')) return
  // Supabase (cascade xóa groups, rows, tl_tasks)
  await _sb.from('projects').delete().eq('id', id)
  // ... logic D object giữ nguyên ...
  save(); renderSidebar(); renderContent()
}
```

**4.4** `doAddMonth()` (dòng 1016): sau khi copy projects sang tháng mới,
upsert tất cả project mới lên Supabase.

---

## PHASE 5 — Write: Groups & Rows (2-3 ngày) ⚠ Hotpath

**Mục tiêu:** Ghi group/row lên Supabase. Đây là path viết nhiều nhất
(mỗi thay đổi ô input đều trigger `updRow()`).

### Chiến lược: Debounce + optimistic update

Không ghi Supabase sau mỗi keystroke. Dùng debounce 1.5s.

```js
const _sbRowDebounce = {}
async function sbSaveRow(groupId, rowId, data) {
  clearTimeout(_sbRowDebounce[rowId])
  _sbRowDebounce[rowId] = setTimeout(async () => {
    await _sb.from('rows').upsert({ id: rowId, group_id: groupId, ...data }, { onConflict: 'id' })
  }, 1500)
}
```

### Các hàm cần sửa

**5.1** `addGroup(pjId)` (dòng 3979):

```js
// Sau khi push vào p.groups:
const g = p.groups[p.groups.length - 1]
await _sb.from('groups').insert({ id: g.id, project_id: pjId, type: '', sort_order: p.groups.length - 1 })
// Row đầu tiên:
await _sb.from('rows').insert({ id: g.rows[0].id, group_id: g.id, status: 'new', qty: 0, ot: 0 })
```

**5.2** `addRow(pjId, gid)` (dòng 3986):

```js
const r = g.rows[g.rows.length - 1]
await _sb.from('rows').insert({ id: r.id, group_id: gid, status: 'new', qty: 0, ot: 0 })
```

**5.3** `updRow(pjId, gid, rid, field, val)` (dòng 4023):

```js
// Map field name JS → Supabase column
const COL_MAP = {
  staff:'staff', status:'status', qty:'qty',
  dateFrom:'date_from', dateTo:'date_to', upTime:'up_time',
  doneAt:'done_at', upScore:'up_score', note:'note',
  ot:'ot', otNote:'ot_note',
  rate0:'rate0', /* ... rate1-13 */
}
const col = COL_MAP[field]
if (col) sbSaveRow(gid, rid, { [col]: val })  // debounced
```

**5.4** `markRowDone(pjId, gid, rid)` (dòng 3499): KHÔNG debounce — ghi ngay:

```js
await _sb.from('rows').update({
  done_at: r.doneAt, up_score: r.upScore
}).eq('id', rid)
```

**5.5** `delGroup(pjId, gid)` / `delRow(pjId, gid, rid)`:

```js
await _sb.from('groups').delete().eq('id', gid)  // cascade xóa rows
await _sb.from('rows').delete().eq('id', rid)
```

**5.6** `updGroup(pjId, gid, field, val)`:

```js
await _sb.from('groups').update({ type: val }).eq('id', gid)
```

---

## PHASE 6 — Write: Staff (1 ngày)

**Mục tiêu:** Ghi thay đổi nhân viên lên Supabase.

Cần cache `staffIdByName` map (name → uuid) sau `sbLoadAll()`.

### Các hàm cần sửa

| Hàm hiện tại | Supabase action |
|---|---|
| `saveStaffProfile(name, field, val)` | `update staff set {col} = val where full_name = name` |
| `addLateRecord(name, date, min, note)` | `upsert staff_late_log on conflict (staff_id, late_date)` |
| `deleteLateRecord(name, date)` | `delete from staff_late_log` |
| `confirmAddLeave(name)` | `insert into staff_leaves` |
| `delLeave(staffName, leaveId)` | `delete from staff_leaves where id = leaveId` |
| `addTrip(name)` | `insert into business_trips` |
| `deleteTrip(name, id)` | `delete from business_trips where id = id` |

---

## PHASE 7 — Realtime Subscriptions (1 ngày)

**Mục tiêu:** Thay `startPeriodicPull()` (poll mỗi 3 phút) bằng
Supabase Realtime — nhận thay đổi tức thì.

### Thay thế `startPeriodicPull()`

```js
function startRealtimeSync() {
  if (startRealtimeSync._channel) return  // already subscribed

  startRealtimeSync._channel = _sb
    .channel('db-changes')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'rows' },
      payload => {
        // Merge thay đổi vào D và re-render nhẹ
        applyRowChange(payload)
      })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'projects' },
      payload => { renderSidebar() })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'months' },
      payload => { renderMonthStrip() })
    .subscribe()
}

function applyRowChange(payload) {
  const { eventType, new: newRow, old: oldRow } = payload
  // Tìm row trong D và update tại chỗ
  for (const m of Object.values(D.months)) {
    for (const p of [...(m.projects||[]), ...(m.projectsVN||[])]) {
      for (const g of (p.groups||[])) {
        const idx = g.rows.findIndex(r => r.id === (newRow?.id || oldRow?.id))
        if (idx === -1) continue
        if (eventType === 'DELETE') g.rows.splice(idx, 1)
        else g.rows[idx] = { ...g.rows[idx], ...mapSupabaseRow(newRow) }
        renderContent()
        return
      }
    }
  }
}
```

**Lưu ý:** Cần bật Replication cho các bảng trong Supabase Dashboard
→ Database → Replication → chọn `rows`, `projects`, `months`.

---

## PHASE 8 — Photos: base64 → Supabase Storage (1-2 ngày)

**Mục tiêu:** Không lưu base64 trong D (chiếm ~70% localStorage).

### Sửa `uploadPhoto(pjId, slot, input)` (dòng 2938)

```js
async function uploadPhoto(pjId, slot, input) {
  const file = input.files[0]; if (!file) return
  const path = `projects/${pjId}/slot_${slot}.jpg`
  const { error } = await _sb.storage.from('project-photos').upload(path, file, { upsert: true })
  if (error) { toast('Lỗi upload ảnh: ' + error.message); return }

  // Lưu path vào DB
  await _sb.from('project_photos').upsert({ project_id: pjId, slot, storage_path: path })

  // Lấy public URL để hiển thị
  const { data } = _sb.storage.from('project-photos').getPublicUrl(path)
  const p = getPj(pjId); if (!p) return
  if (!p.photos) p.photos = []
  p.photos[slot] = data.publicUrl
  save(); renderProjectDetail(/* ... */)
  toast('✓ Đã upload ảnh')
}
```

### Sửa `delPhoto(pjId, slot)` (dòng 2967)

```js
async function delPhoto(pjId, slot) {
  const path = `projects/${pjId}/slot_${slot}.jpg`
  await _sb.storage.from('project-photos').remove([path])
  await _sb.from('project_photos').delete().eq('project_id', pjId).eq('slot', slot)
  // ... xóa khỏi D.photos giữ nguyên ...
}
```

---

## PHASE 9 — Cleanup (1 ngày)

**Mục tiêu:** Xóa code cũ không còn dùng.

### Xóa hoàn toàn

- Toàn bộ hàm `syncPush()`, `syncPull()`, `buildSyncPayload()` (GitHub Gist sync)
- `deriveKey()`, `encryptData()`, `decryptData()` (AES-GCM — không cần nữa)
- `injectSyncPasswords()` IIFE (passwords hardcode)
- `testGistConnection()`, `confirmSyncSetup()`, `showSyncSetup()`
- `startPeriodicPull()` (thay bằng Realtime)
- `triggerAutoSync()` (thay bằng Supabase write trực tiếp)
- Các localStorage keys: `sync_gist_id`, `sync_gh_token`, `sync_last_push`...

### Giữ lại (vẫn cần)

- `persistD()` / `save()` → localStorage làm **offline cache**
- `exportBackup()` / `importBackup()` → backup thủ công vẫn hữu ích
- `hashPw()` → dùng cho Phase 1 auth

### Sửa `renderStorageMeter()` (dòng 6990)

Hiển thị Supabase usage thay vì localStorage 5MB limit.

---

## Tóm tắt timeline

| Phase | Mô tả | Độ khó | Thời gian | Phụ thuộc |
|-------|--------|--------|-----------|-----------|
| **0** | Setup SDK | Dễ | ½ ngày | — |
| **1** | Auth login | Dễ | 1 ngày | Phase 0 |
| **2** | Read data | Trung bình | 2 ngày | Phase 1 |
| **3** | Write settings/months | Dễ | 1 ngày | Phase 2 |
| **4** | Write projects CRUD | Trung bình | 1-2 ngày | Phase 2 |
| **5** | Write groups/rows | Khó | 2-3 ngày | Phase 4 |
| **6** | Write staff | Trung bình | 1 ngày | Phase 2 |
| **7** | Realtime | Trung bình | 1 ngày | Phase 5-6 |
| **8** | Photos Storage | Trung bình | 1-2 ngày | Phase 4 |
| **9** | Cleanup | Dễ | 1 ngày | Phase 7-8 |
| | **Tổng** | | **~12-14 ngày** | |

## Nguyên tắc xuyên suốt

1. **D vẫn là nguồn render** — Supabase chỉ là persistence layer, không render trực tiếp
2. **Optimistic update** — cập nhật D trước, ghi Supabase sau (UI không bị chậm)
3. **localStorage làm offline cache** — giữ đến Phase 9
4. **Không rewrite HTML** — chỉ sửa JS functions, UI giữ nguyên
5. **Mỗi phase app vẫn chạy được** — test từng phase trước khi sang phase tiếp theo
