-- Add scraps_paid_at column to projects table
ALTER TABLE "projects" ADD COLUMN "scraps_paid_at" timestamp;

-- Mark all existing shipped projects with scraps as already paid out
-- so they are not affected by the new weekly payout system
UPDATE "projects" SET "scraps_paid_at" = "updated_at" WHERE "status" = 'shipped' AND "scraps_awarded" > 0;
