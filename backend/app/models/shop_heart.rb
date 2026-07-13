class ShopHeart < ApplicationRecord
  self.table_name = "shop_hearts"
  belongs_to :user
  belongs_to :shop_item
end
