# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

if Rails.env.development?
  conn = ActiveRecord::Base.connection

  user_id = conn.select_value("SELECT id FROM users WHERE sub = 'dev:test_user'") || conn.select_value(<<~SQL)
    INSERT INTO users (sub, username, email, role, has_been_onboarded, tutorial_completed, created_at, updated_at)
    VALUES ('dev:test_user', 'test_user', 'test_user@dev.local', 'member', true, true, NOW(), NOW())
    RETURNING id
  SQL

  if conn.select_value("SELECT COUNT(*) FROM projects WHERE user_id = #{user_id}").to_i.zero?
    conn.execute(<<~SQL)
      INSERT INTO projects (user_id, name, description, status, hours, scraps_awarded, scraps_paid_amount, scraps_paid_at, created_at, updated_at)
      VALUES (#{user_id}, 'dev test project', 'seeded for local dev', 'shipped', 10, 500, 500, NOW(), NOW(), NOW())
    SQL
  end

  items = [["dev sticker pack", 50], ["dev hoodie", 150]].map do |name, price|
    conn.select_value("SELECT id FROM shop_items WHERE name = #{conn.quote(name)}") || conn.select_value(<<~SQL)
      INSERT INTO shop_items (name, description, price, count, created_at, updated_at)
      VALUES (#{conn.quote(name)}, 'seeded for local dev', #{price}, 20, NOW(), NOW())
      RETURNING id
    SQL
  end

  if conn.select_value("SELECT COUNT(*) FROM shop_orders WHERE user_id = #{user_id}").to_i.zero?
    [[items[0], 50], [items[1], 150]].each do |item_id, price|
      conn.execute(<<~SQL)
        INSERT INTO shop_orders (user_id, shop_item_id, order_type, quantity, price_per_item, total_price, status, created_at, updated_at)
        VALUES (#{user_id}, #{item_id}, 'purchase', 1, #{price}, #{price}, 'pending', NOW(), NOW())
      SQL
    end
  end

  puts "seeded test_user (id #{user_id}) with 500 scraps earned and 2 pending orders"
end
