class AddSizeVariantsToShopItems < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_items, :size_variants, :jsonb, default: [], null: false
  end
end
