class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    # Correlated COUNT(*) subquery in ShopController#items — was a full scan per item.
    add_index :shop_hearts, :shop_item_id, if_not_exists: true

    # Per-user aggregates in the scraps balance calc, the shop item overlay, and
    # the leaderboard subqueries — all full scans without these.
    add_index :user_bonuses, :user_id, if_not_exists: true
    add_index :shop_orders, :user_id, if_not_exists: true
    add_index :refinery_spending_history, :user_id, if_not_exists: true
    add_index :refinery_orders, :user_id, if_not_exists: true
    add_index :shop_penalties, :user_id, if_not_exists: true
    add_index :shop_rolls, :user_id, if_not_exists: true

    # Auth flow inserts one row per login; admin timeline reads by user.
    add_index :user_activity, :user_id, if_not_exists: true
    add_index :user_activity, :email, if_not_exists: true

    # project_activity is read by user_id in EffectiveHoursService and the
    # justification macro; only project_id was indexed.
    add_index :project_activity, :user_id, if_not_exists: true
  end
end
