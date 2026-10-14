class AddFulfilledByToShopOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_orders, :fulfilled_by_id, :integer
    add_column :shop_orders, :fulfilled_at, :datetime, precision: nil
    add_foreign_key :shop_orders, :users, column: :fulfilled_by_id
  end
end
