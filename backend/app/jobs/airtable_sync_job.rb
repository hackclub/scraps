class AirtableSyncJob < ApplicationJob
  queue_as :default

  AIRTABLE_BASE_URL = "https://api.airtable.com/v0"

  def perform
    token = ENV["AIRTABLE_TOKEN"]
    base_id = ENV["AIRTABLE_BASE_ID"]
    table_id = ENV["AIRTABLE_TABLE_ID"] || ENV["AIRTABLE_PROJECTS_TABLE_ID"]

    return unless token.present? && base_id.present? && table_id.present?

    conn = ActiveRecord::Base.connection
    shipped = conn.select_all(<<~SQL).to_a
      SELECT p.id, p.name, p.github_url, p.playable_url, p.description, p.hours, p.hours_override, p.tier, p.tier_override, p.scraps_awarded, p.scraps_paid_at, p.airtable_id, p.user_id,
             u.email, u.slack_id, u.username
      FROM projects p
      INNER JOIN users u ON u.id = p.user_id
      WHERE p.status = 'shipped' AND (p.deleted = 0 OR p.deleted IS NULL)
    SQL

    shipped.each do |project|
      begin
        sync_project_to_airtable(token, base_id, table_id, project, conn)
      rescue StandardError => e
        Rails.logger.error("[AirtableSyncJob] Failed for project #{project['id']}: #{e.message}")
      end
    end
  rescue StandardError => e
    Rails.logger.error("[AirtableSyncJob] Fatal: #{e.message}")
  end

  private

  def sync_project_to_airtable(token, base_id, table_id, project, conn)
    eff_hours = (project["hours_override"] || project["hours"]).to_f
    tier = (project["tier_override"] || project["tier"] || 1).to_i
    mult = ScrapsService::TIER_MULTIPLIERS[tier] || 1.0
    dollar_grant = (eff_hours * ScrapsService::DOLLARS_PER_HOUR * mult * 100).round / 100.0

    fields = {
      "Name" => project["name"],
      "GitHub URL" => project["github_url"],
      "Playable URL" => project["playable_url"],
      "Description" => project["description"],
      "Hours" => eff_hours,
      "Tier" => tier,
      "Dollar Grant" => dollar_grant,
      "Scraps Awarded" => project["scraps_awarded"].to_i,
      "Payout Status" => project["scraps_paid_at"] ? "Paid" : "Pending",
      "Submitter Email" => project["email"],
      "Submitter Slack ID" => project["slack_id"],
      "Submitter Username" => project["username"],
      "Scraps Project ID" => project["id"].to_i
    }

    if project["airtable_id"].present?
      resp = HTTParty.patch(
        "#{AIRTABLE_BASE_URL}/#{base_id}/#{table_id}/#{project['airtable_id']}",
        headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" },
        body: { fields: fields }.to_json
      )
      Rails.logger.warn("[AirtableSyncJob] PATCH failed for project #{project['id']}: #{resp.body}") unless resp.success?
    else
      resp = HTTParty.post(
        "#{AIRTABLE_BASE_URL}/#{base_id}/#{table_id}",
        headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" },
        body: { fields: fields }.to_json
      )
      if resp.success?
        airtable_id = resp.parsed_response["id"]
        conn.execute("UPDATE projects SET airtable_id = #{conn.quote(airtable_id)}, updated_at = NOW() WHERE id = #{project['id'].to_i}") if airtable_id
      else
        Rails.logger.warn("[AirtableSyncJob] POST failed for project #{project['id']}: #{resp.body}")
      end
    end
  end
end
