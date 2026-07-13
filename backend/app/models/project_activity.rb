class ProjectActivity < ApplicationRecord
  self.table_name = "project_activity"

  belongs_to :user
  belongs_to :project, optional: true
end
