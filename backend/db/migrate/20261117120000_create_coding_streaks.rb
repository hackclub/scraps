class CreateCodingStreaks < ActiveRecord::Migration[8.1]
  def change
    create_table :user_daily_minutes do |t|
      t.integer :user_id, null: false
      t.date :day, null: false
      t.integer :seconds, null: false, default: 0
      t.timestamps
    end
    add_index :user_daily_minutes, [:user_id, :day], unique: true

    create_table :streak_reward_claims do |t|
      t.integer :user_id, null: false
      t.date :day, null: false
      t.text :kind, null: false
      t.integer :tickets, null: false, default: 0
      t.text :detail
      t.datetime :created_at, null: false
    end
    add_index :streak_reward_claims, [:user_id, :day], unique: true

    add_column :users, :raffle_tickets, :integer, null: false, default: 0
    add_column :users, :streak_synced_at, :datetime
  end
end
