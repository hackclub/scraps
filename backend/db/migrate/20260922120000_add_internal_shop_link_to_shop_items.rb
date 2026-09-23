class AddInternalShopLinkToShopItems < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_items, :internal_shop_link, :text
  end
end
