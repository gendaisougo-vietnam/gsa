-- =============================================================
-- SUPABASE SCHEMA — Phoicanh Project Management App
-- Derived from localStorage D object structure in index.html
-- =============================================================
-- Run order: extensions → tables → indexes → RLS → functions
-- =============================================================

-- ── Extensions ───────────────────────────────────────────────
create extension if not exists "uuid-ossp";


-- =============================================================
-- SETTINGS
-- Global app config: staffList, typeList, contactList, sync…
-- Stored as a single row (singleton pattern)
-- =============================================================
create table settings (
  id              uuid primary key default uuid_generate_v4(),
  staff_list      text[]    not null default '{}',        -- D.settings.staffList
  type_list       text[]    not null default '{}',        -- D.settings.typeList  (JP)
  type_list_vn    text[]    not null default '{}',        -- D.settings.typeListVN
  contact_list    text[]    not null default '{}',        -- D.settings.contactList (JP)
  contact_list_vn text[]    not null default '{}',        -- D.settings.contactListVN
  holidays        jsonb     not null default '[]',        -- [{date, name}]
  sync_config     jsonb     not null default '{}',        -- gistId, binId, hashes (no plaintext passwords)
  active_month    char(7)   not null default to_char(now(), 'YYYY-MM'),  -- D.activeMonth
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Enforce singleton
create unique index settings_singleton on settings ((true));


-- =============================================================
-- MONTHS
-- Each row = one calendar month (YYYY-MM)
-- =============================================================
create table months (
  id          char(7)   primary key,    -- 'YYYY-MM', e.g. '2025-04'
  target_new  int       not null default 0,   -- D.months[mid].targetNew
  target_rev  int       not null default 0,   -- D.months[mid].targetRev
  created_at  timestamptz not null default now()
);


-- =============================================================
-- PROJECTS
-- Both JP (projects[]) and VN (projectsVN[]) in one table,
-- differentiated by section column
-- =============================================================
create table projects (
  id          text        primary key,          -- original app ID (gid())
  month_id    char(7)     not null references months(id) on delete cascade,
  section     text        not null check (section in ('jp', 'vn')),
  name_vn     text        not null default '',
  name_jp     text        not null default '',
  office      text        not null default ''   -- 大阪 / 東京 / ハノイ / HCM
                          check (office in ('大阪', '東京', 'ハノイ', 'HCM', '')),
  contact     text        not null default '',  -- JP contact person
  main_staff  text        not null default '',  -- primary staff name
  notes       text        not null default '',
  is_carryover boolean    not null default false, -- _carryover flag
  sort_order  int         not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);


-- =============================================================
-- PROJECT PHOTOS
-- photos[] is base64 in localStorage; in Supabase use Storage
-- This table holds references (storage paths or public URLs)
-- =============================================================
create table project_photos (
  id          uuid    primary key default uuid_generate_v4(),
  project_id  text    not null references projects(id) on delete cascade,
  slot        int     not null default 0,   -- original array index (0-based)
  storage_path text   not null,             -- Supabase Storage object path
  created_at  timestamptz not null default now(),
  unique (project_id, slot)
);


-- =============================================================
-- OT LOG  (p.otLog)
-- Per-project overtime entries (legacy format, pre-groups era)
-- =============================================================
create table ot_log (
  id          uuid    primary key default uuid_generate_v4(),
  project_id  text    not null references projects(id) on delete cascade,
  staff       text    not null,
  hours       numeric(5,2) not null default 0,
  log_date    date,
  note        text    not null default '',
  created_at  timestamptz not null default now()
);


-- =============================================================
-- GROUPS  (p.groups[])
-- "Hạng mục" — work category within a project
-- =============================================================
create table groups (
  id          text    primary key,          -- original app gid()
  project_id  text    not null references projects(id) on delete cascade,
  type        text    not null default '',  -- パース type (外観パース, etc.)
  tl_task_id  text,                         -- linked timeline task id
  sort_order  int     not null default 0,
  created_at  timestamptz not null default now()
);


-- =============================================================
-- ROWS  (g.rows[])
-- Individual work assignment lines within a group
-- =============================================================
create table rows (
  id          text    primary key,          -- original app gid()
  group_id    text    not null references groups(id) on delete cascade,
  staff       text    not null default '',
  status      text    not null default 'new' check (status in ('new', 'rev')),
  qty         int     not null default 0,
  date_from   date,                         -- dateFrom
  date_to     date,                         -- dateTo (deadline / UP date)
  up_time     time,                         -- specific UP time if any
  done_at     timestamptz,                  -- when marked done
  up_score    numeric(4,2),                 -- calcUpScore() result
  note        text    not null default '',
  ot          numeric(5,2) not null default 0,   -- overtime hours
  ot_note     text    not null default '',
  -- Rating fields (scale 0-10, both JP and VN sections)
  -- JP:  rate0-5 = Group A (技術, 40%), rate6-9 = Group B (30%), rate10-13 = Group C (30%)
  -- VN:  rate0-6 = Group A (45%),       rate7-10 = Group B (30%), rate11-13 = Group C (25%)
  rate0       numeric(4,2),
  rate1       numeric(4,2),
  rate2       numeric(4,2),
  rate3       numeric(4,2),
  rate4       numeric(4,2),
  rate5       numeric(4,2),
  rate6       numeric(4,2),
  rate7       numeric(4,2),
  rate8       numeric(4,2),
  rate9       numeric(4,2),
  rate10      numeric(4,2),
  rate11      numeric(4,2),
  rate12      numeric(4,2),
  rate13      numeric(4,2),
  sort_order  int     not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);


-- =============================================================
-- TIMELINE TASKS  (p.tlTasks[])
-- Gantt-style tasks for VN projects (renderProjectTimeline_VN)
-- =============================================================
create table tl_tasks (
  id          text    primary key,
  project_id  text    not null references projects(id) on delete cascade,
  parent_group text,                        -- parent task id (if child)
  lv          text    not null default 'task' check (lv in ('group', 'task')),
  name        text    not null default '',
  start_date  date,
  end_date    date,
  up_date     date,                         -- upload/delivery date
  actual_date date,                         -- actual completion date
  content     text    not null default '',
  progress    int     not null default 0 check (progress between 0 and 100),
  status      text    not null default '',  -- e.g. 'done', 'in_progress', ''
  dep         text    not null default '',  -- dependency task id
  staff       text[]  not null default '{}',
  note        text    not null default '',
  sort_order  int     not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);


-- =============================================================
-- STAFF
-- Master list + profile (D.settings.staffList + staffProfiles)
-- =============================================================
create table staff (
  id            uuid    primary key default uuid_generate_v4(),
  full_name     text    not null unique,    -- e.g. 'SGN ヒエン'
  short_name    text    not null default '', -- derived: ヒエン
  office        text    not null default '', -- SGN / HAN / Management / HCM
  role          text    not null default '',
  salary_gross  numeric(12,0) not null default 0,
  salary_net    numeric(12,0) not null default 0,
  contract_end  date,                       -- prof.contractEnd
  sort_order    int     not null default 99,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);


-- =============================================================
-- STAFF LEAVES  (prof.leaves[])
-- Approved leave periods per staff member
-- =============================================================
create table staff_leaves (
  id          uuid    primary key default uuid_generate_v4(),
  staff_id    uuid    not null references staff(id) on delete cascade,
  date_from   date    not null,
  date_to     date,                         -- null = single day (same as date_from)
  session     text    not null default 'all'
              check (session in ('all', 'morning', 'afternoon')),
  reason      text    not null default '',
  created_at  timestamptz not null default now()
);


-- =============================================================
-- STAFF LATE LOG  (prof.lateLog[])
-- Record of late arrivals per staff member
-- =============================================================
create table staff_late_log (
  id          uuid    primary key default uuid_generate_v4(),
  staff_id    uuid    not null references staff(id) on delete cascade,
  late_date   date    not null,
  minutes     int     not null default 0,
  note        text    not null default '',
  created_at  timestamptz not null default now(),
  unique (staff_id, late_date)               -- one record per staff per day
);


-- =============================================================
-- BUSINESS TRIPS  (prof.businessTrips[])
-- Staff travel / công tác records
-- =============================================================
create table business_trips (
  id          uuid    primary key default uuid_generate_v4(),
  staff_id    uuid    not null references staff(id) on delete cascade,
  date_from   date    not null,
  date_to     date,
  destination text    not null default '',
  note        text    not null default '',
  created_at  timestamptz not null default now()
);


-- =============================================================
-- INDEXES
-- =============================================================

-- projects
create index idx_projects_month   on projects(month_id);
create index idx_projects_section on projects(month_id, section);

-- groups
create index idx_groups_project   on groups(project_id);

-- rows
create index idx_rows_group       on rows(group_id);
create index idx_rows_staff       on rows(staff);
create index idx_rows_date_to     on rows(date_to);
create index idx_rows_done_at     on rows(done_at);

-- timeline tasks
create index idx_tl_tasks_project on tl_tasks(project_id);

-- ot_log
create index idx_ot_log_project   on ot_log(project_id);
create index idx_ot_log_staff     on ot_log(staff);

-- staff leaves / late
create index idx_leaves_staff     on staff_leaves(staff_id);
create index idx_late_staff       on staff_late_log(staff_id, late_date);
create index idx_trips_staff      on business_trips(staff_id);


-- =============================================================
-- UPDATED_AT TRIGGER
-- =============================================================
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_settings_updated  before update on settings  for each row execute function set_updated_at();
create trigger trg_projects_updated  before update on projects  for each row execute function set_updated_at();
create trigger trg_rows_updated      before update on rows      for each row execute function set_updated_at();
create trigger trg_tl_tasks_updated  before update on tl_tasks  for each row execute function set_updated_at();
create trigger trg_staff_updated     before update on staff     for each row execute function set_updated_at();


-- =============================================================
-- ROW LEVEL SECURITY
-- =============================================================
alter table settings       enable row level security;
alter table months         enable row level security;
alter table projects       enable row level security;
alter table project_photos enable row level security;
alter table ot_log         enable row level security;
alter table groups         enable row level security;
alter table rows           enable row level security;
alter table tl_tasks       enable row level security;
alter table staff          enable row level security;
alter table staff_leaves   enable row level security;
alter table staff_late_log enable row level security;
alter table business_trips enable row level security;

-- Service-role bypass (used by server-side sync functions)
-- Anon / authenticated users get read access; writes require service role or custom claim

-- Example: authenticated users can read everything
create policy "read_all_authenticated" on settings       for select to authenticated using (true);
create policy "read_all_authenticated" on months         for select to authenticated using (true);
create policy "read_all_authenticated" on projects       for select to authenticated using (true);
create policy "read_all_authenticated" on project_photos for select to authenticated using (true);
create policy "read_all_authenticated" on ot_log         for select to authenticated using (true);
create policy "read_all_authenticated" on groups         for select to authenticated using (true);
create policy "read_all_authenticated" on rows           for select to authenticated using (true);
create policy "read_all_authenticated" on tl_tasks       for select to authenticated using (true);
create policy "read_all_authenticated" on staff          for select to authenticated using (true);
create policy "read_all_authenticated" on staff_leaves   for select to authenticated using (true);
create policy "read_all_authenticated" on staff_late_log for select to authenticated using (true);
create policy "read_all_authenticated" on business_trips for select to authenticated using (true);

-- Writes: only service_role (sync from app) or add your own role check here
-- e.g.: using (auth.jwt() ->> 'app_role' in ('admin', 'edit'))


-- =============================================================
-- HELPER VIEWS
-- =============================================================

-- Monthly KPI summary per staff
create or replace view v_staff_monthly_kpi as
select
  r.staff,
  p.month_id,
  p.section,
  count(r.id)                                        as row_count,
  sum(case when r.status = 'new' then r.qty else 0 end) as qty_new,
  sum(case when r.status = 'rev' then r.qty else 0 end) as qty_rev,
  sum(r.ot)                                          as ot_hours,
  count(r.done_at) filter (where r.date_to is not null)  as done_count,
  count(r.id)      filter (where r.date_to is not null)  as total_scheduled,
  -- on-time rate: done_at date <= date_to
  round(
    count(r.id) filter (
      where r.done_at is not null
        and r.date_to is not null
        and r.done_at::date <= r.date_to
    )::numeric
    / nullif(count(r.id) filter (where r.date_to is not null and r.done_at is not null), 0)
  , 2)                                               as on_time_rate,
  -- average ratings across all fields
  round(avg(
    (coalesce(r.rate0,0) + coalesce(r.rate1,0) + coalesce(r.rate2,0) +
     coalesce(r.rate3,0) + coalesce(r.rate4,0) + coalesce(r.rate5,0) +
     coalesce(r.rate6,0) + coalesce(r.rate7,0) + coalesce(r.rate8,0)) / 9.0
  ) filter (where r.rate0 is not null), 2)           as avg_rating
from rows r
join groups g on g.id = r.group_id
join projects p on p.id = g.project_id
where r.staff <> ''
group by r.staff, p.month_id, p.section;


-- Upcoming deadlines (next 7 days)
create or replace view v_upcoming_deadlines as
select
  r.id        as row_id,
  r.staff,
  r.date_to,
  r.up_time,
  r.qty,
  r.status,
  r.done_at,
  g.type      as group_type,
  p.name_vn,
  p.name_jp,
  p.month_id,
  p.section
from rows r
join groups g  on g.id = r.group_id
join projects p on p.id = g.project_id
where r.date_to between current_date and current_date + 7
  and r.done_at is null
order by r.date_to, r.up_time;


-- Project totals (denormalized for sidebar display)
create or replace view v_project_totals as
select
  p.id,
  p.month_id,
  p.section,
  p.name_vn,
  p.name_jp,
  p.office,
  p.main_staff,
  sum(case when r.status = 'new' then r.qty else 0 end) as total_new,
  sum(case when r.status = 'rev' then r.qty else 0 end) as total_rev,
  sum(r.ot)                                              as total_ot,
  count(r.id) filter (where r.date_to is not null and r.done_at is null) as pending_ups,
  max(r.date_to) filter (where r.done_at is null)        as next_deadline
from projects p
left join groups g  on g.project_id = p.id
left join rows r    on r.group_id = g.id
group by p.id, p.month_id, p.section, p.name_vn, p.name_jp, p.office, p.main_staff;
