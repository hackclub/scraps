class RefineryOrder < ApplicationRecord
  self.table_name = "refinery_orders"
  belongs_to :user
  belongs_to :shop_item
end
