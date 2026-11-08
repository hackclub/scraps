class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :site_settings, id: false do |t|
      t.text :key, null: false, primary_key: true
      t.boolean :enabled, null: false, default: false
      t.timestamps
    end
  end
end
