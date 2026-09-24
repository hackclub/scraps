namespace :users do
  desc "Encrypt any plaintext access_token/refresh_token/id_token left over from before User#encrypts was added"
  task encrypt_tokens: :environment do
    conn = ActiveRecord::Base.connection
    rows = conn.select_all(<<~SQL).to_a
      SELECT id, access_token, refresh_token, id_token FROM users
      WHERE access_token IS NOT NULL OR refresh_token IS NOT NULL OR id_token IS NOT NULL
    SQL

    puts "Found #{rows.size} user(s) with token data to encrypt."

    rows.each do |row|
      user = User.find(row["id"])
      # update_columns writes the raw nil directly, skipping the encrypted-attribute
      # dirty-check that would otherwise try (and fail) to decrypt the old plaintext
      # value. Wrapped in a transaction so a failure on update! rolls back the nil too.
      ActiveRecord::Base.transaction do
        user.update_columns(access_token: nil, refresh_token: nil, id_token: nil)
        user.update!(
          access_token: row["access_token"],
          refresh_token: row["refresh_token"],
          id_token: row["id_token"]
        )
      end
      print "."
    end

    puts "\nDone."
  end
end
