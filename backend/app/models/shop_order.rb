class ShopOrder < ApplicationRecord
  self.table_name = "shop_orders"
  belongs_to :user
  belongs_to :shop_item
end
