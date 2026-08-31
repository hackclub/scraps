class LoginAllowlistEntry < ApplicationRecord
  TYPES = %w[email slack_id].freeze

  validates :identifier, presence: true
  validates :identifier_type, inclusion: { in: TYPES }
  validates :identifier, uniqueness: { scope: :identifier_type, case_sensitive: false }

  # Login is gated only while at least one entry exists. Empty table = open sign-up.
  def self.gating?
    exists?
  end

  # True if this email / slack_id is permitted to log in (or the gate is off).
  def self.permits?(email:, slack_id:)
    return true unless gating?

    email = email.to_s.strip.downcase
    slack_id = slack_id.to_s.strip

    where(identifier_type: "email").where("LOWER(identifier) = ?", email).exists? ||
      (slack_id.present? && where(identifier_type: "slack_id", identifier: slack_id).exists?)
  end
end
