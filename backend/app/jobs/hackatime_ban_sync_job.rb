class HackatimeBanSyncJob < ApplicationJob
  queue_as :default

  # Refresh the cached Hackatime ban flag for users whose check is stale, so the
  # leaderboard (and anywhere else) can filter with a WHERE clause instead of an
  # HTTP call per row. Runs on a cron; only touches a bounded batch each pass.
  STALE_AFTER = 6.hours
  BATCH = 40

  def perform
    conn = ActiveRecord::Base.connection
    rows = conn.select_all(<<~SQL).to_a
      SELECT id, email, slack_id
      FROM users
      WHERE email <> ''
        AND (hackatime_ban_checked_at IS NULL
             OR hackatime_ban_checked_at < NOW() - INTERVAL '#{STALE_AFTER.to_i} seconds')
      ORDER BY hackatime_ban_checked_at ASC NULLS FIRST
      LIMIT #{BATCH}
    SQL

    rows.each do |u|
      banned = begin
        ht = HackatimeService.get_user(u["email"], u["slack_id"])
        ht ? (ht[:banned] ? true : false) : false
      rescue StandardError
        nil
      end
      next if banned.nil? # transient failure — leave the old value, retry next pass

      conn.execute(<<~SQL)
        UPDATE users
        SET hackatime_banned = #{banned}, hackatime_ban_checked_at = NOW()
        WHERE id = #{u['id'].to_i}
      SQL
    end

    Rails.logger.info("[HackatimeBanSyncJob] checked #{rows.length} users")
  end
end
