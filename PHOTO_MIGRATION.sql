-- PHOTO_MIGRATION.sql
-- Thêm cột month_id vào bảng project_photos
-- Chạy trong Supabase SQL Editor

ALTER TABLE public.project_photos
  ADD COLUMN IF NOT EXISTS month_id text DEFAULT '';

-- Backfill month_id từ bảng projects
UPDATE public.project_photos pp
SET month_id = p.month_id
FROM public.projects p
WHERE pp.project_id = p.id
  AND (pp.month_id IS NULL OR pp.month_id = '');

-- Indexes
CREATE INDEX IF NOT EXISTS idx_project_photos_month_id
  ON public.project_photos (month_id);

CREATE INDEX IF NOT EXISTS idx_project_photos_project_month
  ON public.project_photos (project_id, month_id);
