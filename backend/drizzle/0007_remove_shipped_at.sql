-- Remove shipped_at column from projects table
-- Ship dates are now derived from the project_activity table (project_shipped action)
DROP INDEX IF EXISTS idx_projects_shipped_at;
ALTER TABLE projects DROP COLUMN IF EXISTS shipped_at;
