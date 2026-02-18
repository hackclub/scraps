CREATE TABLE "lootbox_hearts" (
	"id" integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY (sequence name "lootbox_hearts_id_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START WITH 1 CACHE 1),
	"user_id" integer NOT NULL,
	"lootbox_id" integer NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "lootbox_hearts_user_id_lootbox_id_unique" UNIQUE("user_id","lootbox_id")
);
--> statement-breakpoint
CREATE TABLE "lootbox_items" (
	"id" integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY (sequence name "lootbox_items_id_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START WITH 1 CACHE 1),
	"lootbox_id" integer NOT NULL,
	"shop_item_id" integer NOT NULL,
	"percentage" integer NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "lootbox_rolls" (
	"id" integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY (sequence name "lootbox_rolls_id_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START WITH 1 CACHE 1),
	"user_id" integer NOT NULL,
	"lootbox_id" integer NOT NULL,
	"won_shop_item_id" integer NOT NULL,
	"boosted_shop_item_id" integer NOT NULL,
	"rolled" integer NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "lootboxes" (
	"id" integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY (sequence name "lootboxes_id_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START WITH 1 CACHE 1),
	"name" varchar NOT NULL,
	"image" varchar NOT NULL,
	"description" varchar NOT NULL,
	"price" integer NOT NULL,
	"category" varchar NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "lootbox_hearts" ADD CONSTRAINT "lootbox_hearts_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lootbox_hearts" ADD CONSTRAINT "lootbox_hearts_lootbox_id_lootboxes_id_fk" FOREIGN KEY ("lootbox_id") REFERENCES "public"."lootboxes"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lootbox_items" ADD CONSTRAINT "lootbox_items_lootbox_id_lootboxes_id_fk" FOREIGN KEY ("lootbox_id") REFERENCES "public"."lootboxes"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lootbox_items" ADD CONSTRAINT "lootbox_items_shop_item_id_shop_items_id_fk" FOREIGN KEY ("shop_item_id") REFERENCES "public"."shop_items"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lootbox_rolls" ADD CONSTRAINT "lootbox_rolls_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lootbox_rolls" ADD CONSTRAINT "lootbox_rolls_lootbox_id_lootboxes_id_fk" FOREIGN KEY ("lootbox_id") REFERENCES "public"."lootboxes"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lootbox_rolls" ADD CONSTRAINT "lootbox_rolls_won_shop_item_id_shop_items_id_fk" FOREIGN KEY ("won_shop_item_id") REFERENCES "public"."shop_items"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "lootbox_rolls" ADD CONSTRAINT "lootbox_rolls_boosted_shop_item_id_shop_items_id_fk" FOREIGN KEY ("boosted_shop_item_id") REFERENCES "public"."shop_items"("id") ON DELETE no action ON UPDATE no action;