-- Add shipped_at timestamp to track when projects were shipped
ALTER TABLE projects ADD COLUMN shipped_at timestamp;

-- Backfill shipped_at for existing shipped projects using updatedAt as approximation
UPDATE projects
SET shipped_at = updated_at
WHERE status = 'shipped' AND shipped_at IS NULL;

-- Create index for efficient ordering queries
CREATE INDEX idx_projects_shipped_at ON projects(shipped_at) WHERE shipped_at IS NOT NULL;
