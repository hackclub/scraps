
BEGIN;

ALTER TABLE "shop_items"
  ADD COLUMN IF NOT EXISTS "upgrade_budget_multiplier" real NOT NULL DEFAULT 3.0;

COMMENT ON COLUMN "shop_items"."upgrade_budget_multiplier" IS
  'Per-item multiplier applied to item price when deriving the total upgrade budget (default: 3.0)';

COMMIT;
