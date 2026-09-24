class CreateSignupSources < ActiveRecord::Migration[8.1]
  def change
    create_table :signup_sources do |t|
      t.text :slug, null: false
      t.text :note
      t.timestamps
    end

    add_index :signup_sources, :slug, unique: true
  end
end
