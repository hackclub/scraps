class AddHackatimeBanCacheToUsers < ActiveRecord::Migration[8.1]
  def change
    # Cached from the Hackatime admin API by HackatimeBanSyncJob so the leaderboard
    # can filter banned users with a WHERE clause instead of an HTTP call per row.
    add_column :users, :hackatime_banned, :boolean, default: false, null: false
    add_column :users, :hackatime_ban_checked_at, :datetime
  end
end
