class AddFulfillmentCostToShopItems < ActiveRecord::Migration[8.1]
  def change
    # The real cost (USD) to fulfill/ship one unit. Set manually by an admin —
    # not derived from the item's "value".
    add_column :shop_items, :fulfillment_cost, :decimal, precision: 10, scale: 2
  end
end
