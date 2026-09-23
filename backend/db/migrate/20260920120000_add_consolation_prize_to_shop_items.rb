class AddConsolationPrizeToShopItems < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_items, :consolation_prize, :boolean, default: false, null: false
  end
end
