class HackatimeBanSyncJob < ApplicationJob
  queue_as :default

  PROTECTED_ROLES = %w[admin creator].freeze
  IDLE_RECHECK_AFTER = 1.hour
  LOCK_KEY = "lock:hackatime_ban_sync"
  LOCK_TTL = 600

  def perform
    got_lock = Sidekiq.redis { |r| r.set(LOCK_KEY, Time.now.to_i, nx: true, ex: LOCK_TTL) }
    return Rails.logger.info("[HackatimeBanSyncJob] previous run still going, skipping") unless got_lock
    begin
      run(ActiveRecord::Base.connection)
    ensure
      Sidekiq.redis { |r| r.del(LOCK_KEY) }
    end
  end

  private

  def run(conn)
    rows = conn.select_all(<<~SQL).to_a
      SELECT id, username, email, slack_id, role, hackatime_banned, hackatime_user_id
      FROM users
      WHERE email <> '' AND role <> 'banned'
        AND (
          EXISTS (SELECT 1 FROM sessions s WHERE s.user_id = users.id AND s.expires_at > NOW())
          OR hackatime_ban_checked_at IS NULL
          OR hackatime_ban_checked_at < NOW() - INTERVAL '#{IDLE_RECHECK_AFTER.to_i} seconds'
        )
      ORDER BY hackatime_ban_checked_at ASC NULLS FIRST
    SQL

    banned_count = 0
    rows.each do |u|
      ht = begin
        (u["hackatime_user_id"] && HackatimeService.get_user_by_id(u["hackatime_user_id"])) ||
          HackatimeService.get_user(u["email"], u["slack_id"])
      rescue StandardError
        :error
      end
      next if ht == :error

      red = ht.is_a?(Hash) && (ht[:trust_level] == "red" || ht[:banned] == true)
      ht_id = ht.is_a?(Hash) && ht[:user_id].to_i.positive? ? ht[:user_id].to_i : "NULL"

      conn.execute(<<~SQL)
        UPDATE users
        SET hackatime_banned = #{red}, hackatime_ban_checked_at = NOW(), hackatime_user_id = #{ht_id}
        WHERE id = #{u['id'].to_i}
      SQL

      next unless red

      if PROTECTED_ROLES.include?(u["role"])
        was_red = [true, "t", 1].include?(u["hackatime_banned"])
        notify(u, "banned", "Hackatime red — NOT auto-banned (#{u['role']})") unless was_red
        next
      end

      conn.execute("UPDATE users SET role = 'banned', updated_at = NOW() WHERE id = #{u['id'].to_i} AND role <> 'banned'")
      conn.execute("DELETE FROM sessions WHERE user_id = #{u['id'].to_i}")
      notify(u, "banned", "Hackatime red (auto-ban)")
      banned_count += 1
    end

    Rails.logger.info("[HackatimeBanSyncJob] checked #{rows.length} users, auto-banned #{banned_count}")
  end

  def notify(user, new_role, reason)
    SlackService.notify_role_change(
      token: ENV["SLACK_BOT_TOKEN"],
      target_id: user["id"].to_i,
      target_username: user["username"],
      target_slack_id: user["slack_id"],
      old_role: user["role"],
      new_role: new_role,
      changed_by_username: reason,
      changed_by_slack_id: nil
    )
  end
end
