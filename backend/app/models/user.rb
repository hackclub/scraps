class User < ApplicationRecord
  self.table_name = "users"

  has_many :sessions, foreign_key: :user_id
  has_many :projects, foreign_key: :user_id
  has_many :user_bonuses, foreign_key: :user_id
  has_many :shop_hearts, foreign_key: :user_id
  has_many :shop_orders, foreign_key: :user_id
  has_many :refinery_orders, foreign_key: :user_id
  has_many :shop_penalties, foreign_key: :user_id
  has_many :refinery_spending_histories, foreign_key: :user_id
  has_many :user_activities, foreign_key: :user_id
end
