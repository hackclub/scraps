class StreakController < ApplicationController
  before_action :require_auth

  def show
    begin
      StreakService.sync(current_user)
    rescue StandardError => e
      Rails.logger.error("[StreakController] sync failed for user #{current_user.id}: #{e.message}")
    end
    render_json(StreakService.state(current_user))
  end

  def claim
    result = StreakService.claim(current_user, params[:date], params[:item_id] || params[:itemId])
    render_json(result.merge(StreakService.state(current_user)))
  rescue StreakService::ClaimError => e
    render_json({ error: e.message }, status: :unprocessable_entity)
  end
end
