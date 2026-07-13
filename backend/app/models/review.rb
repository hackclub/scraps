class Review < ApplicationRecord
  self.table_name = "reviews"

  belongs_to :project
  belongs_to :reviewer, class_name: "User", foreign_key: :reviewer_id
end
