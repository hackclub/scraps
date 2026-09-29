class AddHackatimeUserIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :hackatime_user_id, :integer
  end
end
