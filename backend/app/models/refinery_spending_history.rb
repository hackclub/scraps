class RefinerySpendingHistory < ApplicationRecord
  self.table_name = "refinery_spending_history"
  belongs_to :user
  belongs_to :shop_item
end
