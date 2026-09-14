class AddRetainedCapTrackingToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :retained_cap_bonus, :integer, default: 0, null: false
    add_column :users, :retained_cap_checked_on, :date
  end
end
