module ReferralService
  # A referred user counts as "converted" once Hack Club Auth reports them fully
  # verified. Tracking only — there is no scraps reward.
  VERIFIED_STATUSES = %w[verified].freeze

  # Lazily assign and persist a share code for the user.
  def self.share_code_for(user)
    return user.referral_code if user.referral_code.present?

    conn = ActiveRecord::Base.connection
    code = nil
    loop do
      code = SecureRandom.alphanumeric(8).downcase
      break unless conn.select_value("SELECT 1 FROM users WHERE referral_code = #{conn.quote(code)} LIMIT 1")
    end
    conn.execute("UPDATE users SET referral_code = #{conn.quote(code)}, updated_at = NOW() WHERE id = #{user.id.to_i}")
    user.referral_code = code
    code
  end

  # Record that `referred_user` (a brand-new account) signed up via `code`.
  # No-op if the code is unknown, self-referral, banned referrer, or the user wassw
  # already referred once.
  def self.attach(referred_user, code)
    code = code.to_s.strip.downcase
    return if code.blank?
    conn = ActiveRecord::Base.connection
    referrer = conn.select_one(
      "SELECT id, role FROM users WHERE referral_code = #{conn.quote(code)} LIMIT 1"
    )
    return unless referrer
    return if referrer["id"].to_i == referred_user.id
    return if referrer["role"] == "banned"
    return if Referral.exists?(referred_user_id: referred_user.id)

    Referral.create!(referrer_id: referrer["id"].to_i, referred_user_id: referred_user.id, code: code)
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
