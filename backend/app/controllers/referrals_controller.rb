class ReferralsController < ApplicationController
  before_action :require_auth, only: %i[me]
  before_action :require_reviewer, only: %i[admin_list]

  # GET /referrals/me — the signed-in user's own code, link and invitees.
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

    render_json({
      code: code,
      link: "#{frontend_url}/?r=#{code}",
      total: referrals.size,
      verified_count: referrals.count { |x| x[:verified] },
      referrals: referrals
    })
  end

  # GET /referrals/leaderboard — public. Top referrers by verified invitees.
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

  # GET /admin/referrals — reviewer+. Every referral pair with conversion state.
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

  def require_reviewer
    return if current_user && %w[reviewer admin creator].include?(current_user.role)
    render_json({ error: "Unauthorized" }, status: :unauthorized)
  end

  def frontend_url
    ENV.fetch("FRONTEND_URL") { "http://localhost:5173" }
  end
end
