
BEGIN;

CREATE TABLE IF NOT EXISTS admin_deleted_orders (
  id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  original_order_id integer NOT NULL,                                  -- id from shop_orders
  user_id integer NOT NULL,                                            -- the user who placed the order
  shop_item_id integer,                                                 -- referenced shop item (nullable if item removed)
  quantity integer NOT NULL DEFAULT 1,
  price_per_item integer NOT NULL,
  total_price integer NOT NULL,
  status varchar,                                                       -- original order status (pending, fulfilled, etc.)
  order_type varchar,                                                   -- purchase | luck_win | consolation | etc.
  shipping_address text,
  phone varchar,
  item_name varchar,                                                    -- snapshot of item name at time of order
  created_at timestamptz,                                               -- original order creation time
  deleted_by integer,                                                   -- admin user id who performed the deletion
  deleted_at timestamptz NOT NULL DEFAULT now(),                        -- tombstone timestamp
  reason text,                                                          -- optional short explanation provided by admin
  deleted_payload jsonb,                                                 -- optional raw row payload / metadata
  restored boolean NOT NULL DEFAULT false,                              -- whether this archived record was later restored
  restored_by integer,                                                   -- admin id who restored (if any)
  restored_at timestamptz,                                               -- when it was restored
  CONSTRAINT fk_admin_deleted_orders_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL,
  CONSTRAINT fk_admin_deleted_orders_shop_item FOREIGN KEY (shop_item_id) REFERENCES shop_items (id) ON DELETE SET NULL,
  CONSTRAINT fk_admin_deleted_orders_deleted_by FOREIGN KEY (deleted_by) REFERENCES users (id) ON DELETE SET NULL,
  CONSTRAINT fk_admin_deleted_orders_restored_by FOREIGN KEY (restored_by) REFERENCES users (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_admin_deleted_orders_deleted_at ON admin_deleted_orders (deleted_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_deleted_orders_user_id ON admin_deleted_orders (user_id);
CREATE INDEX IF NOT EXISTS idx_admin_deleted_orders_original_order_id ON admin_deleted_orders (original_order_id);

COMMIT;
