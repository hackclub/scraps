module RaffleService
  FIRST_DRAW = Time.utc(2026, 11, 25, 17, 0, 0)
  WEEKS = 4
  OPEN_WEEKS = [1, 2].freeze

  class EntryError < StandardError; end

  class << self
    def conn
      ActiveRecord::Base.connection
    end

    def draw_at(week)
      FIRST_DRAW + (week - 1).weeks
    end

    def open?(week)
      OPEN_WEEKS.include?(week) && Time.current < draw_at(week)
    end

    def state(user)
      uid = user.id.to_i
      tickets = conn.select_value("SELECT raffle_tickets FROM users WHERE id = #{uid}").to_i
      placed = conn.select_all("SELECT week, tickets FROM raffle_entries WHERE user_id = #{uid} AND tickets > 0")
        .to_h { |r| [r["week"].to_s, r["tickets"].to_i] }
      { tickets: tickets, placed: placed, open_weeks: (1..WEEKS).select { |w| open?(w) } }
    end

    def set(user, week, count)
      week = Integer(week.to_s, exception: false)
      count = Integer(count.to_s, exception: false)
      raise EntryError, "Unknown week" unless week && week.between?(1, WEEKS)
      raise EntryError, "Invalid ticket count" unless count && count >= 0
      raise EntryError, "That week is closed" unless open?(week)

      uid = user.id.to_i
      ActiveRecord::Base.transaction do
        tickets = conn.select_value("SELECT raffle_tickets FROM users WHERE id = #{uid} FOR UPDATE").to_i
        elsewhere = conn.select_value("SELECT COALESCE(SUM(tickets), 0) FROM raffle_entries WHERE user_id = #{uid} AND week <> #{week}").to_i
        raise EntryError, "You don't have enough tickets" if elsewhere + count > tickets
        conn.execute(<<~SQL)
          INSERT INTO raffle_entries (user_id, week, tickets, created_at, updated_at)
          VALUES (#{uid}, #{week}, #{count}, NOW(), NOW())
          ON CONFLICT (user_id, week) DO UPDATE SET tickets = EXCLUDED.tickets, updated_at = NOW()
        SQL
      end
      state(user)
    end
  end
end
