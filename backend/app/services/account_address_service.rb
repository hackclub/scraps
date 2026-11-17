class AccountAddressService
  AUTH_URL = "https://auth.hackclub.com".freeze
  FIELDS = "first_name, legal_first_name, legal_last_name, phone, address_line1, address_line2, address_city, address_state, address_postal_code, address_country".freeze

  def self.user_row(conn, user_id)
    conn.select_one("SELECT #{FIELDS} FROM users WHERE id = #{user_id.to_i}")
  end

  def self.missing?(row)
    return true unless row
    (row["legal_first_name"].presence || row["first_name"]).blank? ||
      row["legal_last_name"].blank? ||
      row["address_line1"].blank? ||
      row["phone"].blank?
  end

  def self.shipping_hash(row)
    return nil if row.nil? || row["address_line1"].blank?
    {
      firstName: row["legal_first_name"].presence || row["first_name"],
      lastName: row["legal_last_name"],
      address1: row["address_line1"],
      address2: row["address_line2"].presence,
      city: row["address_city"],
      state: row["address_state"],
      postalCode: row["address_postal_code"],
      country: row["address_country"],
      phone: row["phone"].presence
    }
  end

  def self.shipping_json(row)
    shipping_hash(row)&.to_json
  end

  def self.resync!(user)
    identity = fetch_identity(user.access_token)
    if identity.nil? && user.refresh_token.present?
      tokens = refresh_tokens(user.refresh_token)
      if tokens && tokens["access_token"]
        user.update!(access_token: tokens["access_token"], refresh_token: tokens["refresh_token"].presence || user.refresh_token)
        identity = fetch_identity(tokens["access_token"])
      end
    end
    return :reauth_required unless identity

    conn = ActiveRecord::Base.connection
    addrs = identity["addresses"]
    addr = addrs.is_a?(Array) && addrs.any? ? (addrs.find { |a| a["primary"] } || addrs.first) : nil
    sets = ["updated_at = NOW()"]
    sets << "phone = #{conn.quote(identity['phone_number'])}" if identity["phone_number"].present?
    legal_first = identity["legal_first_name"].presence || addr&.dig("first_name").presence
    legal_last = identity["legal_last_name"].presence || addr&.dig("last_name").presence
    sets << "legal_first_name = #{conn.quote(legal_first)}" if legal_first
    sets << "legal_last_name = #{conn.quote(legal_last)}" if legal_last
    if addr
      sets << "address_line1 = #{conn.quote(addr['line_1'].presence)}"
      sets << "address_line2 = #{conn.quote(addr['line_2'].presence)}"
      sets << "address_city = #{conn.quote(addr['city'].presence)}"
      sets << "address_state = #{conn.quote(addr['state'].presence)}"
      sets << "address_postal_code = #{conn.quote(addr['postal_code'].presence)}"
      sets << "address_country = #{conn.quote(addr['country'].presence)}"
    end
    conn.execute("UPDATE users SET #{sets.join(', ')} WHERE id = #{user.id.to_i}")
    :ok
  end

  def self.fetch_identity(access_token)
    return nil if access_token.blank?
    resp = HTTParty.get("#{AUTH_URL}/api/v1/me", headers: { "Authorization" => "Bearer #{access_token}" }, timeout: 10)
    resp.success? ? resp.parsed_response["identity"] : nil
  rescue StandardError
    nil
  end

  def self.refresh_tokens(refresh_token)
    resp = HTTParty.post(
      "#{AUTH_URL}/oauth/token",
      headers: { "Content-Type" => "application/x-www-form-urlencoded" },
      body: URI.encode_www_form(
        client_id: ENV["HCAUTH_CLIENT_ID"],
        client_secret: ENV["HCAUTH_CLIENT_SECRET"],
        refresh_token: refresh_token,
        grant_type: "refresh_token"
      ),
      timeout: 10
    )
    resp.success? ? resp.parsed_response : nil
  rescue StandardError
    nil
  end
end
