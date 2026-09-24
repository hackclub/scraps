class AddSignupSourceToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :signup_source, :text
    add_index :users, :signup_source
  end
end
