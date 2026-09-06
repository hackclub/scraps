class CreateShopGachapons < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_gachapons do |t|
      t.text :name, null: false
      t.text :description
      t.text :image
      t.integer :price, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    create_table :shop_gachapon_items do |t|
      t.integer :gachapon_id, null: false
      t.integer :shop_item_id, null: false
      t.datetime :created_at, null: false
    end

    add_index :shop_gachapon_items, :gachapon_id
    add_index :shop_gachapon_items, [:gachapon_id, :shop_item_id], unique: true, name: "index_gachapon_items_on_gachapon_and_item"
  end
end
