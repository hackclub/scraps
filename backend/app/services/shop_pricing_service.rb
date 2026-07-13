module ShopPricingService
  PHI = (1 + Math.sqrt(5)) / 2
  DEFAULT_BASE_PROBABILITY = 50
  DEFAULT_PER_ROLL_MULT = 0.05
  DEFAULT_UPGRADE_BUDGET_MULT = 3.0

  # dollar_cost: real dollars the item costs
  # base_prob: optional integer override for base probability (1-99)
  # stock_count: how many are in stock (influences upgrade cost scaling)
  def self.compute_item_pricing(dollar_cost, base_prob = nil, stock_count = 1)
    scraps_price = (dollar_cost * ScrapsService::SCRAPS_PER_DOLLAR).round

    effective_prob = base_prob&.clamp(1, 99) || DEFAULT_BASE_PROBABILITY

    roll_cost = ScrapsService.calculate_roll_cost(scraps_price, effective_prob, nil, effective_prob)

    boost_per_upgrade = (effective_prob * 0.1).ceil.clamp(1, 10).to_f

    upgrade_budget = scraps_price * DEFAULT_UPGRADE_BUDGET_MULT
    base_upgrade_cost = [upgrade_budget / (effective_prob / boost_per_upgrade), 1].max.round

    cost_multiplier = (PHI * 1.5 * (100.0 / effective_prob)).round(4)

    {
      scraps_price: scraps_price,
      base_probability: effective_prob,
      boost_amount: boost_per_upgrade,
      base_upgrade_cost: base_upgrade_cost.to_i,
      cost_multiplier: cost_multiplier,
      roll_cost_estimate: roll_cost
    }
  end

  def self.update_all_items
    conn = ActiveRecord::Base.connection
    items = conn.select_all("SELECT id, price FROM shop_items").to_a
    count = 0
    items.each do |item|
      pricing = compute_item_pricing(item["price"].to_f / ScrapsService::SCRAPS_PER_DOLLAR)
      conn.execute(<<~SQL)
        UPDATE shop_items
        SET base_upgrade_cost = #{pricing[:base_upgrade_cost]},
            cost_multiplier = #{pricing[:cost_multiplier]},
            boost_amount = #{pricing[:boost_amount]},
            updated_at = NOW()
        WHERE id = #{item['id'].to_i}
      SQL
      count += 1
    end
    count
  end
end
