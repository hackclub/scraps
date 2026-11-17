module StreakService
  TZ = "America/New_York"
  GOAL = 30 * 60
  BONUS = 60 * 60
  SYNC_EVERY_MINUTES = 5
  HISTORY_WEEKS = 5
  REWARDS_START = Date.new(2026, 11, 17)
  REWARDS = {
    2 => { kind: "spool", title: "your choice of a shop item!", tickets: 1 },
    5 => { kind: "roll", title: "random amount of scraps", tickets: 2 },
    7 => { kind: "week", title: "+100 scraps", tickets: 3, scraps: 100 }
  }.freeze
  MYSTERY_SCRAPS = { 10 => 60, 25 => 30, 50 => 10 }.freeze
  TICKET = { kind: "ticket", title: "raffle ticket", tickets: 1 }.freeze
  BASE = { kind: "base", tickets: 1 }.freeze
  HOUR = { kind: "hour", tickets: 1 }.freeze

  class ClaimError < StandardError; end

  class << self
    def zone
      ActiveSupport::TimeZone[TZ]
    end

    def today
      zone.today
    end

    def monday(d)
      d - (d.cwday - 1)
    end

    def history_start
      [monday(today) - HISTORY_WEEKS * 7, REWARDS_START].max
    end

    def calendar_start
      monday(history_start)
    end

    def week_start(d)
      [monday(d), REWARDS_START].max
    end

    def linked_project_names(uid)
      conn.select_values("SELECT hackatime_project FROM projects WHERE user_id = #{uid} AND (deleted = 0 OR deleted IS NULL) AND hackatime_project IS NOT NULL AND hackatime_project <> ''")
        .flat_map { |h| HackatimeService.project_names(h) }
        .uniq
    end

    def conn
      ActiveRecord::Base.connection
    end

    def sync(user)
      uid = user.id.to_i
      row = conn.select_one(<<~SQL)
        UPDATE users SET streak_synced_at = NOW()
        WHERE id = #{uid} AND (streak_synced_at IS NULL OR streak_synced_at < NOW() - INTERVAL '#{SYNC_EVERY_MINUTES} minutes')
        RETURNING hackatime_user_id, email, slack_id
      SQL
      return unless row

      ht_id = row["hackatime_user_id"].presence&.to_i
      ht_id ||= HackatimeService.get_user(row["email"], row["slack_id"])&.dig(:user_id)
      return unless ht_id

      last = conn.select_value("SELECT MAX(day) FROM user_daily_minutes WHERE user_id = #{uid}")
      from = last ? [Date.parse(last.to_s) - 1, history_start].max : history_start
      times = []
      linked_project_names(uid).each do |name|
        page = HackatimeService.fetch_heartbeat_times(ht_id, (from - 1).to_s, name)
        unless page
          conn.execute("UPDATE users SET streak_synced_at = NULL WHERE id = #{uid}")
          return
        end
        times.concat(page)
      end
      times.sort!

      totals = Hash.new(0.0)
      times.each_cons(2) do |prev, time|
        day = zone.at(prev).to_date
        totals[day] += [time - prev, HackatimeService::HEARTBEAT_TIMEOUT].min if day >= from
      end

      values = (from..today).map { |d| "(#{uid}, #{conn.quote(d.to_s)}, #{totals[d].round}, NOW(), NOW())" }
      conn.execute(<<~SQL)
        INSERT INTO user_daily_minutes (user_id, day, seconds, created_at, updated_at)
        VALUES #{values.join(', ')}
        ON CONFLICT (user_id, day) DO UPDATE SET seconds = EXCLUDED.seconds, updated_at = NOW()
      SQL
    end

    def load(user)
      uid = user.id.to_i
      start = conn.quote(history_start.to_s)
      secs = conn.select_all("SELECT day, seconds FROM user_daily_minutes WHERE user_id = #{uid} AND day >= #{start}")
        .to_h { |r| [Date.parse(r["day"].to_s), r["seconds"].to_i] }
      claims = Hash.new { |h, k| h[k] = {} }
      conn.select_all("SELECT day, kind, detail FROM streak_reward_claims WHERE user_id = #{uid} AND day >= #{start}").each do |r|
        claims[Date.parse(r["day"].to_s)][r["kind"]] = r["detail"]
      end
      [secs, claims]
    end

    def weekly_run(d, secs)
      n = 0
      (week_start(d)..d).each do |x|
        break unless secs[x].to_i >= GOAL
        n += 1
      end
      n
    end

    def alive?(secs)
      t = today
      ws = week_start(t)
      t == ws || weekly_run(t - 1, secs) >= (t - ws).to_i
    end

    def parts_for(d, secs)
      t = today
      return [] if d > t
      big = REWARDS[d.cwday]
      parts = []
      parts << BASE if secs[d].to_i >= GOAL
      if secs[d].to_i >= BONUS
        if !big
          parts << HOUR
        elsif weekly_run(d, secs) >= (d - week_start(d)).to_i + 1
          parts << big
        end
      end
      parts
    end

    def reward_for(d, secs, claims)
      return nil if d < REWARDS_START
      t = today
      big = REWARDS[d.cwday]
      r = big || TICKET
      done = claims.key?(d) ? claims[d] : {}
      unlocked = parts_for(d, secs)
      pending = unlocked.reject { |p| done.key?(p[:kind]) }
      window = d >= monday(t) - 7
      bonus_kind = big ? big[:kind] : HOUR[:kind]
      slot_state = lambda do |kind, possible|
        next "claimed" if done.key?(kind)
        next(window ? "claimable" : "expired") if unlocked.any? { |p| p[:kind] == kind }
        next(possible ? "upcoming" : "lost") if d >= t
        "lost"
      end
      info = {
        kind: r[:kind],
        title: r[:title],
        claimed: done.values.join(", ").presence,
        pending: pending.map { |p| p[:kind] },
        tickets: pending.sum { |p| p[:tickets] },
        slots: [
          { slot: "base", kind: "ticket", state: slot_state.call(BASE[:kind], true) },
          { slot: "bonus", kind: big ? big[:kind] : "ticket", state: slot_state.call(bonus_kind, !big || monday(d) > monday(t) || alive?(secs)) }
        ]
      }
      if pending.any?
        return info.merge(state: "claimable") if d >= monday(t) - 7
        return info.merge(state: done.any? ? "claimed" : "expired")
      end
      return info.merge(state: "claimed") if done.any?
      if d >= t
        return info.merge(state: "upcoming") if !big || monday(d) > monday(t)
        return info.merge(state: alive?(secs) ? "upcoming" : "lost")
      end
      info.merge(state: "lost")
    end

    def state(user)
      secs, claims = load(user)
      t = today
      start = calendar_start
      tickets = conn.select_value("SELECT raffle_tickets FROM users WHERE id = #{user.id.to_i}").to_i
      weeks = (0..((monday(t) - start).to_i / 7)).map do |w|
        (0..6).map do |i|
          d = start + w * 7 + i
          active = d >= REWARDS_START
          { date: d.to_s, active: active, minutes: secs[d].to_i / 60, kept: active && secs[d].to_i >= GOAL, reward: reward_for(d, secs, claims) }
        end
      end
      {
        today: t.to_s,
        goal_minutes: GOAL / 60,
        bonus_minutes: BONUS / 60,
        today_minutes: secs[t].to_i / 60,
        week_streak: weekly_run(t, secs),
        week_days: 7 - (week_start(t) - monday(t)).to_i,
        alive: alive?(secs),
        tickets: tickets,
        weeks: weeks,
        unclaimed: weeks.flatten.select { |x| x[:reward]&.dig(:state) == "claimable" }.map { |x| x[:date] }
      }
    end

    def claim(user, date, item_id = nil)
      d = Date.iso8601(date.to_s) rescue (raise ClaimError, "Invalid date")
      secs, claims = load(user)
      r = reward_for(d, secs, claims)
      raise ClaimError, "Nothing to claim for that day" unless r && r[:state] == "claimable"
      done = claims.key?(d) ? claims[d] : {}
      parts = parts_for(d, secs).reject { |p| done.key?(p[:kind]) }

      uid = user.id.to_i
      details = {}
      ActiveRecord::Base.transaction do
        parts.each do |p|
          detail =
            case p[:kind]
            when "spool"
              item = conn.select_one("SELECT id, name FROM shop_items WHERE id = #{item_id.to_i} AND hidden = false AND consolation_prize = false AND gachapon_only = false")
              raise ClaimError, "Pick an item from the shop" unless item
              if conn.select_value("SELECT 1 FROM shop_retained_items WHERE user_id = #{uid} AND shop_item_id = #{item['id'].to_i}")
                raise ClaimError, "That item is already in your shop, pick another"
              end
              used = conn.select_value("SELECT COUNT(*) FROM shop_retained_items WHERE user_id = #{uid}").to_i
              cap = ShopController.retained_items_cap_for(user)
              raise ClaimError, "Your shop is full (#{used}/#{cap}). Remove an item first, then claim" if used >= cap
              conn.execute("INSERT INTO shop_retained_items (user_id, shop_item_id, created_at) VALUES (#{uid}, #{item['id'].to_i}, NOW())")
              item["name"]
            when "roll"
              pick = rand(MYSTERY_SCRAPS.values.sum)
              amount = MYSTERY_SCRAPS.find { |_, w| (pick -= w) < 0 }.first
              conn.execute("INSERT INTO user_bonuses (user_id, amount, reason, created_at) VALUES (#{uid}, #{amount}, #{conn.quote('streak: mystery roll')}, NOW())")
              "+#{amount} scraps"
            when "week"
              conn.execute("INSERT INTO user_bonuses (user_id, amount, reason, created_at) VALUES (#{uid}, #{p[:scraps].to_i}, #{conn.quote('streak: full week')}, NOW())")
              "+#{p[:scraps]} scraps"
            else
              "raffle ticket"
            end

          inserted = conn.select_value(<<~SQL)
            INSERT INTO streak_reward_claims (user_id, day, kind, tickets, detail, created_at)
            VALUES (#{uid}, #{conn.quote(d.to_s)}, #{conn.quote(p[:kind])}, #{p[:tickets].to_i}, #{conn.quote(detail)}, NOW())
            ON CONFLICT (user_id, day, kind) DO NOTHING
            RETURNING id
          SQL
          raise ClaimError, "Already claimed" unless inserted
          details[p[:kind]] = detail
        end

        conn.execute("UPDATE users SET raffle_tickets = raffle_tickets + #{parts.sum { |p| p[:tickets].to_i }} WHERE id = #{uid}")
      end
      main = details.except("base", "hour").values.first
      { success: true, detail: main || "raffle ticket", tickets: parts.sum { |p| p[:tickets] } }
    end
  end
end
