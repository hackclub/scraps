class ShopController < ApplicationController
  RETAINED_ITEMS_CAP = 2

  def items
    conn = ActiveRecord::Base.connection
    # The item list + heart counts are the same for everyone; only the per-user
    # overlay below varies. Cache the shared part off the remote-DB hot path.
    rows = Rails.cache.fetch("shop:items:v1", expires_in: 60.seconds) do
      conn.select_all(<<~SQL).to_a
        SELECT si.*,
          (SELECT COUNT(*) FROM shop_hearts WHERE shop_item_id = si.id) AS heart_count
        FROM shop_items si
      SQL
    end

    render_json(hydrate_items(rows))
  end

  def daily_picks
    conn = ActiveRecord::Base.connection
    ids = Rails.cache.fetch("shop:daily:#{Date.current}", expires_in: 1.hour) do
      pool = conn.select_all("SELECT id FROM shop_items WHERE count != 0").map { |r| r["id"].to_i }
      seed = Digest::MD5.hexdigest(Date.current.to_s).to_i(16) % (2**31)
      pool.shuffle(random: Random.new(seed)).first(5)
    end

    rows = ids.any? ? conn.select_all(<<~SQL).to_a : []
      SELECT si.*, (SELECT COUNT(*) FROM shop_hearts WHERE shop_item_id = si.id) AS heart_count
      FROM shop_items si WHERE si.id IN (#{ids.join(',')})
    SQL

    render_json({ date: Date.current.to_s, items: hydrate_items(rows) })
  end

  def retained_items
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    conn = ActiveRecord::Base.connection
    ids = conn.select_all("SELECT shop_item_id FROM shop_retained_items WHERE user_id = #{current_user.id} ORDER BY created_at ASC").map { |r| r["shop_item_id"].to_i }
    rows = ids.any? ? conn.select_all(<<~SQL).to_a : []
      SELECT si.*, (SELECT COUNT(*) FROM shop_hearts WHERE shop_item_id = si.id) AS heart_count
      FROM shop_items si WHERE si.id IN (#{ids.join(',')})
    SQL

    render_json({ cap: RETAINED_ITEMS_CAP, used: ids.length, items: hydrate_items(rows) })
  end

  def retain_item
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    item_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    return render_json({ error: "Item not found" }, status: :not_found) unless conn.select_one("SELECT 1 FROM shop_items WHERE id = #{item_id}")

    count = conn.select_one("SELECT COUNT(*) AS cnt FROM shop_retained_items WHERE user_id = #{current_user.id}")["cnt"].to_i
    return render_json({ error: "Your permanent shop is full" }, status: :unprocessable_entity) if count >= RETAINED_ITEMS_CAP

    already = conn.select_one("SELECT 1 FROM shop_retained_items WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
    return render_json({ error: "Already in your permanent shop" }, status: :unprocessable_entity) if already

    conn.execute("INSERT INTO shop_retained_items (user_id, shop_item_id, created_at) VALUES (#{current_user.id}, #{item_id}, NOW())")
    render_json({ success: true })
  end

  def unretain_item
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    item_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    conn.execute("DELETE FROM shop_retained_items WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
    render_json({ success: true })
  end

  def gachapons
    conn = ActiveRecord::Base.connection
    gachapons = conn.select_all("SELECT * FROM shop_gachapons ORDER BY created_at ASC").to_a
    return render_json([]) if gachapons.empty?

    gachapon_ids = gachapons.map { |g| g["id"].to_i }
    links = conn.select_all("SELECT gachapon_id, shop_item_id FROM shop_gachapon_items WHERE gachapon_id IN (#{gachapon_ids.join(',')})").to_a
    item_ids = links.map { |l| l["shop_item_id"].to_i }.uniq
    items_by_id = if item_ids.any?
      rows = conn.select_all("SELECT id, name, image, count FROM shop_items WHERE id IN (#{item_ids.join(',')})").to_a
      rows.each_with_object({}) { |r, h| h[r["id"].to_i] = { id: r["id"].to_i, name: r["name"], image: r["image"], count: r["count"].to_i } }
    else
      {}
    end

    items_by_gachapon = Hash.new { |h, k| h[k] = [] }
    links.each { |l| items_by_gachapon[l["gachapon_id"].to_i] << items_by_id[l["shop_item_id"].to_i] }

    render_json(gachapons.map { |g|
      {
        id: g["id"].to_i,
        name: g["name"],
        description: g["description"],
        image: g["image"],
        price: g["price"].to_i,
        items: items_by_gachapon[g["id"].to_i].compact
      }
    })
  end

  def purchase_gachapon
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    gachapon_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    gachapon = conn.select_one("SELECT * FROM shop_gachapons WHERE id = #{gachapon_id}")
    return render_json({ error: "Not found" }, status: :not_found) unless gachapon

    price = gachapon["price"].to_i
    phone = conn.select_one("SELECT phone FROM users WHERE id = #{current_user.id}")&.dig("phone")

    begin
      order_row = ActiveRecord::Base.transaction do
        conn.execute("SELECT 1 FROM users WHERE id = #{current_user.id} FOR UPDATE")

        affordable = ScrapsService.can_afford?(current_user.id, price)
        unless affordable
          bal = ScrapsService.get_user_scraps_balance(current_user.id)[:balance]
          raise({ type: "insufficient_funds", balance: bal }.to_s)
        end

        item_ids = conn.select_all("SELECT shop_item_id FROM shop_gachapon_items WHERE gachapon_id = #{gachapon_id}").map { |r| r["shop_item_id"].to_i }
        raise({ type: "empty_gachapon" }.to_s) if item_ids.empty?

        available = conn.select_all("SELECT * FROM shop_items WHERE id IN (#{item_ids.join(',')}) AND count != 0 FOR UPDATE").to_a
        raise({ type: "out_of_stock" }.to_s) if available.empty?

        won_item = available.sample
        won_item_id = won_item["id"].to_i
        conn.execute("UPDATE shop_items SET count = count - 1, updated_at = NOW() WHERE id = #{won_item_id}") unless infinite_stock?(won_item["count"])

        order = conn.select_one(<<~SQL)
          INSERT INTO shop_orders (user_id, shop_item_id, quantity, price_per_item, total_price, shipping_address, phone, status, order_type, created_at, updated_at)
          VALUES (#{current_user.id}, #{won_item_id}, 1, #{price}, #{price}, NULL, #{conn.quote(phone)}, 'pending', 'gachapon', NOW(), NOW())
          RETURNING *
        SQL

        { order: order, item: won_item }
      end

      render_json({
        success: true,
        order: {
          id: order_row[:order]["id"].to_i,
          item_name: order_row[:item]["name"],
          item_image: order_row[:item]["image"],
          total_price: price,
          status: order_row[:order]["status"]
        }
      })
    rescue ActiveRecord::StatementInvalid => e
      msg = e.message
      return render_json({ error: "Insufficient scraps", required: price }, status: :unprocessable_entity) if msg.include?("insufficient_funds")
      return render_json({ error: "This gachapon has no items in it" }, status: :unprocessable_entity) if msg.include?("empty_gachapon")
      return render_json({ error: "All items in this gachapon are sold out" }, status: :unprocessable_entity) if msg.include?("out_of_stock")
      raise
    end
  end

  def show_item
    conn = ActiveRecord::Base.connection
    item = conn.select_one(<<~SQL)
      SELECT si.*, (SELECT COUNT(*) FROM shop_hearts WHERE shop_item_id = si.id) AS heart_count
      FROM shop_items si WHERE si.id = #{params[:id].to_i}
    SQL
    return render_json({ error: "Item not found" }, status: :not_found) unless item

    hearted = false
    boost_pct = 0.0
    penalty_mult = 100.0

    if current_user
      uid = current_user.id
      hearted = conn.select_one("SELECT 1 FROM shop_hearts WHERE user_id = #{uid} AND shop_item_id = #{params[:id].to_i}").present?
      b = conn.select_one("SELECT COALESCE(SUM(boost_amount),0) AS bp FROM refinery_orders WHERE user_id = #{uid} AND shop_item_id = #{params[:id].to_i}")
      boost_pct = b["bp"].to_f if b
      p = conn.select_one("SELECT probability_multiplier FROM shop_penalties WHERE user_id = #{uid} AND shop_item_id = #{params[:id].to_i}")
      penalty_mult = p["probability_multiplier"].to_f if p
    end

    base_prob = item["base_probability"].to_f
    adj_base = (base_prob * penalty_mult / 100.0).floor

    render_json(item_base_h(item).merge(
      user_boost_percent: boost_pct,
      adjusted_base_probability: adj_base,
      effective_probability: [adj_base + boost_pct, 100].min,
      user_hearted: hearted
    ))
  end

  def heart
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    item_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    return render_json({ error: "Item not found" }, status: :not_found) unless conn.select_one("SELECT 1 FROM shop_items WHERE id = #{item_id}")

    result = conn.select_one(<<~SQL)
      WITH del AS (
        DELETE FROM shop_hearts WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id} RETURNING 1
      ),
      ins AS (
        INSERT INTO shop_hearts (user_id, shop_item_id)
        SELECT #{current_user.id}, #{item_id}
        WHERE NOT EXISTS (SELECT 1 FROM del)
        ON CONFLICT DO NOTHING
        RETURNING 1
      )
      SELECT EXISTS(SELECT 1 FROM ins) AS hearted
    SQL

    hearted = result["hearted"] == true || result["hearted"] == "t" || result["hearted"] == 1
    count_r = conn.select_one("SELECT COUNT(*) AS cnt FROM shop_hearts WHERE shop_item_id = #{item_id}")
    render_json({ hearted: hearted, heart_count: count_r["cnt"].to_i })
  end

  def categories
    rows = ActiveRecord::Base.connection.select_all("SELECT DISTINCT category FROM shop_items").to_a
    render_json(rows.map { |r| r["category"] })
  end

  def balance
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user
    render_json(ScrapsService.get_user_scraps_balance(current_user.id))
  end

  def purchase
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    item_id = params[:id].to_i
    quantity = (params[:quantity] || 1).to_i
    return render_json({ error: "Invalid quantity" }, status: :unprocessable_entity) unless quantity >= 1

    conn = ActiveRecord::Base.connection
    item = conn.select_one("SELECT * FROM shop_items WHERE id = #{item_id}")
    return render_json({ error: "Item not found" }, status: :not_found) unless item
    infinite = infinite_stock?(item["count"])

    if !infinite && item["count"].to_i < quantity
      return render_json({ error: "Not enough stock available" }, status: :unprocessable_entity)
    end

    total_price = item["price"].to_i * quantity
    phone = conn.select_one("SELECT phone FROM users WHERE id = #{current_user.id}")&.dig("phone")

    begin
      order_row = ActiveRecord::Base.transaction do
        conn.execute("SELECT 1 FROM users WHERE id = #{current_user.id} FOR UPDATE")

        affordable = ScrapsService.can_afford?(current_user.id, total_price)
        unless affordable
          bal = ScrapsService.get_user_scraps_balance(current_user.id)[:balance]
          raise({ type: "insufficient_funds", balance: bal }.to_s)
        end

        unless infinite
          locked = conn.select_one("SELECT count FROM shop_items WHERE id = #{item_id} FOR UPDATE")
          unless locked && locked["count"].to_i >= quantity
            raise({ type: "out_of_stock" }.to_s)
          end

          conn.execute("UPDATE shop_items SET count = count - #{quantity}, updated_at = NOW() WHERE id = #{item_id}")
        end

        conn.select_one(<<~SQL)
          INSERT INTO shop_orders (user_id, shop_item_id, quantity, price_per_item, total_price, shipping_address, phone, status, order_type, created_at, updated_at)
          VALUES (#{current_user.id}, #{item_id}, #{quantity}, #{item['price'].to_i}, #{total_price}, NULL, #{conn.quote(phone)}, 'pending', 'purchase', NOW(), NOW())
          RETURNING *
        SQL
      end

      render_json({
        success: true,
        order: {
          id: order_row["id"].to_i,
          item_name: item["name"],
          quantity: order_row["quantity"].to_i,
          total_price: order_row["total_price"].to_i,
          status: order_row["status"]
        }
      })
    rescue ActiveRecord::StatementInvalid => e
      msg = e.message
      if msg.include?("insufficient_funds")
        return render_json({ error: "Insufficient scraps", required: total_price }, status: :unprocessable_entity)
      end
      if msg.include?("out_of_stock")
        return render_json({ error: "Not enough stock" }, status: :unprocessable_entity)
      end
      raise
    end
  end

  def try_luck
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    item_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    item = conn.select_one("SELECT * FROM shop_items WHERE id = #{item_id}")
    return render_json({ error: "Item not found" }, status: :not_found) unless item
    infinite = infinite_stock?(item["count"])
    return render_json({ error: "Out of stock" }, status: :unprocessable_entity) if !infinite && item["count"].to_i < 1

    phone = conn.select_one("SELECT phone FROM users WHERE id = #{current_user.id}")&.dig("phone")

    begin
      roll_result = ActiveRecord::Base.transaction do
        conn.execute("SELECT 1 FROM users WHERE id = #{current_user.id} FOR UPDATE")

        unless infinite
          locked = conn.select_one("SELECT count FROM shop_items WHERE id = #{item_id} FOR UPDATE")
          raise({ type: "out_of_stock" }.to_s) unless locked && locked["count"].to_i >= 1
        end

        boost_row = conn.select_one("SELECT COALESCE(SUM(boost_amount),0) AS bp FROM refinery_orders WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        boost_pct = boost_row["bp"].to_f

        penalty_row = conn.select_one("SELECT probability_multiplier FROM shop_penalties WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        penalty_mult = penalty_row ? penalty_row["probability_multiplier"].to_f : 100.0

        base_prob = item["base_probability"].to_f
        adj_base = (base_prob * penalty_mult / 100.0).floor
        effective_prob = [adj_base + boost_pct, 100].min

        base_roll_cost = ScrapsService.calculate_roll_cost(
          item["price"].to_i,
          effective_prob,
          item["roll_cost_override"]&.to_i,
          base_prob
        )

        roll_count_row = conn.select_one("SELECT COUNT(*) AS cnt FROM shop_rolls WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        prev_rolls = roll_count_row["cnt"].to_i
        per_roll_mult = (item["per_roll_multiplier"] || 0.05).to_f
        roll_cost = (base_roll_cost * (1 + per_roll_mult * prev_rolls)).round

        balance = ScrapsService.get_user_scraps_balance(current_user.id)[:balance]
        unless balance >= roll_cost
          raise({ type: "insufficient_funds", balance: balance, cost: roll_cost }.to_s)
        end

        rolled = rand(1..100)
        threshold = ScrapsService.compute_roll_threshold(effective_prob)
        won = rolled <= threshold
        # Don't reveal the roll was actually a win-zone miss — shift display value past effective_prob
        display_rolled = (!won && rolled <= effective_prob) ? rand((effective_prob.to_i + 1)..100) : rolled

        conn.execute(<<~SQL)
          INSERT INTO shop_rolls (user_id, shop_item_id, rolled, threshold, won, created_at)
          VALUES (#{current_user.id}, #{item_id}, #{rolled}, #{threshold}, #{won}, NOW())
        SQL

        if won
          conn.execute("UPDATE shop_items SET count = count - 1, updated_at = NOW() WHERE id = #{item_id}") unless infinite

          order_row = conn.select_one(<<~SQL)
            INSERT INTO shop_orders (user_id, shop_item_id, quantity, price_per_item, total_price, shipping_address, phone, status, order_type, created_at, updated_at)
            VALUES (#{current_user.id}, #{item_id}, 1, #{roll_cost}, #{roll_cost}, NULL, #{conn.quote(phone)}, 'pending', 'luck_win', NOW(), NOW())
            RETURNING id
          SQL

          conn.execute("DELETE FROM refinery_orders WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")

          existing_penalty = conn.select_one("SELECT probability_multiplier FROM shop_penalties WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
          if existing_penalty
            new_mult = [1, (existing_penalty["probability_multiplier"].to_f / 2).floor].max
            conn.execute("UPDATE shop_penalties SET probability_multiplier = #{new_mult}, updated_at = NOW() WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
          else
            conn.execute("INSERT INTO shop_penalties (user_id, shop_item_id, probability_multiplier, created_at, updated_at) VALUES (#{current_user.id}, #{item_id}, 50, NOW(), NOW())")
          end

          { won: true, order_id: order_row["id"].to_i, effective_probability: effective_prob, rolled: display_rolled, roll_cost: roll_cost }
        else
          consolation_row = conn.select_one(<<~SQL)
            INSERT INTO shop_orders (user_id, shop_item_id, quantity, price_per_item, total_price, shipping_address, phone, status, order_type, notes, created_at, updated_at)
            VALUES (#{current_user.id}, #{item_id}, 1, #{roll_cost}, #{roll_cost}, NULL, #{conn.quote(phone)}, 'pending', 'consolation', #{conn.quote("Consolation scrap paper - rolled #{display_rolled}, needed #{effective_prob.to_i} or less")}, NOW(), NOW())
            RETURNING id
          SQL

          if penalty_mult < 100
            recovered = [100, penalty_mult + 5].min
            conn.execute("UPDATE shop_penalties SET probability_multiplier = #{recovered}, updated_at = NOW() WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
          end

          { won: false, consolation_order_id: consolation_row["id"].to_i, effective_probability: effective_prob, rolled: display_rolled, roll_cost: roll_cost, penalty_recovered: penalty_mult < 100 }
        end
      end

      if roll_result[:won]
        if ENV["SLACK_BOT_TOKEN"].present?
          SlackService.notify_shop_win(
            token: ENV["SLACK_BOT_TOKEN"],
            user_slack_id: current_user.slack_id,
            item_name: item["name"],
            item_image: item["image"].to_s.presence,
            frontend_url: ENV.fetch("FRONTEND_URL") { "http://localhost:5173" },
            activity_channel_id: ENV["SLACK_ACTIVITY_CHANNEL_ID"]
          ) rescue nil
        end
        render_json({ success: true, won: true, order_id: roll_result[:order_id], effective_probability: roll_result[:effective_probability], rolled: roll_result[:rolled], roll_cost: roll_result[:roll_cost], refinery_reset: true, probability_halved: true })
      else
        render_json({ success: true, won: false, consolation_order_id: roll_result[:consolation_order_id], effective_probability: roll_result[:effective_probability], rolled: roll_result[:rolled], roll_cost: roll_result[:roll_cost] })
      end
    rescue ActiveRecord::StatementInvalid => e
      msg = e.message
      return render_json({ error: "Insufficient scraps" }, status: :unprocessable_entity) if msg.include?("insufficient_funds")
      return render_json({ error: "Out of stock" }, status: :unprocessable_entity) if msg.include?("out_of_stock")
      raise
    end
  end

  def upgrade_probability
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    item_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    item = conn.select_one("SELECT * FROM shop_items WHERE id = #{item_id}")
    return render_json({ error: "Item not found" }, status: :not_found) unless item
    infinite = infinite_stock?(item["count"])
    return render_json({ error: "Item is out of stock" }, status: :unprocessable_entity) if !infinite && item["count"].to_i < 1

    begin
      result = ActiveRecord::Base.transaction do
        conn.execute("SELECT 1 FROM users WHERE id = #{current_user.id} FOR UPDATE")

        unless infinite
          stock = conn.select_one("SELECT count FROM shop_items WHERE id = #{item_id} FOR UPDATE")
          raise({ type: "out_of_stock" }.to_s) unless stock && stock["count"].to_i >= 1
        end

        boost_row = conn.select_one("SELECT COALESCE(SUM(boost_amount),0) AS bp FROM refinery_orders WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        current_boost = boost_row["bp"].to_f

        penalty_row = conn.select_one("SELECT probability_multiplier FROM shop_penalties WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        penalty_mult = penalty_row ? penalty_row["probability_multiplier"].to_f : 100.0

        adj_base = (item["base_probability"].to_f * penalty_mult / 100.0).floor
        max_boost = 100 - adj_base

        raise({ type: "max_probability" }.to_s) if current_boost >= max_boost

        upgrade_count_row = conn.select_one("SELECT COUNT(*) AS cnt FROM refinery_orders WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        upgrade_count = upgrade_count_row["cnt"].to_i

        spent_row = conn.select_one("SELECT COALESCE(SUM(cost),0) AS total FROM refinery_spending_history WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        actual_spent = spent_row["total"].to_f

        cost = ScrapsService.get_upgrade_cost(item["price"].to_i, upgrade_count, actual_spent, item["base_upgrade_cost"]&.to_i)
        raise({ type: "max_upgrades" }.to_s) if cost.nil?

        affordable = ScrapsService.can_afford?(current_user.id, cost)
        unless affordable
          bal = ScrapsService.get_user_scraps_balance(current_user.id)[:balance]
          raise({ type: "insufficient_funds", balance: bal, cost: cost }.to_s)
        end

        boost_amount = item["boost_amount"].to_f
        new_boost = current_boost + boost_amount

        conn.execute("INSERT INTO refinery_orders (user_id, shop_item_id, cost, boost_amount, created_at, updated_at) VALUES (#{current_user.id}, #{item_id}, #{cost}, #{boost_amount}, NOW(), NOW())")
        conn.execute("INSERT INTO refinery_spending_history (user_id, shop_item_id, cost, created_at) VALUES (#{current_user.id}, #{item_id}, #{cost}, NOW())")

        new_upgrade_count = upgrade_count + 1
        next_cost = (new_boost >= max_boost) ? nil : ScrapsService.get_upgrade_cost(item["price"].to_i, new_upgrade_count, actual_spent + cost, item["base_upgrade_cost"]&.to_i)

        { boost_percent: new_boost, boost_amount: boost_amount, next_cost: next_cost, effective_probability: [adj_base + new_boost, 100].min }
      end

      render_json(result)
    rescue ActiveRecord::StatementInvalid => e
      msg = e.message
      return render_json({ error: "Already at maximum probability" }, status: :unprocessable_entity) if msg.include?("max_probability")
      return render_json({ error: "Upgrade budget exhausted" }, status: :unprocessable_entity) if msg.include?("max_upgrades")
      return render_json({ error: "Insufficient scraps" }, status: :unprocessable_entity) if msg.include?("insufficient_funds")
      raise
    end
  end

  def item_leaderboard
    item_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    item = conn.select_one("SELECT id, base_probability FROM shop_items WHERE id = #{item_id}")
    return render_json({ error: "Item not found" }, status: :not_found) unless item

    rows = conn.select_all(<<~SQL).to_a
      SELECT ro.user_id, u.username, u.avatar, COALESCE(SUM(ro.boost_amount),0) AS boost_pct
      FROM refinery_orders ro
      INNER JOIN users u ON u.id = ro.user_id
      WHERE ro.shop_item_id = #{item_id}
      GROUP BY ro.user_id, u.username, u.avatar
      ORDER BY SUM(ro.boost_amount) DESC
      LIMIT 20
    SQL

    base_prob = item["base_probability"].to_f
    render_json(rows.map { |r|
      boost = r["boost_pct"].to_f
      {
        user_id: r["user_id"].to_i,
        username: r["username"],
        avatar: r["avatar"],
        boost_percent: boost,
        effective_probability: [base_prob + boost, 100].min
      }
    })
  end

  def item_buyers
    item_id = params[:id].to_i
    rows = ActiveRecord::Base.connection.select_all(<<~SQL).to_a
      SELECT so.user_id, u.username, u.avatar, so.quantity, so.created_at AS purchased_at
      FROM shop_orders so
      INNER JOIN users u ON u.id = so.user_id
      WHERE so.shop_item_id = #{item_id}
        AND so.order_type != 'consolation'
        AND so.status != 'deleted'
      ORDER BY so.created_at DESC
      LIMIT 20
    SQL

    render_json(rows.map { |r|
      { user_id: r["user_id"].to_i, username: r["username"], avatar: r["avatar"], quantity: r["quantity"].to_i, purchased_at: r["purchased_at"] }
    })
  end

  def item_hearts
    item_id = params[:id].to_i
    rows = ActiveRecord::Base.connection.select_all(<<~SQL).to_a
      SELECT sh.user_id, u.username, u.avatar, sh.created_at
      FROM shop_hearts sh
      INNER JOIN users u ON u.id = sh.user_id
      WHERE sh.shop_item_id = #{item_id}
      ORDER BY sh.created_at DESC
      LIMIT 20
    SQL

    render_json(rows.map { |r| { user_id: r["user_id"].to_i, username: r["username"], avatar: r["avatar"], created_at: r["created_at"] } })
  end

  # Sourced from the users table (kept in sync from Hack Club Auth on every
  # login, see AuthController), not a live call to the identity API — that
  # API scopes legal name/phone to the individual address record, which made
  # this randomly come back with holes ("undefined undefined") whenever a
  # user hadn't filled those specific fields in on auth.hackclub.com.
  def addresses
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    conn = ActiveRecord::Base.connection
    u = conn.select_one(<<~SQL)
      SELECT first_name, legal_first_name, legal_last_name, phone,
             address_line1, address_line2, address_city, address_state,
             address_postal_code, address_country
      FROM users WHERE id = #{current_user.id}
    SQL
    return render_json([]) unless u
    return render_json([]) if u["address_line1"].blank? && u["address_city"].blank?

    render_json([{
      id: "account",
      first_name: u["legal_first_name"].presence || u["first_name"],
      last_name: u["legal_last_name"],
      line_1: u["address_line1"],
      line_2: u["address_line2"],
      city: u["address_city"],
      state: u["address_state"],
      postal_code: u["address_postal_code"],
      country: u["address_country"],
      phone_number: u["phone"],
      primary: true
    }])
  rescue StandardError => e
    Rails.logger.error("[SHOP/addresses] #{e.message}")
    render_json([])
  end

  def orders
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    rows = ActiveRecord::Base.connection.select_all(<<~SQL).to_a
      SELECT so.id, so.quantity, so.price_per_item, so.total_price, so.status, so.order_type,
             so.shipping_address, so.tracking_number, so.is_fulfilled, so.created_at,
             si.id AS item_id, si.name AS item_name, si.image AS item_image
      FROM shop_orders so
      INNER JOIN shop_items si ON si.id = so.shop_item_id
      WHERE so.user_id = #{current_user.id}
      ORDER BY so.created_at DESC
    SQL

    render_json(rows.map { |r|
      {
        id: r["id"].to_i,
        quantity: r["quantity"].to_i,
        price_per_item: r["price_per_item"].to_i,
        total_price: r["total_price"].to_i,
        status: r["status"],
        order_type: r["order_type"],
        shipping_address: r["shipping_address"],
        tracking_number: r["tracking_number"],
        is_fulfilled: r["is_fulfilled"],
        created_at: r["created_at"],
        item_id: r["item_id"].to_i,
        item_name: r["item_name"],
        item_image: r["item_image"]
      }
    })
  end

  def pending_address
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    rows = ActiveRecord::Base.connection.select_all(<<~SQL).to_a
      SELECT so.id, so.quantity, so.price_per_item, so.total_price, so.status, so.order_type, so.created_at,
             si.id AS item_id, si.name AS item_name, si.image AS item_image
      FROM shop_orders so
      INNER JOIN shop_items si ON si.id = so.shop_item_id
      WHERE so.user_id = #{current_user.id} AND so.shipping_address IS NULL
      ORDER BY so.created_at DESC
    SQL

    render_json(rows.map { |r|
      { id: r["id"].to_i, quantity: r["quantity"].to_i, price_per_item: r["price_per_item"].to_i, total_price: r["total_price"].to_i, status: r["status"], order_type: r["order_type"], created_at: r["created_at"], item_id: r["item_id"].to_i, item_name: r["item_name"], item_image: r["item_image"] }
    })
  end

  def set_address
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    order_id = params[:id].to_i
    shipping_address = params[:shippingAddress].to_s.strip
    return render_json({ error: "Shipping address is required" }, status: :unprocessable_entity) if shipping_address.blank?

    conn = ActiveRecord::Base.connection
    order = conn.select_one("SELECT user_id FROM shop_orders WHERE id = #{order_id}")
    return render_json({ error: "Order not found" }, status: :not_found) unless order
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless order["user_id"].to_i == current_user.id

    conn.execute("UPDATE shop_orders SET shipping_address = #{conn.quote(shipping_address)}, updated_at = NOW() WHERE id = #{order_id}")
    render_json({ success: true })
  end

  def refinery_undo
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    item_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    item = conn.select_one("SELECT * FROM shop_items WHERE id = #{item_id}")
    return render_json({ error: "Item not found" }, status: :not_found) unless item

    begin
      result = ActiveRecord::Base.transaction do
        conn.execute("SELECT 1 FROM users WHERE id = #{current_user.id} FOR UPDATE")

        last_purchase = conn.select_one(<<~SQL)
          SELECT created_at FROM shop_orders
          WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}
            AND order_type IN ('purchase','luck_win')
          ORDER BY created_at DESC LIMIT 1
        SQL

        order_query = if last_purchase
          "SELECT * FROM refinery_orders WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id} AND created_at > '#{last_purchase['created_at']}' ORDER BY created_at DESC LIMIT 1"
        else
          "SELECT * FROM refinery_orders WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id} ORDER BY created_at DESC LIMIT 1"
        end

        order = conn.select_one(order_query)
        unless order
          error_msg = last_purchase ? "Cannot undo refinery upgrades from before your last purchase" : "No refinery upgrades to undo"
          return render_json({ error: error_msg }, status: :unprocessable_entity)
        end

        conn.execute("DELETE FROM refinery_orders WHERE id = #{order['id'].to_i}")

        history = conn.select_one(<<~SQL)
          SELECT id FROM refinery_spending_history
          WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id} AND cost = #{order['cost'].to_i}
          ORDER BY created_at DESC LIMIT 1
        SQL
        conn.execute("DELETE FROM refinery_spending_history WHERE id = #{history['id'].to_i}") if history

        new_boost_row = conn.select_one("SELECT COALESCE(SUM(boost_amount),0) AS bp, COUNT(*) AS cnt FROM refinery_orders WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        new_boost = new_boost_row["bp"].to_f
        new_count = new_boost_row["cnt"].to_i

        penalty_row = conn.select_one("SELECT probability_multiplier FROM shop_penalties WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        penalty_mult = penalty_row ? penalty_row["probability_multiplier"].to_f : 100.0
        adj_base = (item["base_probability"].to_f * penalty_mult / 100.0).floor
        max_boost = 100 - adj_base

        spent_row = conn.select_one("SELECT COALESCE(SUM(cost),0) AS total FROM refinery_spending_history WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        actual_spent = spent_row["total"].to_f

        next_cost = (new_boost >= max_boost) ? nil : ScrapsService.get_upgrade_cost(item["price"].to_i, new_count, actual_spent, item["base_upgrade_cost"]&.to_i)

        { boost_percent: new_boost, upgrade_count: new_count, refunded_cost: order["cost"].to_i, effective_probability: [adj_base + new_boost, 100].min, next_cost: next_cost }
      end

      render_json(result) unless performed?
    rescue StandardError => e
      render_json({ error: "Failed to undo refinery upgrade" }, status: :internal_server_error)
    end
  end

  def refinery_undo_all
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    item_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    item = conn.select_one("SELECT * FROM shop_items WHERE id = #{item_id}")
    return render_json({ error: "Item not found" }, status: :not_found) unless item

    begin
      result = ActiveRecord::Base.transaction do
        conn.execute("SELECT 1 FROM users WHERE id = #{current_user.id} FOR UPDATE")

        last_purchase = conn.select_one(<<~SQL)
          SELECT created_at FROM shop_orders
          WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}
            AND order_type IN ('purchase','luck_win')
          ORDER BY created_at DESC LIMIT 1
        SQL

        orders_query = if last_purchase
          "SELECT * FROM refinery_orders WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id} AND created_at > '#{last_purchase['created_at']}'"
        else
          "SELECT * FROM refinery_orders WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}"
        end

        orders = conn.select_all(orders_query).to_a
        unless orders.any?
          error_msg = last_purchase ? "Cannot undo refinery upgrades from before your last purchase" : "No refinery upgrades to undo"
          return render_json({ error: error_msg }, status: :unprocessable_entity)
        end

        total_refunded = 0
        orders.each do |order|
          conn.execute("DELETE FROM refinery_orders WHERE id = #{order['id'].to_i}")
          history = conn.select_one("SELECT id FROM refinery_spending_history WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id} AND cost = #{order['cost'].to_i} ORDER BY created_at DESC LIMIT 1")
          conn.execute("DELETE FROM refinery_spending_history WHERE id = #{history['id'].to_i}") if history
          total_refunded += order["cost"].to_i
        end

        new_boost_row = conn.select_one("SELECT COALESCE(SUM(boost_amount),0) AS bp, COUNT(*) AS cnt FROM refinery_orders WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        new_boost = new_boost_row["bp"].to_f
        new_count = new_boost_row["cnt"].to_i

        penalty_row = conn.select_one("SELECT probability_multiplier FROM shop_penalties WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        penalty_mult = penalty_row ? penalty_row["probability_multiplier"].to_f : 100.0
        adj_base = (item["base_probability"].to_f * penalty_mult / 100.0).floor
        max_boost = 100 - adj_base

        spent_row = conn.select_one("SELECT COALESCE(SUM(cost),0) AS total FROM refinery_spending_history WHERE user_id = #{current_user.id} AND shop_item_id = #{item_id}")
        actual_spent = spent_row["total"].to_f

        next_cost = (new_boost >= max_boost) ? nil : ScrapsService.get_upgrade_cost(item["price"].to_i, new_count, actual_spent, item["base_upgrade_cost"]&.to_i)

        { boost_percent: new_boost, upgrade_count: new_count, refunded_cost: total_refunded, undone_count: orders.length, effective_probability: [adj_base + new_boost, 100].min, next_cost: next_cost }
      end

      render_json(result) unless performed?
    rescue StandardError => e
      render_json({ error: "Failed to undo refinery upgrades" }, status: :internal_server_error)
    end
  end

  private

  def infinite_stock?(count)
    count.to_i < 0
  end

  def parse_size_variants(raw)
    return raw if raw.is_a?(Array)
    JSON.parse(raw.to_s.presence || "[]")
  rescue JSON::ParserError
    []
  end

  def hydrate_items(rows)
    return rows.map { |item| item_without_user(item) } unless current_user

    conn = ActiveRecord::Base.connection
    uid = current_user.id
    ids = rows.map { |r| r["id"].to_i }
    return [] if ids.empty?

    hearts = conn.select_all("SELECT shop_item_id FROM shop_hearts WHERE user_id = #{uid} AND shop_item_id IN (#{ids.join(',')})").map { |r| r["shop_item_id"].to_i }.to_set
    boosts = {}
    conn.select_all("SELECT shop_item_id, COALESCE(SUM(boost_amount),0) AS boost_pct, COUNT(*) AS upg_count FROM refinery_orders WHERE user_id = #{uid} AND shop_item_id IN (#{ids.join(',')}) GROUP BY shop_item_id").each do |r|
      boosts[r["shop_item_id"].to_i] = { boost: r["boost_pct"].to_f, count: r["upg_count"].to_i }
    end
    penalties = {}
    conn.select_all("SELECT shop_item_id, probability_multiplier FROM shop_penalties WHERE user_id = #{uid} AND shop_item_id IN (#{ids.join(',')})").each do |r|
      penalties[r["shop_item_id"].to_i] = r["probability_multiplier"].to_f
    end
    roll_counts = {}
    conn.select_all("SELECT shop_item_id, COUNT(*) AS cnt FROM shop_rolls WHERE user_id = #{uid} AND shop_item_id IN (#{ids.join(',')}) GROUP BY shop_item_id").each do |r|
      roll_counts[r["shop_item_id"].to_i] = r["cnt"].to_i
    end
    refinery_spent = {}
    conn.select_all("SELECT shop_item_id, COALESCE(SUM(cost),0) AS total FROM refinery_spending_history WHERE user_id = #{uid} AND shop_item_id IN (#{ids.join(',')}) GROUP BY shop_item_id").each do |r|
      refinery_spent[r["shop_item_id"].to_i] = r["total"].to_f
    end

    rows.map { |item| item_with_user_data(item, hearts, boosts, penalties, roll_counts, refinery_spent) }
  end

  def item_base_h(item)
    {
      id: item["id"].to_i,
      name: item["name"],
      image: item["image"],
      description: item["description"],
      price: item["price"].to_i,
      category: item["category"],
      count: item["count"].to_i,
      base_probability: item["base_probability"].to_f,
      base_upgrade_cost: item["base_upgrade_cost"]&.to_i,
      boost_amount: item["boost_amount"].to_f,
      roll_cost_override: item["roll_cost_override"]&.to_i,
      per_roll_multiplier: (item["per_roll_multiplier"] || 0.05).to_f,
      heart_count: item["heart_count"].to_i,
      size_variants: parse_size_variants(item["size_variants"]).select { |v| v["count"].to_i > 0 },
      created_at: item["created_at"],
      updated_at: item["updated_at"]
    }
  end

  def item_without_user(item)
    base_prob = item["base_probability"].to_f
    roll_cost = ScrapsService.calculate_roll_cost(item["price"].to_i, base_prob, item["roll_cost_override"]&.to_i, base_prob)
    display_roll_cost = roll_cost.round

    item_base_h(item).merge(
      user_boost_percent: 0,
      upgrade_count: 0,
      adjusted_base_probability: base_prob,
      effective_probability: base_prob,
      roll_count: 0,
      user_hearted: false,
      next_upgrade_cost: item["base_upgrade_cost"]&.to_i,
      display_roll_cost: display_roll_cost
    )
  end

  def item_with_user_data(item, hearts, boosts, penalties, roll_counts, refinery_spent)
    item_id = item["id"].to_i
    base_prob = item["base_probability"].to_f
    boost_data = boosts[item_id] || { boost: 0.0, count: 0 }
    penalty_mult = penalties[item_id] || 100.0
    adj_base = (base_prob * penalty_mult / 100.0).floor
    max_boost = 100 - adj_base
    boost_pct = boost_data[:boost]
    upg_count = boost_data[:count]
    actual_spent = refinery_spent[item_id] || 0.0
    effective_prob = [adj_base + boost_pct, 100].min

    next_upgrade_cost = (boost_pct >= max_boost) ? nil : ScrapsService.get_upgrade_cost(item["price"].to_i, upg_count, actual_spent, item["base_upgrade_cost"]&.to_i)

    base_roll_cost = ScrapsService.calculate_roll_cost(item["price"].to_i, effective_prob, item["roll_cost_override"]&.to_i, base_prob)
    prev_rolls = roll_counts[item_id] || 0
    per_roll_mult = (item["per_roll_multiplier"] || 0.05).to_f
    display_roll_cost = (base_roll_cost * (1 + per_roll_mult * prev_rolls)).round

    item_base_h(item).merge(
      user_boost_percent: boost_pct,
      upgrade_count: upg_count,
      adjusted_base_probability: adj_base,
      effective_probability: effective_prob,
      roll_count: prev_rolls,
      user_hearted: hearts.include?(item_id),
      next_upgrade_cost: next_upgrade_cost,
      display_roll_cost: display_roll_cost
    )
  end
end
