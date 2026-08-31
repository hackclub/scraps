class CreateLoginAllowlistEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :login_allowlist_entries do |t|
      t.text :identifier, null: false          # an email address or a Slack ID
      t.text :identifier_type, null: false     # "email" | "slack_id"
      t.text :note
      t.bigint :added_by_user_id
      t.timestamps
    end

    add_index :login_allowlist_entries, %i[identifier_type identifier], unique: true
  end
end
