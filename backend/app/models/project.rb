class Project < ApplicationRecord
  self.table_name = "projects"

  belongs_to :user
  has_many :reviews, foreign_key: :project_id
  has_many :project_activities, foreign_key: :project_id

  scope :active, -> { where("deleted = 0 OR deleted IS NULL") }
end
