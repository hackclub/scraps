class AirtableUserSyncJob < ApplicationJob
  queue_as :default

  AIRTABLE_BASE_URL = "https://api.airtable.com/v0"

  # Syncs a user into the "Users" table of the "YSWS - Scraps v2" base
  # (AIRTABLE_BASE_ID / AIRTABLE_USERS_TABLE_ID).
  #
  # scraps `verification_status` -> the "Verification Status" single-select options
  # in that base (verified / unverified / pending / needs_submission).
  VERIFICATION_STATUS_MAP = {
    "verified" => "verified",
    "pending" => "pending",
    "needs_submission" => "needs_submission",
    "ineligible" => "unverified"
  }.freeze

  def perform(user_id, first_name: nil, last_name: nil)
    token = ENV["AIRTABLE_TOKEN"]
    base_id = ENV["AIRTABLE_BASE_ID"]
    table_id = ENV["AIRTABLE_USERS_TABLE_ID"]
    return unless token.present? && base_id.present? && table_id.present?

    conn = ActiveRecord::Base.connection
    user = conn.select_one(<<~SQL)
      SELECT id, email, slack_id, airtable_id, verification_status, ysws_eligible,
             phone, birthday, legal_first_name, legal_last_name,
             address_line1, address_line2, address_city, address_state,
             address_postal_code, address_country
      FROM users WHERE id = #{user_id.to_i}
    SQL
    return unless user

    hackatime_linked = begin
      HackatimeService.get_user(user["email"], user["slack_id"]).present?
    rescue StandardError
      false
    end

    referred_by = conn.select_value(<<~SQL) || "none"
      SELECT ref.username
      FROM referrals r JOIN users ref ON ref.id = r.referrer_id
      WHERE r.referred_user_id = #{user_id.to_i}
      LIMIT 1
    SQL

    fields = {
      "Referred By" => referred_by,
      "Email" => user["email"],
      "First Name" => first_name,
      "Last Name" => last_name,
      "Slack ID" => user["slack_id"],
      "Verification Status" => VERIFICATION_STATUS_MAP[user["verification_status"]],
      "Hackatime Linked?" => hackatime_linked,
      "ysws_eligible" => cast_bool(user["ysws_eligible"]),
      "Phone" => user["phone"],
      "Birthday" => user["birthday"].presence,
      "Legal First Name" => user["legal_first_name"],
      "Legal Last Name" => user["legal_last_name"],
      "Address Line 1" => user["address_line1"],
      "Address Line 2" => user["address_line2"],
      "Address City" => user["address_city"],
      "Address State" => user["address_state"],
      "Address Postal Code" => user["address_postal_code"],
      "Address Country" => user["address_country"]
    }.compact

    headers = { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }

    if user["airtable_id"].present?
      resp = HTTParty.patch(
        "#{AIRTABLE_BASE_URL}/#{base_id}/#{table_id}/#{user['airtable_id']}",
        headers: headers,
        body: { fields: fields, typecast: true }.to_json
      )
      Rails.logger.warn("[AirtableUserSyncJob] PATCH failed for user #{user_id}: #{resp.body}") unless resp.success?
    else
      resp = HTTParty.post(
        "#{AIRTABLE_BASE_URL}/#{base_id}/#{table_id}",
        headers: headers,
        body: { fields: fields, typecast: true }.to_json
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

  private

  # Postgres booleans come back as true/false/"t"/"f"/nil depending on the driver path.
  def cast_bool(value)
    return nil if value.nil?
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
