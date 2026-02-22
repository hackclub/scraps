
BEGIN;

ALTER TABLE "shop_items"
  ADD COLUMN IF NOT EXISTS "per_roll_multiplier" real NOT NULL DEFAULT 0.05;

COMMENT ON COLUMN "shop_items"."per_roll_multiplier" IS
  'Per-item multiplier applied to base roll cost per previous roll (decimal, e.g. 0.05 = +5% per previous roll)';

COMMIT;
