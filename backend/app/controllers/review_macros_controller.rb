class ReviewMacrosController < ApplicationController
  before_action :require_reviewer_role, only: %i[index]
  before_action :require_admin_role, only: %i[create update destroy]

  def index
    render_json(ReviewMacro.order(:short_name).map { |m| macro_h(m) })
  end

  def create
    macro = ReviewMacro.new(short_name: params[:shortName].to_s.strip, body: params[:body].to_s.strip, created_by: current_user.id)
    return render_json({ error: macro.errors.full_messages.first }, status: :unprocessable_entity) unless macro.save
    render_json(macro_h(macro), status: :created)
  end

  def update
    macro = ReviewMacro.find_by(id: params[:id])
    return render_json({ error: "Not found" }, status: :not_found) unless macro
    macro.short_name = params[:shortName].to_s.strip if params.key?(:shortName)
    macro.body = params[:body].to_s.strip if params.key?(:body)
    return render_json({ error: macro.errors.full_messages.first }, status: :unprocessable_entity) unless macro.save
    render_json(macro_h(macro))
  end

  def destroy
    macro = ReviewMacro.find_by(id: params[:id])
    return render_json({ error: "Not found" }, status: :not_found) unless macro
    macro.destroy
    render_json({ success: true })
  end

  private

  def macro_h(m)
    { id: m.id, short_name: m.short_name, body: m.body, updated_at: m.updated_at }
  end
end
