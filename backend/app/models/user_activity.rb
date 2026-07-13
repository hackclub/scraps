class UserActivity < ApplicationRecord
  self.table_name = "user_activity"
  belongs_to :user, optional: true
end
