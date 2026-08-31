class AddInternalNotesToProjects < ActiveRecord::Migration[8.1]
  # Admin/reviewer notes attached to a single project (distinct from users.internal_notes,
  # which follow the user, and projects.reviewer_notes, which is the author's own text).
  def change
    add_column :projects, :internal_notes, :text
  end
end
