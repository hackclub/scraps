class LeaderboardController < ApplicationController
  def index
    sort_by = params[:sortBy].to_s.presence || "scraps"
    conn = ActiveRecord::Base.connection

    if sort_by == "hours"
      rows = conn.select_all(<<~SQL).to_a
        SELECT u.id, u.username, u.avatar, u.email, u.slack_id,
          COALESCE((SELECT SUM(scraps_awarded) FROM projects WHERE user_id = u.id AND scraps_paid_at IS NOT NULL AND status != 'permanently_rejected'), 0) AS scraps_earned,
          COALESCE((SELECT SUM(amount) FROM user_bonuses WHERE user_id = u.id), 0) AS scraps_bonus,
          COALESCE((SELECT SUM(total_price) FROM shop_orders WHERE user_id = u.id AND status NOT IN ('cancelled','deleted')), 0) AS scraps_shop_spent,
          COALESCE((SELECT SUM(cost) FROM refinery_spending_history WHERE user_id = u.id), 0) AS scraps_refinery_spent,
          COALESCE(SUM(p.hours_override), 0) + COALESCE(SUM(CASE WHEN p.hours_override IS NULL THEN p.hours ELSE 0 END), 0) AS total_hours,
          COUNT(p.id) AS project_count
        FROM users u
        LEFT JOIN projects p ON p.user_id = u.id AND (p.deleted = 0 OR p.deleted IS NULL) AND p.status != 'permanently_rejected'
        WHERE u.role != 'banned' AND u.hackatime_banned = false
        GROUP BY u.id
        ORDER BY total_hours DESC
        LIMIT 20
      SQL
    else
      rows = conn.select_all(<<~SQL).to_a
        SELECT u.id, u.username, u.avatar, u.email, u.slack_id,
          COALESCE((SELECT SUM(scraps_awarded) FROM projects WHERE user_id = u.id AND scraps_paid_at IS NOT NULL AND status != 'permanently_rejected'), 0) AS scraps_earned,
          COALESCE((SELECT SUM(amount) FROM user_bonuses WHERE user_id = u.id), 0) AS scraps_bonus,
          COALESCE((SELECT SUM(total_price) FROM shop_orders WHERE user_id = u.id AND status NOT IN ('cancelled','deleted')), 0) AS scraps_shop_spent,
          COALESCE((SELECT SUM(cost) FROM refinery_spending_history WHERE user_id = u.id), 0) AS scraps_refinery_spent,
          COALESCE(SUM(p.hours_override), 0) + COALESCE(SUM(CASE WHEN p.hours_override IS NULL THEN p.hours ELSE 0 END), 0) AS total_hours,
          COUNT(p.id) AS project_count
        FROM users u
        LEFT JOIN projects p ON p.user_id = u.id AND (p.deleted = 0 OR p.deleted IS NULL) AND p.status != 'permanently_rejected'
        WHERE u.role != 'banned' AND u.hackatime_banned = false
        GROUP BY u.id
        ORDER BY (
          COALESCE((SELECT SUM(scraps_awarded) FROM projects WHERE user_id = u.id AND scraps_paid_at IS NOT NULL AND status != 'permanently_rejected'), 0) +
          COALESCE((SELECT SUM(amount) FROM user_bonuses WHERE user_id = u.id), 0) -
          COALESCE((SELECT SUM(total_price) FROM shop_orders WHERE user_id = u.id AND status NOT IN ('cancelled','deleted')), 0) -
          COALESCE((SELECT SUM(cost) FROM refinery_spending_history WHERE user_id = u.id), 0)
        ) DESC
        LIMIT 20
      SQL
    end

    filtered = rows.first(10)

    render_json(filtered.each_with_index.map do |u, i|
      earned = u["scraps_earned"].to_f.round
      bonus = u["scraps_bonus"].to_f.round
      shop_spent = u["scraps_shop_spent"].to_f.round
      refinery_spent = u["scraps_refinery_spent"].to_f.round
      {
        rank: i + 1,
        id: u["id"].to_i,
        username: u["username"],
        avatar: u["avatar"],
        hours: u["total_hours"].to_f.round(1),
        scraps: earned + bonus - shop_spent - refinery_spent,
        scraps_earned: earned,
        project_count: u["project_count"].to_i
      }
    end)
  end

  def views
    conn = ActiveRecord::Base.connection
    rows = conn.select_all(<<~SQL).to_a
      SELECT p.id, p.name, p.image, p.views, p.user_id,
             u.email AS user_email, u.slack_id AS user_slack_id, u.role AS user_role
      FROM projects p
      INNER JOIN users u ON u.id = p.user_id
      WHERE p.status = 'shipped'
        AND (p.deleted = 0 OR p.deleted IS NULL)
        AND u.role != 'banned'
        AND u.hackatime_banned = false
      ORDER BY p.views DESC
      LIMIT 20
    SQL

    filtered = rows.first(10)

    user_ids = filtered.map { |r| r["user_id"].to_i }.uniq
    users = {}
    if user_ids.any?
      conn.select_all("SELECT id, username, avatar FROM users WHERE id IN (#{user_ids.join(',')})").each do |u|
        users[u["id"].to_i] = u
      end
    end

    render_json(filtered.each_with_index.map do |p, i|
      owner = users[p["user_id"].to_i]
      {
        rank: i + 1,
        id: p["id"].to_i,
        name: p["name"],
        image: p["image"],
        views: p["views"].to_i,
        owner: owner ? { id: owner["id"].to_i, username: owner["username"], avatar: owner["avatar"] } : nil
      }
    end)
  end

  def probability_leaders
    conn = ActiveRecord::Base.connection

    items = conn.select_all("SELECT id, name, image, base_probability FROM shop_items").to_a
    boosts = conn.select_all("SELECT user_id, shop_item_id, COALESCE(SUM(boost_amount), 0) AS boost_percent FROM refinery_orders GROUP BY user_id, shop_item_id").to_a
    penalties = conn.select_all("SELECT user_id, shop_item_id, probability_multiplier FROM shop_penalties").to_a

    boost_map = {}
    boosts.each { |b| boost_map["#{b['user_id']}-#{b['shop_item_id']}"] = b["boost_percent"].to_f }

    penalty_map = {}
    penalties.each { |p| penalty_map["#{p['user_id']}-#{p['shop_item_id']}"] = p["probability_multiplier"].to_f }

    user_ids = (boosts.map { |b| b["user_id"].to_i } + penalties.map { |p| p["user_id"].to_i }).uniq
    users = {}
    if user_ids.any?
      conn.select_all("SELECT id, username, avatar FROM users WHERE id IN (#{user_ids.join(',')})").each do |u|
        users[u["id"].to_i] = u
      end
    end

    render_json(items.map do |item|
      base_prob = item["base_probability"].to_f
      top_user = nil
      top_probability = base_prob

      user_ids.each do |uid|
        boost = boost_map["#{uid}-#{item['id']}"] || 0
        penalty_mult = penalty_map["#{uid}-#{item['id']}"] || 100
        adjusted_base = (base_prob * penalty_mult / 100.0).floor
        effective = [adjusted_base + boost, 100].min
        if effective > top_probability
          top_probability = effective
          top_user = users[uid]
        end
      end

      {
        item_id: item["id"].to_i,
        item_name: item["name"],
        item_image: item["image"],
        base_probability: base_prob,
        top_user: top_user ? { id: top_user["id"].to_i, username: top_user["username"], avatar: top_user["avatar"] } : nil,
        effective_probability: top_probability
      }
    end)
  end
end
