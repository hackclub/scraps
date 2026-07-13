class NewsController < ApplicationController
  def index
    items = ActiveRecord::Base.connection.select_all(
      "SELECT * FROM news WHERE active = true ORDER BY created_at DESC"
    ).to_a
    render_json(items.map { |n| news_to_h(n) })
  end

  def latest
    item = ActiveRecord::Base.connection.select_one(
      "SELECT * FROM news WHERE active = true ORDER BY created_at DESC LIMIT 1"
    )
    render_json(item ? news_to_h(item) : nil)
  end

  private

  def news_to_h(n)
    {
      id: n["id"].to_i,
      title: n["title"],
      content: n["content"],
      active: n["active"],
      created_at: n["created_at"],
      updated_at: n["updated_at"]
    }
  end
end
