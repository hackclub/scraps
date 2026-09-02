class AddIsReshipToProjects < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :is_reship, :boolean, default: false, null: false
    execute "UPDATE projects SET is_reship = true WHERE update_description IS NOT NULL AND update_description <> ''"
  end

  def down
    remove_column :projects, :is_reship
  end
end
