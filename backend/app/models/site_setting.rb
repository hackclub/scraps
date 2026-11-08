class SiteSetting < ApplicationRecord
  self.primary_key = "key"

  KEYS = %w[explore].freeze

  def self.enabled?(key)
    where(key: key.to_s).pick(:enabled) == true
  end

  def self.set!(key, enabled)
    row = find_or_initialize_by(key: key.to_s)
    row.enabled = enabled
    row.save!
    row
  end

  def self.all_flags
    stored = where(key: KEYS).pluck(:key, :enabled).to_h
    KEYS.index_with { |k| stored[k] == true }
  end
end
