class SignupSource < ApplicationRecord
  SLUG_FORMAT = /\A[a-z0-9_-]{1,32}\z/

  validates :slug, presence: true, format: { with: SLUG_FORMAT }, uniqueness: true

  def self.valid_slug?(value)
    value.to_s.match?(SLUG_FORMAT)
  end
end
