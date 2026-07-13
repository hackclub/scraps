class AirtableUserSyncJob < ApplicationJob
  queue_as :default

  AIRTABLE_BASE_URL = "https://api.airtable.com/v0"

  def perform(user_id, first_name: nil, last_name: nil)
    token = ENV["AIRTABLE_TOKEN"]
    base_id = ENV["AIRTABLE_BASE_ID"]
    table_id = ENV["AIRTABLE_USERS_TABLE_ID"]
    return unless token.present? && base_id.present? && table_id.present?

    conn = ActiveRecord::Base.connection
    user = conn.select_one("SELECT id, email, slack_id, airtable_id FROM users WHERE id = #{user_id.to_i}")
    return unless user

    fields = {
      "email" => user["email"],
      "slack_id" => user["slack_id"],
      "first_name" => first_name,
      "last_name" => last_name
    }.compact

    if user["airtable_id"].present?
      resp = HTTParty.patch(
        "#{AIRTABLE_BASE_URL}/#{base_id}/#{table_id}/#{user['airtable_id']}",
        headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" },
        body: { fields: fields }.to_json
      )
      Rails.logger.warn("[AirtableUserSyncJob] PATCH failed for user #{user_id}: #{resp.body}") unless resp.success?
    else
      resp = HTTParty.post(
        "#{AIRTABLE_BASE_URL}/#{base_id}/#{table_id}",
        headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" },
        body: { fields: fields }.to_json
      )
      if resp.success?
        airtable_id = resp.parsed_response["id"]
        conn.execute("UPDATE users SET airtable_id = #{conn.quote(airtable_id)}, updated_at = NOW() WHERE id = #{user_id.to_i}") if airtable_id
      else
        Rails.logger.warn("[AirtableUserSyncJob] POST failed for user #{user_id}: #{resp.body}")
      end
    end
  rescue StandardError => e
    Rails.logger.error("[AirtableUserSyncJob] Fatal for user #{user_id}: #{e.message}")
  end
end
