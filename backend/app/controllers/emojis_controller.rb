class EmojisController < ApplicationController
  def search
    render_json({ emojis: EmojiService.search(params[:q].to_s) })
  rescue StandardError => e
    render_json({ error: "Couldn't load emojis: #{e.message}" }, status: :bad_gateway)
  end

  def lookup
    names = params[:names].to_s.split(",").map(&:strip).reject(&:empty?).first(200)
    render json: { emojis: EmojiService.lookup(names) }
  rescue StandardError => e
    render_json({ error: "Couldn't load emojis: #{e.message}" }, status: :bad_gateway)
  end
end
