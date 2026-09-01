module ScrapsService
  PHI = (1 + Math.sqrt(5)) / 2
  MULTIPLIER = 10
  SCRAPS_PER_HOUR = PHI * MULTIPLIER
  DOLLARS_PER_HOUR = 4
  SCRAPS_PER_DOLLAR = SCRAPS_PER_HOUR / DOLLARS_PER_HOUR

  TIER_MULTIPLIERS = {
    1 => 0.8,
    2 => 1.0,
    3 => 1.25,
    4 => 1.5
  }.freeze

  UPGRADE_START_PERCENT = 0.25
  UPGRADE_DECAY = 1.05
  UPGRADE_MAX_BUDGET_MULTIPLIER = 3

  def self.calculate_scraps_from_hours(hours, tier = 1)
    tier_multiplier = TIER_MULTIPLIERS[tier] || 1.0
    (hours * PHI * MULTIPLIER * tier_multiplier).floor
  end

  def self.get_user_scraps_balance(user_id, conn = ActiveRecord::Base.connection)
    # One round-trip instead of five — the remote DB has ~100ms latency per query.
    row = conn.select_one(<<~SQL, "ScrapsBalance", [user_id])
      SELECT
        (SELECT COALESCE(SUM(CASE WHEN scraps_paid_amount > 0 THEN scraps_paid_amount ELSE scraps_awarded END), 0)
         FROM projects
         WHERE user_id = $1
           AND (scraps_paid_at IS NOT NULL OR scraps_paid_amount > 0)
           AND scraps_awarded > 0) AS project_earned,
        (SELECT COALESCE(SUM(scraps_awarded - CASE WHEN scraps_paid_amount > 0 THEN scraps_paid_amount ELSE 0 END), 0)
         FROM projects
         WHERE user_id = $1
           AND status = 'shipped'
           AND (deleted = 0 OR deleted IS NULL)
           AND scraps_paid_at IS NULL
           AND scraps_awarded > 0) AS pending,
        (SELECT COALESCE(SUM(amount), 0)
         FROM user_bonuses WHERE user_id = $1) AS bonus_earned,
        (SELECT COALESCE(SUM(total_price), 0)
         FROM shop_orders
         WHERE user_id = $1 AND status NOT IN ('cancelled', 'deleted')) AS shop_spent,
        (SELECT COALESCE(SUM(cost), 0)
         FROM refinery_spending_history WHERE user_id = $1) AS refinery_spent
    SQL

    project_earned = row["project_earned"].to_f.round
    pending = row["pending"].to_f.round
    bonus_earned = row["bonus_earned"].to_f.round
    earned = project_earned + bonus_earned
    shop_spent = row["shop_spent"].to_f.round
    upgrade_spent = row["refinery_spent"].to_f.round
    spent = shop_spent + upgrade_spent
    balance = earned - spent

    { earned: earned, pending: pending, spent: spent, balance: balance }
  end

  def self.can_afford?(user_id, cost, conn = ActiveRecord::Base.connection)
    return false if cost < 0 || !cost.finite?
    balance = get_user_scraps_balance(user_id, conn)[:balance]
    balance >= cost
  end

  def self.calculate_roll_cost(base_price, effective_probability, roll_cost_override = nil, base_probability = nil)
    if roll_cost_override && roll_cost_override > 0
      return roll_cost_override
    end
    prob = base_probability || effective_probability
    [1, (base_price * (prob / 100.0)).round].max
  end

  def self.compute_roll_threshold(probability)
    # 15% house edge
    [(probability * 17 / 20.0).floor, 1].max
  end

  def self.get_upgrade_cost(price, upgrade_count, actual_spent = nil, base_upgrade_cost = nil)
    max_budget = price * UPGRADE_MAX_BUDGET_MULTIPLIER
    cumulative = actual_spent || 0
    return nil if cumulative >= max_budget

    base = base_upgrade_cost || [1, (price * UPGRADE_START_PERCENT).floor].max
    next_cost = [1, (base / (UPGRADE_DECAY**upgrade_count)).floor].max

    if cumulative + next_cost > max_budget
      remaining = (max_budget - cumulative).floor
      return remaining > 0 ? remaining : nil
    end
    next_cost
  end
end
