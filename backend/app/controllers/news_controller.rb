class NewsController < ApplicationController
  # News is identical for every visitor and changes rarely; cache the payload so
  # this isn't a remote-DB round trip on every page load. Admin writes bust it.
  def index
    payload = Rails.cache.fetch("news:index:v1", expires_in: 5.minutes) do
      items = ActiveRecord::Base.connection.select_all(
        "SELECT * FROM news WHERE active = true ORDER BY created_at DESC"
      ).to_a
      items.map { |n| news_to_h(n) }
    end
    render_json(payload)
  end

  def latest
    payload = Rails.cache.fetch("news:latest:v1", expires_in: 5.minutes) do
      item = ActiveRecord::Base.connection.select_one(
        "SELECT * FROM news WHERE active = true ORDER BY created_at DESC LIMIT 1"
      )
      item ? news_to_h(item) : nil
    end
    render_json(payload)
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
