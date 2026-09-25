module ShopPricingService
  DEFAULT_BASE_PROBABILITY = 50
  DEFAULT_PER_ROLL_MULT = 0.05
  UPGRADE_START_PERCENT = 0.25

  CHAOS_PROBABILITY_RANGE = (12..88)
  CHAOS_UPGRADES_TO_MAX_RANGE = (3..22)
  CHAOS_UPGRADE_PERCENT_RANGE = (0.06..0.6)
  CHAOS_MAX_ATTEMPTS = 60

  MIN_SPEND_RATIO = 1.1
  MAX_SPEND_RATIO = 2.2

  # dollar_cost: real dollars the item costs
  # base_prob: optional integer override for base probability (1-99); rolled randomly when nil
  # stock_count: kept for signature compatibility; no longer affects pricing
  def self.compute_item_pricing(dollar_cost, base_prob = nil, _stock_count = 1)
    scraps_price = (dollar_cost * ScrapsService::SCRAPS_PER_DOLLAR).round
    fixed_prob = base_prob&.clamp(1, 99)

    candidate = nil
    CHAOS_MAX_ATTEMPTS.times do
      attempt = chaotic_candidate(scraps_price, fixed_prob)
      ratio = cheapest_spend_ratio(scraps_price, attempt[:base_probability], attempt[:base_upgrade_cost], attempt[:boost_amount])
      if ratio >= min_spend_ratio(scraps_price, attempt[:base_probability]) && ratio <= MAX_SPEND_RATIO
        candidate = attempt
        break
      end
    end
    candidate ||= budget_safe_fallback(scraps_price, fixed_prob || DEFAULT_BASE_PROBABILITY)

    roll_cost = ScrapsService.calculate_roll_cost(scraps_price, candidate[:base_probability], nil, candidate[:base_probability])

    {
      scraps_price: scraps_price,
      base_probability: candidate[:base_probability],
      boost_amount: candidate[:boost_amount],
      base_upgrade_cost: candidate[:base_upgrade_cost],
      roll_cost_estimate: roll_cost,
      expected_spend_at_best: (cheapest_spend_ratio(scraps_price, candidate[:base_probability], candidate[:base_upgrade_cost], candidate[:boost_amount]) * scraps_price).round
    }
  end

  def self.chaotic_candidate(scraps_price, fixed_prob)
    prob = fixed_prob || skewed_rand(CHAOS_PROBABILITY_RANGE)
    upgrades_to_max = rand(CHAOS_UPGRADES_TO_MAX_RANGE)
    boost = ((100 - prob).to_f / upgrades_to_max * rand(0.7..1.4)).round.clamp(1, 40)
    upgrade_pct = Math.exp(rand(Math.log(CHAOS_UPGRADE_PERCENT_RANGE.min)..Math.log(CHAOS_UPGRADE_PERCENT_RANGE.max)))
    {
      base_probability: prob,
      boost_amount: boost.to_f,
      base_upgrade_cost: [(scraps_price * upgrade_pct).round, 1].max
    }
  end

  def self.skewed_rand(range)
    span = range.max - range.min
    (range.min + span * (rand**rand(0.6..1.6))).round
  end

  def self.budget_safe_fallback(scraps_price, prob)
    boost = (prob * 0.1).ceil.clamp(1, 10).to_f
    upgrade_cost = [(scraps_price * UPGRADE_START_PERCENT).round, 1].max
    target = min_spend_ratio(scraps_price, prob)
    20.times do
      break if cheapest_spend_ratio(scraps_price, prob, upgrade_cost, boost) >= target
      upgrade_cost = (upgrade_cost * 1.15).ceil
    end
    { base_probability: prob, boost_amount: boost, base_upgrade_cost: upgrade_cost }
  end

  def self.min_spend_ratio(scraps_price, prob)
    return MIN_SPEND_RATIO if scraps_price <= 0
    roll_cost = ScrapsService.calculate_roll_cost(scraps_price, prob, nil, prob)
    no_upgrade_ratio = roll_cost * 100.0 / ScrapsService.compute_roll_threshold(prob) / scraps_price
    [MIN_SPEND_RATIO, no_upgrade_ratio].min
  end

  def self.cheapest_spend_ratio(scraps_price, prob, base_upgrade_cost, boost)
    return Float::INFINITY if scraps_price <= 0
    roll_cost = ScrapsService.calculate_roll_cost(scraps_price, prob, nil, prob)
    max_upgrades = boost > 0 ? ((100 - prob) / boost.to_f).ceil : 0
    cumulative = 0
    best = Float::INFINITY
    (0..max_upgrades).each do |k|
      cumulative += ScrapsService.get_upgrade_cost(scraps_price, k - 1, nil, base_upgrade_cost) if k > 0
      effective = [prob + k * boost, 100].min
      threshold = ScrapsService.compute_roll_threshold(effective)
      best = [best, cumulative + roll_cost * 100.0 / threshold].min
    end
    best / scraps_price
  end

  def self.update_all_items
    conn = ActiveRecord::Base.connection
    items = conn.select_all("SELECT id, price, base_probability FROM shop_items").to_a
    items.each do |item|
      pricing = compute_item_pricing(item["price"].to_f / ScrapsService::SCRAPS_PER_DOLLAR, item["base_probability"]&.to_i)
      conn.execute(<<~SQL)
        UPDATE shop_items
        SET base_upgrade_cost = #{pricing[:base_upgrade_cost]},
            boost_amount = #{pricing[:boost_amount]},
            updated_at = NOW()
        WHERE id = #{item['id'].to_i}
      SQL
    end
    items.length
  end
end
