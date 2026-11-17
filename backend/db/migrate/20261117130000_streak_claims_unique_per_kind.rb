class StreakClaimsUniquePerKind < ActiveRecord::Migration[8.1]
  def change
    remove_index :streak_reward_claims, [:user_id, :day], unique: true
    add_index :streak_reward_claims, [:user_id, :day, :kind], unique: true
  end
end
