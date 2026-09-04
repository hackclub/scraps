class CreateShopRetainedItems < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_retained_items do |t|
      t.integer :user_id, null: false
      t.integer :shop_item_id, null: false
      t.datetime :created_at, null: false
    end

    add_index :shop_retained_items, :user_id
    add_index :shop_retained_items, [:user_id, :shop_item_id], unique: true
  end
end
