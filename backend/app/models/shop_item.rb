class ShopItem < ApplicationRecord
  self.table_name = "shop_items"

  has_many :shop_hearts, foreign_key: :shop_item_id
  has_many :shop_orders, foreign_key: :shop_item_id
  has_many :shop_rolls, foreign_key: :shop_item_id
  has_many :refinery_orders, foreign_key: :shop_item_id
  has_many :shop_penalties, foreign_key: :shop_item_id
  has_many :refinery_spending_histories, foreign_key: :shop_item_id
end
