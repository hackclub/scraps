class CreateReferralRewardClaims < ActiveRecord::Migration[8.1]
  def change
    create_table :referral_reward_claims do |t|
      t.bigint :user_id, null: false
      t.string :reward, null: false
      t.integer :shop_order_id
      t.timestamps
    end
    add_index :referral_reward_claims, [:user_id, :reward], unique: true
  end
end
