class AddMissingIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :projects, :user_id, algorithm: :concurrently
    add_index :projects, :status, algorithm: :concurrently
    add_index :projects, :updated_at, algorithm: :concurrently
    add_index :projects, :views, algorithm: :concurrently
    add_index :reviews, :project_id, algorithm: :concurrently
    add_index :reviews, :reviewer_id, algorithm: :concurrently
    add_index :project_activity, :project_id, algorithm: :concurrently
  end
end
