class AddHasBeenOnboardedToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :has_been_onboarded, :boolean, default: false, null: false
  end
end
