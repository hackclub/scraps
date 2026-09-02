class AirtableSyncJob < ApplicationJob
  queue_as :default

  AIRTABLE_BASE_URL = "https://api.airtable.com/v0"

  # Pushes shipped scraps projects into the "YSWS Project Submission" table
  # (AIRTABLE_BASE_ID / AIRTABLE_PROJECTS_TABLE_ID) — the grant-fulfillment pipeline.
  #
  # perform(project_id) syncs one project (called when a project passes review).
  # perform      syncs every shipped project (the 5-minute cron backstop).
  def perform(project_id = nil)
    token = ENV["AIRTABLE_TOKEN"]
    base_id = ENV["AIRTABLE_BASE_ID"]
    table_id = ENV["AIRTABLE_TABLE_ID"] || ENV["AIRTABLE_PROJECTS_TABLE_ID"]
    return unless token.present? && base_id.present? && table_id.present?

    conn = ActiveRecord::Base.connection
    where = +"p.status = 'shipped' AND (p.deleted = 0 OR p.deleted IS NULL)"
    where << " AND p.id = #{project_id.to_i}" if project_id

    conn.select_all(<<~SQL).to_a.each do |project|
      SELECT p.id, p.github_url, p.playable_url, p.description, p.image,
             p.hours, p.hours_override, p.airtable_id,
             (SELECT r.internal_justification FROM reviews r
              WHERE r.project_id = p.id AND r.action = 'approved'
              ORDER BY r.created_at DESC LIMIT 1) AS review_justification,
             u.email, u.slack_id, u.username, u.phone, u.birthday,
             u.legal_first_name, u.legal_last_name,
             u.address_line1, u.address_line2, u.address_city, u.address_state,
             u.address_postal_code, u.address_country
      FROM projects p
      INNER JOIN users u ON u.id = p.user_id
      WHERE #{where}
    SQL
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
    first, last = names_for(project)

    fields = {
      "Code URL" => project["github_url"],
      "Playable URL" => project["playable_url"],
      "Description" => project["description"],
      "GitHub Username" => github_username(project["github_url"]),
      "First Name" => first,
      "Last Name" => last,
      "Email" => project["email"],
      "Slack Username" => project["username"],
      "Phone number" => project["phone"],
      "Birthday" => project["birthday"].presence,
      "Address (Line 1)" => project["address_line1"],
      "Address (Line 2)" => project["address_line2"],
      "City" => project["address_city"],
      "State / Province" => project["address_state"],
      "Country" => project["address_country"],
      "ZIP / Postal Code" => project["address_postal_code"]
    }.compact

    # Always send the scraps-approved hours (the reviewer's "hours to approve"
    # value, stored as hours_override; falls back to the raw logged total).
    approved_hours = project["hours_override"].presence || project["hours"]
    if approved_hours.present?
      fields["Optional - Override Hours Spent"] = approved_hours.to_f
      fields["Optional - Override Hours Spent Justification"] =
        project["review_justification"].presence || "Hours approved by scraps reviewer."
    end

    img = project["image"].to_s
    fields["Screenshot"] = [{ url: img }] if img.start_with?("http")

    headers = { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
    body = { fields: fields, typecast: true }.to_json

    stored_id = project["airtable_id"].presence
    if stored_id
      resp = HTTParty.patch("#{AIRTABLE_BASE_URL}/#{base_id}/#{table_id}/#{stored_id}", headers: headers, body: body)
      return if resp.success?

      # Stored record is gone (base re-pointed, row deleted). Drop the stale id and
      # create a fresh row instead of retrying a dead PATCH forever.
      if resp.body.to_s =~ /NOT_FOUND|MODEL_NOT_FOUND|INVALID_PERMISSIONS_OR_MODEL_NOT_FOUND/
        conn.execute("UPDATE projects SET airtable_id = NULL WHERE id = #{project['id'].to_i}")
        stored_id = nil
      else
        Rails.logger.warn("[AirtableSyncJob] PATCH failed for project #{project['id']}: #{resp.body}")
        return
      end
    end

    resp = HTTParty.post("#{AIRTABLE_BASE_URL}/#{base_id}/#{table_id}", headers: headers, body: body)
    if resp.success?
      airtable_id = resp.parsed_response["id"]
      conn.execute("UPDATE projects SET airtable_id = #{conn.quote(airtable_id)}, updated_at = NOW() WHERE id = #{project['id'].to_i}") if airtable_id
    else
      Rails.logger.warn("[AirtableSyncJob] POST failed for project #{project['id']}: #{resp.body}")
    end
  end

  # Legal name from Hack Club Auth if present, else split the Slack display name.
  def names_for(project)
    return [project["legal_first_name"], project["legal_last_name"]] if project["legal_first_name"].present?

    parts = project["username"].to_s.strip.split(/\s+/)
    return [nil, nil] if parts.empty?
    [parts.first, (parts[1..] || []).join(" ").presence]
  end

  def github_username(url)
    return nil if url.blank?
    m = url.match(%r{github\.com/([^/]+)}i)
    m && m[1].presence
  end
end
