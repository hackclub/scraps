module ScrapsService
  SCRAPS_PER_HOUR = 64.0
  DOLLARS_PER_HOUR = 4
  SCRAPS_PER_DOLLAR = SCRAPS_PER_HOUR / DOLLARS_PER_HOUR

  TIER_MULTIPLIERS = {
    1 => 0.8,
    2 => 1.0,
    3 => 1.25,
    4 => 1.5
  }.freeze

# find a good baalnce or smtjh iasjdioasjdoasd
  SCORE_FLOOR_MULT = 0.5
  SCORE_NEUTRAL_MULT = 1.0
  SCORE_CEIL_MULT = 2.0

  UPGRADE_START_PERCENT = 0.25
  UPGRADE_DECAY = 1.05

  def self.calculate_scraps_from_hours(hours, tier = 1)
    tier_multiplier = TIER_MULTIPLIERS[tier] || 1.0
    (hours * SCRAPS_PER_HOUR * tier_multiplier).floor
  end

  def self.reviewer_score_multiplier(score)
    score = score.to_f.clamp(1.0, 3.0)
    x1, y1 = 1.0, SCORE_FLOOR_MULT
    x2, y2 = 2.0, SCORE_NEUTRAL_MULT
    x3, y3 = 3.0, SCORE_CEIL_MULT
    l1 = ((score - x2) * (score - x3)) / ((x1 - x2) * (x1 - x3))
    l2 = ((score - x1) * (score - x3)) / ((x2 - x1) * (x2 - x3))
    l3 = ((score - x1) * (score - x2)) / ((x3 - x1) * (x3 - x2))
    y1 * l1 + y2 * l2 + y3 * l3
  end

  def self.calculate_scraps_from_score(hours, reviewer_score)
    (hours * SCRAPS_PER_HOUR * reviewer_score_multiplier(reviewer_score)).floor
  end

  def self.get_user_scraps_balance(user_id, conn = ActiveRecord::Base.connection)
    # FIXED THE NUMBER OF QUERIES
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

    {
      earned: earned,
      pending: pending,
      spent: spent,
      balance: balance,
      project_earned: project_earned,
      bonus_earned: bonus_earned,
      shop_spent: shop_spent,
      upgrade_spent: upgrade_spent
    }
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
    [(probability * 17 / 20.0).floor, 1].max
  end

  def self.get_upgrade_cost(price, upgrade_count, _actual_spent = nil, base_upgrade_cost = nil)
    base = base_upgrade_cost || [1, (price * UPGRADE_START_PERCENT).floor].max
    [1, (base / (UPGRADE_DECAY**upgrade_count)).floor].max
  end
end
