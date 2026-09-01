class Referral < ApplicationRecord
  belongs_to :referrer, class_name: "User"
  belongs_to :referred_user, class_name: "User"

  validates :code, presence: true
  validates :referred_user_id, uniqueness: true
end
