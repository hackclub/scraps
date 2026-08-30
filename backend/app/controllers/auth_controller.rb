class AuthController < ApplicationController
  HACKCLUB_AUTH_URL = "https://auth.hackclub.com"

  # Community-tier scopes. Once Hack Club HQ grants this OAuth app the elevated
  # scopes, append them here (or set HCAUTH_SCOPE in the env, no deploy needed):
  #   basic_info  -> legal_first_name, legal_last_name, birthday
  #   addresses   -> addresses[] (line_1/2, city, state, postal_code, country)
  #   phone       -> phone_number
  # e.g. "openid email name profile verification_status slack_id basic_info addresses phone"
  OAUTH_SCOPE = ENV.fetch("HCAUTH_SCOPE", "openid email name profile verification_status slack_id")

  def collect_email
    email = params[:email].to_s.strip
    unless email.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
      return render_json({ error: "Invalid email" }, status: :unprocessable_entity)
    end
    UserActivity.create!(email: email, action: "auth_started")
    render_json({ success: true })
  end

  def login
    redirect_to authorization_url, allow_other_host: true
  end

  def callback
    code = params[:code]
    frontend_url = ENV.fetch("FRONTEND_URL") { "http://localhost:5173" }

    unless code
      return redirect_to "#{frontend_url}/auth/error?reason=auth-failed", allow_other_host: true
    end

    tokens = exchange_code_for_tokens(code)
    unless tokens
      return redirect_to "#{frontend_url}/auth/error?reason=auth-failed", allow_other_host: true
    end

    me_response = fetch_user_identity(tokens["access_token"])
    unless me_response
      return redirect_to "#{frontend_url}/auth/error?reason=auth-failed", allow_other_host: true
    end

    identity = me_response["identity"]

    if identity["verification_status"] == "needs_submission"
      return redirect_to "#{frontend_url}/auth/error?reason=needs-verification", allow_other_host: true
    end

    if identity["verification_status"] == "ineligible"
      return redirect_to "#{frontend_url}/auth/error?reason=not-eligible", allow_other_host: true
    end

    begin
      user = create_or_update_user(identity, tokens)
    rescue => e
      msg = e.message
      if msg == "not-eligible"
        return redirect_to "#{frontend_url}/auth/error?reason=not-eligible", allow_other_host: true
      end
      return redirect_to "#{frontend_url}/auth/error?reason=auth-failed", allow_other_host: true
    end

    UserActivity.create!(user_id: user.id, email: identity["primary_email"], action: "auth_completed")

    AirtableUserSyncJob.perform_later(user.id, first_name: @airtable_first_name, last_name: @airtable_last_name)

    if user.role == "banned"
      return redirect_to "https://fraud.land", allow_other_host: true
    end

    # Check Hackatime ban
    begin
      ht_user = HackatimeService.get_user(identity["primary_email"], identity["slack_id"])
      if ht_user && ht_user[:banned]
        return redirect_to "https://fraud.land", allow_other_host: true
      end
    rescue StandardError => e
      Rails.logger.error("[AUTH] Failed to check Hackatime ban: #{e.message}")
    end

    token = SecureRandom.uuid
    expires_at = 7.days.from_now
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(
        ["INSERT INTO sessions (token, user_id, expires_at, created_at) VALUES (?, ?, ?, NOW())",
         token, user.id, expires_at.utc.iso8601]
      )
    )

    is_dev = Rails.env.development?
    cookie_opts = {
      value: token,
      httponly: true,
      path: "/",
      expires: expires_at,
      same_site: :lax
    }
    cookie_opts[:secure] = true unless is_dev
    cookies["session"] = cookie_opts

    redirect_url = "#{frontend_url}/dashboard"
    render html: "<!DOCTYPE html><html><head><meta http-equiv='refresh' content='0;url=#{redirect_url}'></head><body>Redirecting...</body></html>".html_safe,
           content_type: "text/html"
  end

  def me
    unless current_user
      return render_json({ user: nil })
    end

    if current_user.role == "banned"
      return render_json({ user: nil, banned: true })
    end

    # The tutorial bonus is awarded once in UserController#complete_tutorial;
    # no need to re-check (a locking transaction) on every profile fetch.
    balance = ScrapsService.get_user_scraps_balance(current_user.id)
    render_json({
      user: {
        id: current_user.id,
        username: current_user.username,
        email: current_user.email,
        avatar: current_user.avatar,
        slack_id: current_user.slack_id,
        scraps: balance[:balance],
        scraps_pending: balance[:pending],
        next_payout_date: ScrapsService.next_payout_date.iso8601,
        role: current_user.role,
        tutorial_completed: current_user.tutorial_completed
      }
    })
  end

  def logout
    token = request.cookies["session"]
    if token.present?
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(["DELETE FROM sessions WHERE token = ?", token])
      )
      cookies.delete("session")
    end
    render_json({ success: true })
  end

  private

  def authorization_url
    params = URI.encode_www_form(
      client_id: ENV["HCAUTH_CLIENT_ID"],
      redirect_uri: ENV.fetch("HCAUTH_REDIRECT_URI") { "http://localhost:3000/api/auth/callback/hackclub" },
      response_type: "code",
      scope: OAUTH_SCOPE
    )
    "#{HACKCLUB_AUTH_URL}/oauth/authorize?#{params}"
  end

  def exchange_code_for_tokens(code)
    resp = HTTParty.post(
      "#{HACKCLUB_AUTH_URL}/oauth/token",
      headers: { "Content-Type" => "application/x-www-form-urlencoded" },
      body: URI.encode_www_form(
        client_id: ENV["HCAUTH_CLIENT_ID"],
        client_secret: ENV["HCAUTH_CLIENT_SECRET"],
        redirect_uri: ENV.fetch("HCAUTH_REDIRECT_URI") { "http://localhost:3000/api/auth/callback/hackclub" },
        code: code,
        grant_type: "authorization_code"
      )
    )
    resp.success? ? resp.parsed_response : nil
  rescue StandardError
    nil
  end

  def fetch_user_identity(access_token)
    resp = HTTParty.get(
      "#{HACKCLUB_AUTH_URL}/api/v1/me",
      headers: { "Authorization" => "Bearer #{access_token}" }
    )
    resp.success? ? resp.parsed_response : nil
  rescue StandardError
    nil
  end

  def create_or_update_user(identity, tokens)
    if identity["ysws_eligible"] == false
      raise "not-eligible"
    end

    username = nil
    avatar_url = nil

    # Primary source: Cachet (cachet.dunkirk.sh), a public proxy/cache for Slack
    # profile pictures and display names. Needs no bot scope, unlike users.info.
    if identity["slack_id"].present?
      cachet = fetch_cachet_profile(identity["slack_id"])
      if cachet
        username = cachet["displayName"].presence || cachet["realName"].presence
        # Store the Cachet permalink (302s to the current image) rather than the
        # slack-edge URL, so the avatar never goes stale.
        avatar_url = "https://cachet.dunkirk.sh/users/#{identity['slack_id']}/r" if cachet["imageUrl"].present?
      end
    end

    # Secondary: a direct users.info lookup, only useful if the bot token has the
    # users:read scope. Also the source of the Airtable first/last name split.
    if (username.nil? || avatar_url.nil?) && identity["slack_id"].present? && ENV["SLACK_BOT_TOKEN"].present?
      profile = fetch_slack_profile(identity["slack_id"])
      if profile
        username ||= profile["display_name"].presence || profile["real_name"]
        avatar_url ||= profile["image_512"] || profile["image_192"] || profile["image_72"]
        @airtable_first_name = profile["first_name"]
        @airtable_last_name = profile["last_name"]
      end
    end

    # Final fallback: the name from Hack Club Auth (there is no avatar there).
    username ||= [identity["first_name"], identity["last_name"]]
                 .map { |s| s.to_s.strip.presence }.compact.join(" ").presence
    @airtable_first_name ||= identity["first_name"]
    @airtable_last_name ||= identity["last_name"]

    conn = ActiveRecord::Base.connection
    # Only present once HQ grants `basic_info` / `addresses` / `phone` scopes; nil otherwise.
    addr = primary_address(identity)

    existing = conn.select_one(
      "SELECT id FROM users WHERE sub = #{conn.quote(identity['id'])}"
    )

    if existing
      conn.execute(<<~SQL)
        UPDATE users SET
          username = COALESCE(#{conn.quote(username)}, username),
          email = COALESCE(#{conn.quote(identity['primary_email'])}, email),
          slack_id = #{conn.quote(identity['slack_id'])},
          avatar = COALESCE(#{conn.quote(avatar_url)}, avatar),
          access_token = #{conn.quote(tokens['access_token'])},
          refresh_token = #{conn.quote(tokens['refresh_token'])},
          id_token = #{conn.quote(tokens['id_token'])},
          verification_status = #{conn.quote(identity['verification_status'])},
          ysws_eligible = #{conn.quote(identity['ysws_eligible'])},
          phone = COALESCE(#{conn.quote(identity['phone_number'])}, phone),
          birthday = COALESCE(#{conn.quote(identity['birthday'])}, birthday),
          legal_first_name = COALESCE(#{conn.quote(identity['legal_first_name'])}, legal_first_name),
          legal_last_name = COALESCE(#{conn.quote(identity['legal_last_name'])}, legal_last_name),
          address_line1 = COALESCE(#{conn.quote(addr['line_1'])}, address_line1),
          address_line2 = COALESCE(#{conn.quote(addr['line_2'])}, address_line2),
          address_city = COALESCE(#{conn.quote(addr['city'])}, address_city),
          address_state = COALESCE(#{conn.quote(addr['state'])}, address_state),
          address_postal_code = COALESCE(#{conn.quote(addr['postal_code'])}, address_postal_code),
          address_country = COALESCE(#{conn.quote(addr['country'])}, address_country),
          updated_at = NOW()
        WHERE sub = #{conn.quote(identity['id'])}
      SQL
      User.find(existing["id"])
    else
      conn.execute(<<~SQL)
        INSERT INTO users (
          sub, slack_id, username, email, avatar, access_token, refresh_token, id_token,
          verification_status, ysws_eligible, phone, birthday, legal_first_name, legal_last_name,
          address_line1, address_line2, address_city, address_state, address_postal_code, address_country,
          role, tutorial_completed, language, created_at, updated_at
        )
        VALUES (
          #{conn.quote(identity['id'])},
          #{conn.quote(identity['slack_id'])},
          #{conn.quote(username)},
          #{conn.quote(identity['primary_email'] || '')},
          #{conn.quote(avatar_url)},
          #{conn.quote(tokens['access_token'])},
          #{conn.quote(tokens['refresh_token'])},
          #{conn.quote(tokens['id_token'])},
          #{conn.quote(identity['verification_status'])},
          #{conn.quote(identity['ysws_eligible'])},
          #{conn.quote(identity['phone_number'])},
          #{conn.quote(identity['birthday'])},
          #{conn.quote(identity['legal_first_name'])},
          #{conn.quote(identity['legal_last_name'])},
          #{conn.quote(addr['line_1'])},
          #{conn.quote(addr['line_2'])},
          #{conn.quote(addr['city'])},
          #{conn.quote(addr['state'])},
          #{conn.quote(addr['postal_code'])},
          #{conn.quote(addr['country'])},
          'member', false, 'en', NOW(), NOW()
        )
      SQL
      User.find_by!(sub: identity["id"])
    end
  end

  # The user's primary address from Hack Club Auth (identity["addresses"]), or {}.
  # Empty until the OAuth app is granted the `addresses` scope.
  def primary_address(identity)
    addrs = identity["addresses"]
    return {} unless addrs.is_a?(Array) && addrs.any?
    (addrs.find { |a| a["primary"] } || addrs.first || {})
  end

  def fetch_slack_profile(slack_id)
    resp = HTTParty.get(
      "https://slack.com/api/users.info?user=#{slack_id}",
      headers: { "Authorization" => "Bearer #{ENV['SLACK_BOT_TOKEN']}" }
    )
    return nil unless resp.success?
    data = resp.parsed_response
    return nil unless data["ok"]
    data.dig("user", "profile")
  rescue StandardError
    nil
  end

  # https://cachet.dunkirk.sh/swagger — { displayName, realName, pronouns, imageUrl, ... }
  def fetch_cachet_profile(slack_id)
    resp = HTTParty.get("https://cachet.dunkirk.sh/users/#{slack_id}", timeout: 5)
    return nil unless resp.success?
    data = resp.parsed_response
    data.is_a?(Hash) ? data : nil
  rescue StandardError
    nil
  end
end
