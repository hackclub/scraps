class CreateRaffleEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :raffle_entries do |t|
      t.integer :user_id, null: false
      t.integer :week, null: false
      t.integer :tickets, null: false, default: 0
      t.timestamps
    end
    add_index :raffle_entries, [:user_id, :week], unique: true
  end
end
