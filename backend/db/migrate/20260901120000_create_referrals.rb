class CreateReferrals < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :referral_code, :text
    add_index :users, :referral_code, unique: true

    create_table :referrals do |t|
      t.bigint :referrer_id, null: false
      t.bigint :referred_user_id, null: false   # the person who signed up
      t.text :code, null: false                 # the referrer's code at signup time
      t.boolean :rewarded, null: false, default: false
      t.integer :reward_amount, null: false, default: 0
      t.timestamps
    end

    add_index :referrals, :referrer_id
    add_index :referrals, :referred_user_id, unique: true
  end
end
