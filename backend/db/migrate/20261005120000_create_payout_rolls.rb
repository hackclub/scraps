class CreatePayoutRolls < ActiveRecord::Migration[8.1]
  def change
    create_table :payout_rolls do |t|
      t.integer :project_id, null: false
      t.integer :user_id, null: false
      t.integer :base_scraps, null: false
      t.decimal :roll_1, precision: 4, scale: 2
      t.decimal :roll_2, precision: 4, scale: 2
      t.decimal :final_multiplier, precision: 4, scale: 2
      t.string :status, null: false, default: "open"
      t.datetime :decided_at
      t.timestamps
    end
    add_index :payout_rolls, :project_id
    add_index :payout_rolls, [:user_id, :status]
  end
end
