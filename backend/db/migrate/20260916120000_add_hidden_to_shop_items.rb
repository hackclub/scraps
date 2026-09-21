class AddHiddenToShopItems < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_items, :hidden, :boolean, default: false, null: false
  end
end
