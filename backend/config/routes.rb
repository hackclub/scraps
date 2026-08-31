Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "/", to: proc { [200, {}, ["if you dm @iamalive abt finding this you may get cool stickers"]] }

  # Auth
  get "oauth/callback", to: "auth#callback"
  get "api/auth/callback/hackclub", to: "auth#callback"
  scope :auth do
    post   "collect-email",  to: "auth#collect_email"
    get    "login",          to: "auth#login"
    get    "callback",       to: "auth#callback"
    get    "me",             to: "auth#me"
    post   "logout",         to: "auth#logout"
  end

  # Projects
  scope :projects do
    get    "explore",              to: "projects#explore"
    get    "/",                    to: "projects#index"
    post   "/",                    to: "projects#create"
    get    ":id",                  to: "projects#show"
    put    ":id",                  to: "projects#update"
    delete ":id",                  to: "projects#destroy"
    post   ":id/submit",           to: "projects#submit"
    post   ":id/unsubmit",         to: "projects#unsubmit"
    get    ":id/reviews",          to: "projects#reviews"
  end

  # Shop
  scope :shop do
    get    "items",                        to: "shop#items"
    get    "items/:id",                    to: "shop#show_item"
    post   "items/:id/heart",              to: "shop#heart"
    post   "items/:id/purchase",           to: "shop#purchase"
    post   "items/:id/try-luck",           to: "shop#try_luck"
    post   "items/:id/upgrade-probability", to: "shop#upgrade_probability"
    post   "items/:id/refinery/undo",      to: "shop#refinery_undo"
    post   "items/:id/refinery/undo-all",  to: "shop#refinery_undo_all"
    get    "items/:id/leaderboard",        to: "shop#item_leaderboard"
    get    "items/:id/buyers",             to: "shop#item_buyers"
    get    "items/:id/hearts",             to: "shop#item_hearts"
    get    "categories",                   to: "shop#categories"
    get    "balance",                      to: "shop#balance"
    get    "orders",                       to: "shop#orders"
    get    "orders/pending-address",       to: "shop#pending_address"
    post   "orders/:id/address",           to: "shop#set_address"
    get    "addresses",                    to: "shop#addresses"
  end

  # Leaderboard
  scope :leaderboard do
    get "/",                  to: "leaderboard#index"
    get "views",              to: "leaderboard#views"
    get "probability-leaders", to: "leaderboard#probability_leaders"
  end

  # News
  scope :news do
    get "/",       to: "news#index"
    get "latest",  to: "news#latest"
  end

  # User
  scope :user do
    get    "me",                to: "user#me"
    put    "language",          to: "user#update_language"
    post   "complete-tutorial", to: "user#complete_tutorial"
    get    "profile/:id",       to: "user#profile"
  end

  # Hackatime
  scope :hackatime do
    get "projects", to: "hackatime#projects"
  end

  # Upload
  scope :upload do
    post "image", to: "upload#image"
  end

  # Slack
  scope :slack do
    post "events", to: "slack#events"
  end

  # Admin
  scope :admin do
    mount  Blazer::Engine,                    at: "blazer"

    get    "stats",                           to: "admin#stats"
    get    "config",                          to: "admin#pricing_config"
    post   "sync-airtable",                   to: "admin#sync_airtable"
    post   "fix-negative-balances",           to: "admin#fix_negative_balances"
    get    "unified-duplicates",              to: "admin#unified_duplicates"
    post   "recalculate-shop-pricing",        to: "admin#recalculate_shop_pricing"

    # Login allowlist
    get    "login-allowlist",                 to: "admin#login_allowlist"
    post   "login-allowlist",                 to: "admin#add_login_allowlist"
    delete "login-allowlist/:id",             to: "admin#delete_login_allowlist"

    # Users
    get    "users",                           to: "admin#users"
    get    "users/:id",                       to: "admin#show_user"
    delete "users/:id",                       to: "admin#delete_user"
    put    "users/:id/role",                  to: "admin#update_role"
    put    "users/:id/notes",                 to: "admin#update_notes"
    post   "users/:id/bonus",                 to: "admin#create_bonus"
    get    "users/:id/bonuses",               to: "admin#user_bonuses"
    get    "users/:id/timeline",              to: "admin#user_timeline"
    delete "bonuses/:id",                     to: "admin#delete_bonus"

    # Reviews
    get    "reviews",                         to: "admin#reviews"
    get    "reviews/:id",                     to: "admin#show_review"
    post   "reviews/:id",                     to: "admin#submit_review"

    # Second pass
    get    "second-pass",                     to: "admin#second_pass"
    get    "second-pass/:id",                 to: "admin#show_second_pass"
    post   "second-pass/:id",                 to: "admin#second_pass_submit"

    # Scraps payout
    get    "scraps-payout",                   to: "admin#scraps_payout_info"
    post   "scraps-payout",                   to: "admin#trigger_payout"
    post   "scraps-payout/reject",            to: "admin#reject_payout"

    # Orders
    get    "orders",                          to: "admin#orders"
    patch  "orders/:id",                      to: "admin#update_order"
    delete "orders/:id",                      to: "admin#delete_order"
    post   "orders/:id/restore",              to: "admin#restore_order"

    # Shop management
    post   "shop/compute-pricing",            to: "admin#compute_pricing"
    post   "shop/compute-roll-costs",         to: "admin#compute_roll_costs"
    post   "shop/reset-non-buyer-refinery",   to: "admin#reset_non_buyer_refinery"
    get    "shop/items",                      to: "admin#shop_items"
    post   "shop/items",                      to: "admin#create_shop_item"
    put    "shop/items/:id",                  to: "admin#update_shop_item"
    delete "shop/items/:id",                  to: "admin#delete_shop_item"

    # News
    get    "news",                            to: "admin#news_index"
    post   "news",                            to: "admin#create_news"
    put    "news/:id",                        to: "admin#update_news"
    delete "news/:id",                        to: "admin#delete_news"

    # Projects (admin actions)
    post   "projects/:id/sync-hours",         to: "admin#sync_hours"
    post   "projects/:id/unship",             to: "admin#unship_project"

    # Exports
    get    "export/review-csv",               to: "admin#export_review_csv"
    get    "export/review-json",              to: "admin#export_review_json"
  end

  # Serves the SvelteKit SPA for any route not matched above, so client-side routing
  # (e.g. a hard refresh on /projects/123) works when Rails serves the built frontend.
  get "*path", to: "static#fallback", constraints: ->(req) { req.format.html? }
end
