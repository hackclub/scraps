class AddReviewerScoreToReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :reviews, :reviewer_score, :float
  end
end
