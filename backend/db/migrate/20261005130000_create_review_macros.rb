class CreateReviewMacros < ActiveRecord::Migration[8.1]
  def change
    create_table :review_macros do |t|
      t.string :short_name, null: false
      t.text :body, null: false
      t.integer :created_by
      t.timestamps
    end
    add_index :review_macros, :short_name, unique: true
  end
end
