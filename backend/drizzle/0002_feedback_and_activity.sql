ALTER TABLE "projects" ADD COLUMN "feedback_source" text;--> statement-breakpoint
ALTER TABLE "projects" ADD COLUMN "feedback_good" text;--> statement-breakpoint
ALTER TABLE "projects" ADD COLUMN "feedback_improve" text;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "language" varchar NOT NULL DEFAULT 'en';--> statement-breakpoint
ALTER TABLE "activity" RENAME TO "project_activity";--> statement-breakpoint
DROP TABLE IF EXISTS "user_emails";--> statement-breakpoint
CREATE TABLE "user_activity" (
	"id" serial PRIMARY KEY,
	"user_id" integer,
	"email" varchar,
	"action" varchar NOT NULL,
	"metadata" text,
	"created_at" timestamp DEFAULT now() NOT NULL
);--> statement-breakpoint
ALTER TABLE "user_activity" ADD CONSTRAINT "user_activity_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;
