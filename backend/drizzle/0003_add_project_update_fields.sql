ALTER TABLE "projects" ADD COLUMN "is_update" integer DEFAULT 0;--> statement-breakpoint
ALTER TABLE "projects" ADD COLUMN "update_description" text;
