class UserBonus < ApplicationRecord
  self.table_name = "user_bonuses"
  belongs_to :user
  belongs_to :given_by_user, class_name: "User", foreign_key: :given_by, optional: true
end
