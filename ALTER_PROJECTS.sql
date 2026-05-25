ALTER TABLE projects ADD COLUMN IF NOT EXISTS client text;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS building_type text;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS scope text;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS area text;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS construction_start date;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS construction_end date;
