class AddLoggedHoursToReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :reviews, :logged_hours, :float
  end
end
