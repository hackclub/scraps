module ShopPricingService
  DEFAULT_BASE_PROBABILITY = 50
  DEFAULT_PER_ROLL_MULT = 0.05
  UPGRADE_START_PERCENT = 0.25

  # dollar_cost: real dollars the item costs
  # base_prob: optional integer override for base probability (1-99)
  # stock_count: kept for signature compatibility; no longer affects pricing
  def self.compute_item_pricing(dollar_cost, base_prob = nil, _stock_count = 1)
    scraps_price = (dollar_cost * ScrapsService::SCRAPS_PER_DOLLAR).round
    effective_prob = base_prob&.clamp(1, 99) || DEFAULT_BASE_PROBABILITY

    roll_cost = ScrapsService.calculate_roll_cost(scraps_price, effective_prob, nil, effective_prob)
    boost_per_upgrade = (effective_prob * 0.1).ceil.clamp(1, 10).to_f
    base_upgrade_cost = [(scraps_price * UPGRADE_START_PERCENT).round, 1].max

    {
      scraps_price: scraps_price,
      base_probability: effective_prob,
      boost_amount: boost_per_upgrade,
      base_upgrade_cost: base_upgrade_cost,
      roll_cost_estimate: roll_cost
    }
  end

  def self.update_all_items
    conn = ActiveRecord::Base.connection
    items = conn.select_all("SELECT id, price FROM shop_items").to_a
    items.each do |item|
      pricing = compute_item_pricing(item["price"].to_f / ScrapsService::SCRAPS_PER_DOLLAR)
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
