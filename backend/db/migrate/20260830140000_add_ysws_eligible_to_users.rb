class AddYswsEligibleToUsers < ActiveRecord::Migration[8.1]
  def change
    # Nullable: null = not yet known (pre-existing rows), true/false = reported by Hack Club Auth at login.
    add_column :users, :ysws_eligible, :boolean
  end
end
