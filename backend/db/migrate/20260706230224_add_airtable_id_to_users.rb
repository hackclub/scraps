class AddAirtableIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :airtable_id, :string
  end
end
