ALTER TABLE "projects" DROP COLUMN IF EXISTS "is_update";--> statement-breakpoint
ALTER TABLE "projects" ADD COLUMN "ai_description" text;
