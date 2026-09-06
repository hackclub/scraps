class AddUserNoteToShopOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_orders, :user_note, :text
  end
end
