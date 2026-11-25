class RaffleController < ApplicationController
  before_action :require_auth

  def show
    render_json(RaffleService.state(current_user))
  end

  def update
    render_json(RaffleService.set(current_user, params[:week], params[:tickets]))
  rescue RaffleService::EntryError => e
    render_json({ error: e.message }, status: :unprocessable_entity)
  end
end
