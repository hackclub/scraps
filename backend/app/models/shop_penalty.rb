class ShopPenalty < ApplicationRecord
  self.table_name = "shop_penalties"
  belongs_to :user
  belongs_to :shop_item
end
