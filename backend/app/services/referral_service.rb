module ReferralService
  # A referred user counts as "converted" (and triggers the referrer's reward)
  # once Hack Club Auth reports them fully verified.
  VERIFIED_STATUSES = %w[verified].freeze

  # Scraps awarded to the referrer when their invitee verifies. 0 = tracking only.
  def self.reward_amount
    ENV.fetch("REFERRAL_REWARD_SCRAPS", "0").to_i
  end

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
  # No-op if the code is unknown, self-referral, banned referrer, or the user was
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
    sync_reward(referred_user)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Grant the referrer their reward once the invitee is verified. Idempotent.
  def self.sync_reward(referred_user)
    return if reward_amount <= 0
    return unless VERIFIED_STATUSES.include?(referred_user.verification_status)

    referral = Referral.find_by(referred_user_id: referred_user.id, rewarded: false)
    return unless referral

    UserBonus.create!(
      user_id: referral.referrer_id,
      amount: reward_amount,
      reason: "Referral: #{referred_user.username || referred_user.email} verified"
    )
    referral.update!(rewarded: true, reward_amount: reward_amount)
  end
end
