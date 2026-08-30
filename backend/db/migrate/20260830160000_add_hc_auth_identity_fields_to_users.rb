class AddHcAuthIdentityFieldsToUsers < ActiveRecord::Migration[8.1]
  # Extra identity fields from Hack Club Auth's /api/v1/me. Populated only once the
  # OAuth app is granted the `basic_info` + `addresses` scopes (see AuthController::OAUTH_SCOPE).
  # `phone` already exists on the table.
  def change
    add_column :users, :birthday, :date
    add_column :users, :legal_first_name, :text
    add_column :users, :legal_last_name, :text
    add_column :users, :address_line1, :text
    add_column :users, :address_line2, :text
    add_column :users, :address_city, :text
    add_column :users, :address_state, :text
    add_column :users, :address_postal_code, :text
    add_column :users, :address_country, :text
  end
end
