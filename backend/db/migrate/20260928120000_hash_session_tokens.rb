class HashSessionTokens < ActiveRecord::Migration[8.1]
  # Existing rows store the raw cookie value; the app now looks sessions up by
  # SHA256(cookie value), so old rows can never match again anyway. Clearing
  # them logs everyone out once instead of leaving dead rows behind.
  def up
    execute "DELETE FROM sessions"
  end

  def down
    execute "DELETE FROM sessions"
  end
end
