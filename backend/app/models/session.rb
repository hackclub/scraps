class Session < ApplicationRecord
  self.table_name = "sessions"
  self.primary_key = "token"

  belongs_to :user
end
