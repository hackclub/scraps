class ScrapPayoutJob < ApplicationJob
  queue_as :default

  HCB_API = "https://hcb.hackclub.com/api/v3"

  def perform
    self.class.perform_now_sync
  end

  def self.perform_now_sync
    token = ENV["HCB_TOKEN"]
    org_slug = ENV["HCB_ORG_SLUG"]

    unless token.present? && org_slug.present?
      Rails.logger.warn("[ScrapPayoutJob] Missing HCB_TOKEN or HCB_ORG_SLUG — skipping payout")
      return { paid_count: 0, total_scraps: 0 }
    end

    conn = ActiveRecord::Base.connection

    pending = conn.select_all(<<~SQL).to_a
      SELECT p.id, p.user_id, p.name, p.scraps_awarded, p.tier, p.tier_override, p.hours, p.hours_override
      FROM projects p
      WHERE p.status = 'shipped'
        AND p.scraps_paid_at IS NULL
        AND p.scraps_awarded > 0
        AND (p.deleted = 0 OR p.deleted IS NULL)
    SQL

    return { paid_count: 0, total_scraps: 0 } if pending.empty?

    user_ids = pending.map { |p| p["user_id"].to_i }.uniq
    users = {}
    conn.select_all("SELECT id, email, slack_id, username FROM users WHERE id IN (#{user_ids.join(',')})").each { |u| users[u["id"].to_i] = u }

    paid_count = 0; total_scraps = 0

    pending.each do |project|
      user = users[project["user_id"].to_i]
      next unless user&.dig("email")

      tier = (project["tier_override"] || project["tier"] || 1).to_i
      mult = ScrapsService::TIER_MULTIPLIERS[tier] || 1.0
      eff_hours = (project["hours_override"] || project["hours"]).to_f
      dollar_amount = (eff_hours * ScrapsService::DOLLARS_PER_HOUR * mult * 100).round

      next unless dollar_amount > 0

      begin
        resp = HTTParty.post(
          "#{HCB_API}/organizations/#{org_slug}/transfers",
          headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" },
          body: {
            recipient_email: user["email"],
            amount_cents: dollar_amount,
            memo: "Scraps payout for project: #{project['name']} (#{eff_hours}h × tier #{tier})"
          }.to_json
        )

        if resp.success?
          conn.execute("UPDATE projects SET scraps_paid_at = NOW(), scraps_paid_amount = #{project['scraps_awarded'].to_i}, updated_at = NOW() WHERE id = #{project['id'].to_i}")
          conn.execute(<<~SQL)
            INSERT INTO project_activity (user_id, project_id, action, created_at)
            VALUES (#{project['user_id'].to_i}, #{project['id'].to_i}, #{conn.quote("paid out #{project['scraps_awarded'].to_i} scraps ($#{dollar_amount.to_f/100})")}, NOW())
          SQL
          paid_count += 1
          total_scraps += project["scraps_awarded"].to_i
        else
          Rails.logger.error("[ScrapPayoutJob] HCB transfer failed for project #{project['id']}: #{resp.body}")
        end
      rescue StandardError => e
        Rails.logger.error("[ScrapPayoutJob] Error paying project #{project['id']}: #{e.message}")
      end
    end

    Rails.logger.info("[ScrapPayoutJob] Completed: #{paid_count} projects, #{total_scraps} scraps")
    { paid_count: paid_count, total_scraps: total_scraps }
  end
end
