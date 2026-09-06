class AddGachaponOnlyToShopItems < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_items, :gachapon_only, :boolean, default: false, null: false
  end
end
