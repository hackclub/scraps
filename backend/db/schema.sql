-- Scraps database schema (reverse-engineered from Rails controllers)
-- Run against a fresh postgres database:
--   psql postgresql://postgres:postgres@127.0.0.1:5432/app_development < db/schema.sql

-- Required by ActiveRecord even without migrations
CREATE TABLE IF NOT EXISTS schema_migrations (version VARCHAR(255) PRIMARY KEY);
CREATE TABLE IF NOT EXISTS ar_internal_metadata (key VARCHAR(255) PRIMARY KEY, value TEXT, created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL);

CREATE TABLE users (
  id               SERIAL PRIMARY KEY,
  sub              TEXT UNIQUE NOT NULL,
  slack_id         TEXT,
  username         TEXT,
  email            TEXT NOT NULL DEFAULT '',
  avatar           TEXT,
  phone            TEXT,
  access_token     TEXT,
  refresh_token    TEXT,
  id_token         TEXT,
  verification_status TEXT,
  role             TEXT NOT NULL DEFAULT 'member',
  tutorial_completed BOOLEAN NOT NULL DEFAULT FALSE,
  language         TEXT DEFAULT 'en',
  internal_notes   TEXT,
  created_at       TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE sessions (
  token      TEXT PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id),
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE projects (
  id                 SERIAL PRIMARY KEY,
  user_id            INTEGER NOT NULL REFERENCES users(id),
  name               TEXT NOT NULL DEFAULT '',
  description        TEXT,
  image              TEXT,
  github_url         TEXT,
  playable_url       TEXT,
  hackatime_project  TEXT,
  hours              FLOAT NOT NULL DEFAULT 0,
  hours_override     FLOAT,
  tier               INTEGER NOT NULL DEFAULT 1,
  tier_override      INTEGER,
  status             TEXT NOT NULL DEFAULT 'in_progress',
  scraps_awarded     INTEGER NOT NULL DEFAULT 0,
  scraps_paid_at     TIMESTAMP,
  scraps_paid_amount INTEGER NOT NULL DEFAULT 0,
  views              INTEGER NOT NULL DEFAULT 0,
  deleted            INTEGER NOT NULL DEFAULT 0,
  airtable_id        TEXT,
  update_description TEXT,
  ai_description     TEXT,
  reviewer_notes     TEXT,
  feedback_source    TEXT,
  feedback_good      TEXT,
  feedback_improve   TEXT,
  created_at         TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE project_activity (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER REFERENCES users(id),
  project_id INTEGER REFERENCES projects(id),
  action     TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE reviews (
  id                   SERIAL PRIMARY KEY,
  project_id           INTEGER NOT NULL REFERENCES projects(id),
  reviewer_id          INTEGER NOT NULL REFERENCES users(id),
  action               TEXT NOT NULL,
  feedback_for_author  TEXT,
  internal_justification TEXT,
  created_at           TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE user_bonuses (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id),
  amount     INTEGER NOT NULL,
  reason     TEXT NOT NULL,
  given_by   INTEGER REFERENCES users(id),
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE user_activity (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER REFERENCES users(id),
  email      TEXT,
  action     TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE news (
  id         SERIAL PRIMARY KEY,
  title      TEXT NOT NULL,
  content    TEXT NOT NULL,
  active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE shop_items (
  id                      SERIAL PRIMARY KEY,
  name                    TEXT NOT NULL,
  image                   TEXT NOT NULL DEFAULT '',
  description             TEXT NOT NULL DEFAULT '',
  price                   INTEGER NOT NULL DEFAULT 0,
  category                TEXT NOT NULL DEFAULT '',
  count                   INTEGER NOT NULL DEFAULT 0,
  base_probability        FLOAT NOT NULL DEFAULT 50,
  base_upgrade_cost       INTEGER,
  cost_multiplier         FLOAT,
  boost_amount            FLOAT NOT NULL DEFAULT 5,
  roll_cost_override      INTEGER,
  per_roll_multiplier     FLOAT NOT NULL DEFAULT 0.05,
  upgrade_budget_multiplier FLOAT NOT NULL DEFAULT 3.0,
  created_at              TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE shop_hearts (
  id           SERIAL PRIMARY KEY,
  user_id      INTEGER NOT NULL REFERENCES users(id),
  shop_item_id INTEGER NOT NULL REFERENCES shop_items(id),
  created_at   TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, shop_item_id)
);

CREATE TABLE shop_orders (
  id             SERIAL PRIMARY KEY,
  user_id        INTEGER NOT NULL REFERENCES users(id),
  shop_item_id   INTEGER NOT NULL REFERENCES shop_items(id),
  quantity       INTEGER NOT NULL DEFAULT 1,
  price_per_item INTEGER NOT NULL DEFAULT 0,
  total_price    INTEGER NOT NULL DEFAULT 0,
  shipping_address TEXT,
  phone          TEXT,
  status         TEXT NOT NULL DEFAULT 'pending',
  order_type     TEXT NOT NULL,
  notes          TEXT,
  tracking_number TEXT,
  is_fulfilled   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at     TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE shop_rolls (
  id           SERIAL PRIMARY KEY,
  user_id      INTEGER NOT NULL REFERENCES users(id),
  shop_item_id INTEGER NOT NULL REFERENCES shop_items(id),
  rolled       INTEGER NOT NULL,
  threshold    INTEGER NOT NULL,
  won          BOOLEAN NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE shop_penalties (
  id                    SERIAL PRIMARY KEY,
  user_id               INTEGER NOT NULL REFERENCES users(id),
  shop_item_id          INTEGER NOT NULL REFERENCES shop_items(id),
  probability_multiplier FLOAT NOT NULL DEFAULT 100,
  created_at            TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE refinery_orders (
  id           SERIAL PRIMARY KEY,
  user_id      INTEGER NOT NULL REFERENCES users(id),
  shop_item_id INTEGER NOT NULL REFERENCES shop_items(id),
  cost         INTEGER NOT NULL,
  boost_amount FLOAT NOT NULL,
  created_at   TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE refinery_spending_history (
  id           SERIAL PRIMARY KEY,
  user_id      INTEGER NOT NULL REFERENCES users(id),
  shop_item_id INTEGER NOT NULL REFERENCES shop_items(id),
  cost         INTEGER NOT NULL,
  created_at   TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE admin_deleted_orders (
  id                SERIAL PRIMARY KEY,
  original_order_id INTEGER NOT NULL,
  user_id           INTEGER NOT NULL,
  shop_item_id      INTEGER NOT NULL,
  quantity          INTEGER NOT NULL,
  price_per_item    INTEGER NOT NULL,
  total_price       INTEGER NOT NULL,
  status            TEXT NOT NULL,
  order_type        TEXT NOT NULL,
  shipping_address  TEXT,
  phone             TEXT,
  item_name         TEXT,
  created_at        TIMESTAMP,
  deleted_payload   JSONB NOT NULL,
  deleted_by        INTEGER REFERENCES users(id),
  deleted_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  reason            TEXT NOT NULL,
  restored          BOOLEAN NOT NULL DEFAULT FALSE,
  restored_by       INTEGER REFERENCES users(id),
  restored_at       TIMESTAMP
);
