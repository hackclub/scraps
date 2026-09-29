class Session < ApplicationRecord
  self.table_name = "sessions"
  self.primary_key = "token"

  belongs_to :user

  # The `token` column stores a hash, not the raw cookie value, so reading the
  # sessions table (e.g. via Blazer) can't be used to log in as someone else.
  def self.hash_token(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end
end
