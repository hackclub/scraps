# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_03_121000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "admin_deleted_orders", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.datetime "deleted_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "deleted_by"
    t.jsonb "deleted_payload", null: false
    t.text "item_name"
    t.text "order_type", null: false
    t.integer "original_order_id", null: false
    t.text "phone"
    t.integer "price_per_item", null: false
    t.integer "quantity", null: false
    t.text "reason", null: false
    t.boolean "restored", default: false, null: false
    t.datetime "restored_at", precision: nil
    t.integer "restored_by"
    t.text "shipping_address"
    t.integer "shop_item_id", null: false
    t.text "status", null: false
    t.integer "total_price", null: false
    t.integer "user_id", null: false
  end

  create_table "blazer_audits", force: :cascade do |t|
    t.datetime "created_at"
    t.string "data_source"
    t.bigint "query_id"
    t.text "statement"
    t.bigint "user_id"
    t.index ["query_id"], name: "index_blazer_audits_on_query_id"
    t.index ["user_id"], name: "index_blazer_audits_on_user_id"
  end

  create_table "blazer_checks", force: :cascade do |t|
    t.string "check_type"
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.text "emails"
    t.datetime "last_run_at"
    t.text "message"
    t.bigint "query_id"
    t.string "schedule"
    t.text "slack_channels"
    t.string "state"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_checks_on_creator_id"
    t.index ["query_id"], name: "index_blazer_checks_on_query_id"
  end

  create_table "blazer_dashboard_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "dashboard_id"
    t.integer "position"
    t.bigint "query_id"
    t.datetime "updated_at", null: false
    t.index ["dashboard_id"], name: "index_blazer_dashboard_queries_on_dashboard_id"
    t.index ["query_id"], name: "index_blazer_dashboard_queries_on_query_id"
  end

  create_table "blazer_dashboards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_dashboards_on_creator_id"
  end

  create_table "blazer_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.string "data_source"
    t.text "description"
    t.string "name"
    t.text "statement"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_queries_on_creator_id"
  end

  create_table "login_allowlist_entries", force: :cascade do |t|
    t.bigint "added_by_user_id"
    t.datetime "created_at", null: false
    t.text "identifier", null: false
    t.text "identifier_type", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.index ["identifier_type", "identifier"], name: "idx_on_identifier_type_identifier_9d4040f940", unique: true
  end

  create_table "news", id: :serial, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.text "content", null: false
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.text "title", null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
  end

  create_table "project_activity", id: :serial, force: :cascade do |t|
    t.text "action", null: false
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "project_id"
    t.integer "user_id"
    t.index ["project_id"], name: "index_project_activity_on_project_id"
    t.index ["user_id"], name: "index_project_activity_on_user_id"
  end

  create_table "projects", id: :serial, force: :cascade do |t|
    t.text "ai_description"
    t.text "airtable_id"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "deleted", default: 0, null: false
    t.text "description"
    t.text "feedback_good"
    t.text "feedback_improve"
    t.text "feedback_source"
    t.text "github_url"
    t.text "hackatime_project"
    t.float "hours", default: 0.0, null: false
    t.float "hours_override"
    t.text "image"
    t.text "internal_notes"
    t.boolean "is_reship", default: false, null: false
    t.text "name", default: "", null: false
    t.text "playable_url"
    t.text "reviewer_notes"
    t.integer "scraps_awarded", default: 0, null: false
    t.integer "scraps_paid_amount", default: 0, null: false
    t.datetime "scraps_paid_at", precision: nil
    t.text "status", default: "in_progress", null: false
    t.integer "tier", default: 1, null: false
    t.integer "tier_override"
    t.text "update_description"
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "user_id", null: false
    t.integer "views", default: 0, null: false
    t.index ["status"], name: "index_projects_on_status"
    t.index ["updated_at"], name: "index_projects_on_updated_at"
    t.index ["user_id"], name: "index_projects_on_user_id"
    t.index ["views"], name: "index_projects_on_views"
  end

  create_table "referrals", force: :cascade do |t|
    t.text "code", null: false
    t.datetime "created_at", null: false
    t.bigint "referred_user_id", null: false
    t.bigint "referrer_id", null: false
    t.integer "reward_amount", default: 0, null: false
    t.boolean "rewarded", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["referred_user_id"], name: "index_referrals_on_referred_user_id", unique: true
    t.index ["referrer_id"], name: "index_referrals_on_referrer_id"
  end

  create_table "refinery_orders", id: :serial, force: :cascade do |t|
    t.float "boost_amount", null: false
    t.integer "cost", null: false
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "shop_item_id", null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_refinery_orders_on_user_id"
  end

  create_table "refinery_spending_history", id: :serial, force: :cascade do |t|
    t.integer "cost", null: false
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "shop_item_id", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_refinery_spending_history_on_user_id"
  end

  create_table "reviews", id: :serial, force: :cascade do |t|
    t.text "action", null: false
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.text "feedback_for_author"
    t.text "internal_justification"
    t.integer "project_id", null: false
    t.integer "reviewer_id", null: false
    t.index ["project_id"], name: "index_reviews_on_project_id"
    t.index ["reviewer_id"], name: "index_reviews_on_reviewer_id"
  end

  create_table "sessions", primary_key: "token", id: :text, force: :cascade do |t|
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.datetime "expires_at", precision: nil, null: false
    t.integer "user_id", null: false
  end

  create_table "shop_hearts", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "shop_item_id", null: false
    t.integer "user_id", null: false
    t.index ["shop_item_id"], name: "index_shop_hearts_on_shop_item_id"
    t.unique_constraint ["user_id", "shop_item_id"], name: "shop_hearts_user_id_shop_item_id_key"
  end

  create_table "shop_items", id: :serial, force: :cascade do |t|
    t.float "base_probability", default: 50.0, null: false
    t.integer "base_upgrade_cost"
    t.float "boost_amount", default: 5.0, null: false
    t.text "category", default: "", null: false
    t.float "cost_multiplier"
    t.integer "count", default: 0, null: false
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.text "description", default: "", null: false
    t.text "image", default: "", null: false
    t.text "name", null: false
    t.float "per_roll_multiplier", default: 0.05, null: false
    t.integer "price", default: 0, null: false
    t.integer "roll_cost_override"
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.float "upgrade_budget_multiplier", default: 3.0, null: false
  end

  create_table "shop_orders", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.boolean "is_fulfilled", default: false, null: false
    t.text "notes"
    t.text "order_type", null: false
    t.text "phone"
    t.integer "price_per_item", default: 0, null: false
    t.integer "quantity", default: 1, null: false
    t.text "shipping_address"
    t.integer "shop_item_id", null: false
    t.text "status", default: "pending", null: false
    t.integer "total_price", default: 0, null: false
    t.text "tracking_number"
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_shop_orders_on_user_id"
  end

  create_table "shop_penalties", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.float "probability_multiplier", default: 100.0, null: false
    t.integer "shop_item_id", null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_shop_penalties_on_user_id"
  end

  create_table "shop_rolls", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "rolled", null: false
    t.integer "shop_item_id", null: false
    t.integer "threshold", null: false
    t.integer "user_id", null: false
    t.boolean "won", default: false, null: false
    t.index ["user_id"], name: "index_shop_rolls_on_user_id"
  end

  create_table "user_activity", id: :serial, force: :cascade do |t|
    t.text "action", null: false
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.text "email"
    t.integer "user_id"
    t.index ["email"], name: "index_user_activity_on_email"
    t.index ["user_id"], name: "index_user_activity_on_user_id"
  end

  create_table "user_bonuses", id: :serial, force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "given_by"
    t.text "reason", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_user_bonuses_on_user_id"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.text "access_token"
    t.text "address_city"
    t.text "address_country"
    t.text "address_line1"
    t.text "address_line2"
    t.text "address_postal_code"
    t.text "address_state"
    t.string "airtable_id"
    t.text "avatar"
    t.date "birthday"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.text "email", default: "", null: false
    t.text "first_name"
    t.datetime "hackatime_ban_checked_at"
    t.boolean "hackatime_banned", default: false, null: false
    t.boolean "has_been_onboarded", default: false, null: false
    t.text "id_token"
    t.text "internal_notes"
    t.text "language", default: "en"
    t.text "legal_first_name"
    t.text "legal_last_name"
    t.text "phone"
    t.text "referral_code"
    t.text "refresh_token"
    t.text "role", default: "member", null: false
    t.text "slack_id"
    t.text "sub", null: false
    t.boolean "tutorial_completed", default: false, null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.text "username"
    t.text "verification_status"
    t.boolean "ysws_eligible"
    t.index ["referral_code"], name: "index_users_on_referral_code", unique: true
    t.unique_constraint ["sub"], name: "users_sub_key"
  end

  add_foreign_key "admin_deleted_orders", "users", column: "deleted_by", name: "admin_deleted_orders_deleted_by_fkey"
  add_foreign_key "admin_deleted_orders", "users", column: "restored_by", name: "admin_deleted_orders_restored_by_fkey"
  add_foreign_key "project_activity", "projects", name: "project_activity_project_id_fkey"
  add_foreign_key "project_activity", "users", name: "project_activity_user_id_fkey"
  add_foreign_key "projects", "users", name: "projects_user_id_fkey"
  add_foreign_key "refinery_orders", "shop_items", name: "refinery_orders_shop_item_id_fkey"
  add_foreign_key "refinery_orders", "users", name: "refinery_orders_user_id_fkey"
  add_foreign_key "refinery_spending_history", "shop_items", name: "refinery_spending_history_shop_item_id_fkey"
  add_foreign_key "refinery_spending_history", "users", name: "refinery_spending_history_user_id_fkey"
  add_foreign_key "reviews", "projects", name: "reviews_project_id_fkey"
  add_foreign_key "reviews", "users", column: "reviewer_id", name: "reviews_reviewer_id_fkey"
  add_foreign_key "sessions", "users", name: "sessions_user_id_fkey"
  add_foreign_key "shop_hearts", "shop_items", name: "shop_hearts_shop_item_id_fkey"
  add_foreign_key "shop_hearts", "users", name: "shop_hearts_user_id_fkey"
  add_foreign_key "shop_orders", "shop_items", name: "shop_orders_shop_item_id_fkey"
  add_foreign_key "shop_orders", "users", name: "shop_orders_user_id_fkey"
  add_foreign_key "shop_penalties", "shop_items", name: "shop_penalties_shop_item_id_fkey"
  add_foreign_key "shop_penalties", "users", name: "shop_penalties_user_id_fkey"
  add_foreign_key "shop_rolls", "shop_items", name: "shop_rolls_shop_item_id_fkey"
  add_foreign_key "shop_rolls", "users", name: "shop_rolls_user_id_fkey"
  add_foreign_key "user_activity", "users", name: "user_activity_user_id_fkey"
  add_foreign_key "user_bonuses", "users", column: "given_by", name: "user_bonuses_given_by_fkey"
  add_foreign_key "user_bonuses", "users", name: "user_bonuses_user_id_fkey"
end
