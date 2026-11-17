class CreateItemSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :item_suggestions do |t|
      t.integer :user_id, null: false
      t.text :name, null: false
      t.text :image
      t.text :description
      t.text :vendor_url, null: false
      t.datetime :created_at, null: false
    end
    add_index :item_suggestions, :user_id
    add_index :item_suggestions, :created_at
  end
end
