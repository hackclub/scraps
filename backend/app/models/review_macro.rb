class ReviewMacro < ApplicationRecord
  validates :short_name, presence: true, length: { maximum: 40 }, uniqueness: { case_sensitive: false }
  validates :body, presence: true, length: { maximum: 2000 }
end
