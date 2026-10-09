class ReferralsController < ApplicationController
  before_action :require_auth, only: %i[me leaderboard claim]
  before_action :require_reviewer, only: %i[admin_list]

  MILESTONES = [
    { key: "shop_slot_1", count: 1, label: "extra shop slot", kind: "slot" },
    { key: "shop_slot_3", count: 3, label: "another shop slot", kind: "slot" },
    { key: "daily_picks", count: 5, label: "+2 daily picks", kind: "daily" },
    { key: "stickers", count: 10, label: "custom stickers", kind: "item", shop_item_id: 71, icon: "question" },
    { key: "special_shirt", count: 20, label: "special shirt", kind: "item", shop_item_id: 70 }
  ].freeze

  # GET /referrals/me: the signed-in user's own code, link and invitees.
  def me
    code = ReferralService.share_code_for(current_user)
    conn = ActiveRecord::Base.connection
    rows = conn.select_all(<<~SQL).to_a
      SELECT u.id, u.username, u.avatar, u.verification_status, r.created_at
      FROM referrals r
      JOIN users u ON u.id = r.referred_user_id
      WHERE r.referrer_id = #{current_user.id.to_i}
      ORDER BY r.created_at DESC
    SQL

    referrals = rows.map do |r|
      {
        username: r["username"],
        avatar: r["avatar"],
        verified: ReferralService::VERIFIED_STATUSES.include?(r["verification_status"]),
        created_at: r["created_at"]
      }
    end

    verified_count = referrals.count { |x| x[:verified] }
    claimed = conn.select_values("SELECT reward FROM referral_reward_claims WHERE user_id = #{current_user.id.to_i}")

    render_json({
      code: code,
      link: "#{frontend_url}/?r=#{code}",
      total: referrals.size,
      verified_count: verified_count,
      referrals: referrals,
      milestones: milestones_for(conn, verified_count, claimed)
    })
  end

  def claim
    milestone = MILESTONES.find { |m| m[:key] == params[:reward].to_s }
    return render_json({ error: "Unknown reward" }, status: :not_found) unless milestone

    conn = ActiveRecord::Base.connection
    result = ActiveRecord::Base.transaction do
      conn.execute("SELECT 1 FROM users WHERE id = #{current_user.id.to_i} FOR UPDATE")

      if conn.select_value("SELECT 1 FROM referral_reward_claims WHERE user_id = #{current_user.id.to_i} AND reward = #{conn.quote(milestone[:key])}")
        next({ error: "Already claimed", status: :conflict })
      end

      verified = verified_count_for(conn, current_user.id)
      if verified < milestone[:count]
        next({ error: "You need #{milestone[:count]} verified referrals (you have #{verified})", status: :forbidden })
      end

      order_id = nil
      if milestone[:kind] == "slot"
        conn.execute("UPDATE users SET retained_cap_bonus = COALESCE(retained_cap_bonus, 0) + 1, updated_at = NOW() WHERE id = #{current_user.id.to_i}")
      elsif milestone[:kind] == "item"
        item_id = milestone[:shop_item_id].to_i
        unless conn.select_value("SELECT 1 FROM shop_items WHERE id = #{item_id}")
          raise ActiveRecord::Rollback
        end
        order_id = conn.select_value(<<~SQL).to_i
          INSERT INTO shop_orders (user_id, shop_item_id, quantity, price_per_item, total_price, shipping_address, phone, status, order_type, notes, created_at, updated_at)
          VALUES (#{current_user.id.to_i}, #{item_id}, 1, 0, 0, NULL, #{conn.quote(current_user.phone)}, 'pending', 'referral_reward',
                  #{conn.quote("Referral reward: #{milestone[:count]} verified referrals")}, NOW(), NOW())
          RETURNING id
        SQL
      end

      conn.execute(<<~SQL)
        INSERT INTO referral_reward_claims (user_id, reward, shop_order_id, created_at, updated_at)
        VALUES (#{current_user.id.to_i}, #{conn.quote(milestone[:key])}, #{order_id || 'NULL'}, NOW(), NOW())
      SQL

      { success: true, reward: milestone[:key], order_id: order_id }
    end

    return render_json({ error: "Reward item is not available right now" }, status: :service_unavailable) if result.nil?
    return render_json({ error: result[:error] }, status: result[:status]) if result[:error]
    render_json(result)
  end

  # GET /referrals/leaderboard: public. Top referrers by verified invitees.
  def leaderboard
    conn = ActiveRecord::Base.connection
    rows = conn.select_all(<<~SQL).to_a
      SELECT ref.id, ref.username, ref.avatar,
        COUNT(r.id) AS total,
        COUNT(*) FILTER (WHERE ru.verification_status = 'verified') AS verified_count
      FROM referrals r
      JOIN users ref ON ref.id = r.referrer_id
      JOIN users ru  ON ru.id = r.referred_user_id
      WHERE ref.role != 'banned'
      GROUP BY ref.id, ref.username, ref.avatar
      HAVING COUNT(*) FILTER (WHERE ru.verification_status = 'verified') > 0
      ORDER BY verified_count DESC, total DESC, ref.id ASC
      LIMIT 20
    SQL

    render_json(rows.each_with_index.map do |r, i|
      {
        rank: i + 1,
        username: r["username"],
        avatar: r["avatar"],
        verified_count: r["verified_count"].to_i,
        total: r["total"].to_i
      }
    end)
  end

  # GET /admin/referrals: reviewer+. Every referral pair with conversion state.
  def admin_list
    conn = ActiveRecord::Base.connection
    rows = conn.select_all(<<~SQL).to_a
      SELECT r.id, r.code, r.created_at,
        ref.id AS referrer_id, ref.username AS referrer_username, ref.avatar AS referrer_avatar,
        ru.id AS referred_id, ru.username AS referred_username, ru.avatar AS referred_avatar,
        ru.verification_status AS referred_status
      FROM referrals r
      JOIN users ref ON ref.id = r.referrer_id
      JOIN users ru  ON ru.id = r.referred_user_id
      ORDER BY r.created_at DESC
    SQL

    entries = rows.map do |r|
      {
        id: r["id"],
        code: r["code"],
        created_at: r["created_at"],
        referrer: { id: r["referrer_id"], username: r["referrer_username"], avatar: r["referrer_avatar"] },
        referred: {
          id: r["referred_id"], username: r["referred_username"], avatar: r["referred_avatar"],
          verification_status: r["referred_status"],
          verified: ReferralService::VERIFIED_STATUSES.include?(r["referred_status"])
        }
      }
    end

    render_json({
      total: entries.size,
      verified_total: entries.count { |e| e[:referred][:verified] },
      entries: entries
    })
  end

  private

  def verified_count_for(conn, user_id)
    conn.select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM referrals r
      JOIN users u ON u.id = r.referred_user_id
      WHERE r.referrer_id = #{user_id.to_i} AND u.verification_status IN (#{ReferralService::VERIFIED_STATUSES.map { |v| conn.quote(v) }.join(',')})
    SQL
  end

  def milestones_for(conn, verified_count, claimed)
    item_ids = MILESTONES.filter_map { |m| m[:shop_item_id] }
    images = conn.select_all("SELECT id, image FROM shop_items WHERE id IN (#{item_ids.join(',')})").to_a
                 .to_h { |r| [r["id"].to_i, r["image"]] }
    MILESTONES.map do |m|
      {
        key: m[:key],
        count: m[:count],
        label: m[:label],
        kind: m[:kind],
        image: m[:icon] ? nil : (m[:image] || (m[:shop_item_id] && images[m[:shop_item_id]])),
        icon: m[:icon],
        reached: verified_count >= m[:count],
        claimed: claimed.include?(m[:key])
      }
    end
  end

  def require_reviewer
    return if current_user && %w[reviewer admin creator].include?(current_user.role)
    render_json({ error: "Unauthorized" }, status: :unauthorized)
  end

  def frontend_url
    ENV.fetch("FRONTEND_URL") { "http://localhost:5173" }
  end
end
