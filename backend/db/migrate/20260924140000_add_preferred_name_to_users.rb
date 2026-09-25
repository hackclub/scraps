class AddPreferredNameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :preferred_name, :text
  end
end
