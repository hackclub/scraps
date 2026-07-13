class ShopRoll < ApplicationRecord
  self.table_name = "shop_rolls"
  belongs_to :user
  belongs_to :shop_item
end
