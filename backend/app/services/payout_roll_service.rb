module PayoutRollService
  CENTER = 0.867
  SPREAD = 0.75
  MIN_MULT = 0.5
  MAX_MULT = 2.0
  EXPECTED_MULTIPLIER = 1.0
  BONUS_REASON = "payout_roll"

  class RollError < StandardError; end

  def self.roll_value
    (CENTER + (rand - rand) * SPREAD).clamp(MIN_MULT, MAX_MULT).round(2)
  end

  def self.open_for_approval(conn, project_id:, user_id:, base_scraps:)
    conn.select_all("SELECT * FROM payout_rolls WHERE project_id = #{project_id.to_i} AND status IN ('open', 'rolled') FOR UPDATE").each do |stale|
      finalize!(conn, stale, stale["status"] == "rolled" ? stale["roll_1"].to_f : 1.0)
    end
    return if base_scraps.to_i <= 0
    conn.execute(<<~SQL)
      INSERT INTO payout_rolls (project_id, user_id, base_scraps, status, created_at, updated_at)
      VALUES (#{project_id.to_i}, #{user_id.to_i}, #{base_scraps.to_i}, 'open', NOW(), NOW())
    SQL
  end

  def self.cancel_for_project(conn, project_id:)
    ids = conn.select_values("SELECT id FROM payout_rolls WHERE project_id = #{project_id.to_i} AND status <> 'cancelled'").map(&:to_i)
    return if ids.empty?
    conn.execute("DELETE FROM user_bonuses WHERE reason IN (#{ids.map { |i| conn.quote("#{BONUS_REASON}:#{i}") }.join(', ')})")
    conn.execute("UPDATE payout_rolls SET status = 'cancelled', decided_at = NOW(), updated_at = NOW() WHERE id IN (#{ids.join(',')})")
  end

  def self.current(conn, project_id:, user_id:)
    conn.select_one("SELECT * FROM payout_rolls WHERE project_id = #{project_id.to_i} AND user_id = #{user_id.to_i} ORDER BY id DESC LIMIT 1")
  end

  def self.max_loss(base_scraps)
    base_scraps.to_i - (base_scraps.to_i * MIN_MULT).floor
  end

  def self.roll!(project_id:, user_id:)
    ActiveRecord::Base.transaction do
      conn = ActiveRecord::Base.connection
      conn.execute("SELECT 1 FROM users WHERE id = #{user_id.to_i} FOR UPDATE")
      row = conn.select_one("SELECT * FROM payout_rolls WHERE project_id = #{project_id.to_i} AND user_id = #{user_id.to_i} AND status IN ('open', 'rolled') ORDER BY id DESC LIMIT 1 FOR UPDATE")
      raise RollError, "no_open_payout" unless row

      balance = ScrapsService.get_user_scraps_balance(user_id.to_i, conn)[:balance]
      raise RollError, "already_spent" if balance < max_loss(row["base_scraps"])

      if row["status"] == "open"
        value = roll_value
        conn.execute("UPDATE payout_rolls SET roll_1 = #{value}, status = 'rolled', updated_at = NOW() WHERE id = #{row['id'].to_i}")
        state_for(conn.select_one("SELECT * FROM payout_rolls WHERE id = #{row['id'].to_i}"))
      else
        value = roll_value
        finalize!(conn, row, value, roll_2: value)
      end
    end
  end

  def self.keep!(project_id:, user_id:)
    ActiveRecord::Base.transaction do
      conn = ActiveRecord::Base.connection
      conn.execute("SELECT 1 FROM users WHERE id = #{user_id.to_i} FOR UPDATE")
      row = conn.select_one("SELECT * FROM payout_rolls WHERE project_id = #{project_id.to_i} AND user_id = #{user_id.to_i} AND status IN ('open', 'rolled') ORDER BY id DESC LIMIT 1 FOR UPDATE")
      raise RollError, "no_open_payout" unless row
      mult = row["status"] == "rolled" ? row["roll_1"].to_f : 1.0
      finalize!(conn, row, mult)
    end
  end

  def self.finalize!(conn, row, mult, roll_2: nil)
    base = row["base_scraps"].to_i
    delta = (base * mult).floor - base
    roll_2_sql = roll_2 ? ", roll_2 = #{roll_2}" : ""
    conn.execute("UPDATE payout_rolls SET final_multiplier = #{mult}, status = 'final', decided_at = NOW(), updated_at = NOW()#{roll_2_sql} WHERE id = #{row['id'].to_i}")
    if delta != 0
      conn.execute("INSERT INTO user_bonuses (user_id, amount, reason, created_at) VALUES (#{row['user_id'].to_i}, #{delta}, #{conn.quote("#{BONUS_REASON}:#{row['id'].to_i}")}, NOW())")
    end
    state_for(conn.select_one("SELECT * FROM payout_rolls WHERE id = #{row['id'].to_i}"))
  end

  def self.state_for(row)
    return nil unless row
    base = row["base_scraps"].to_i
    mult = row["final_multiplier"]&.to_f
    {
      id: row["id"].to_i,
      status: row["status"],
      base_scraps: base,
      roll_1: row["roll_1"]&.to_f,
      roll_2: row["roll_2"]&.to_f,
      final_multiplier: mult,
      final_scraps: mult ? (base * mult).floor : nil,
      min_multiplier: MIN_MULT,
      max_multiplier: [CENTER + SPREAD, MAX_MULT].min.round(2)
    }
  end
end
