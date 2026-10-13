class AddSizeToShopOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_orders, :size, :text
  end
end
