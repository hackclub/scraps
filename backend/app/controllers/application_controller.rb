class ApplicationController < ActionController::API
  include ActionController::Cookies

  def render_json(data, status: :ok)
    render json: deep_camelize(data), status: status
  end

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = user_from_session
  end

  def require_auth
    unless current_user
      render_json({ error: "Unauthorized" }, status: :unauthorized)
    end
  end

  def require_reviewer_role
    unless current_user && %w[reviewer admin creator].include?(current_user.role)
      render_json({ error: "Unauthorized" }, status: :unauthorized)
      return nil
    end
    current_user
  end

  def require_admin_role
    unless current_user && %w[admin creator].include?(current_user.role)
      render_json({ error: "Unauthorized" }, status: :unauthorized)
      return nil
    end
    current_user
  end

  def require_creator_role
    unless current_user && current_user.role == "creator"
      render_json({ error: "Unauthorized" }, status: :unauthorized)
      return nil
    end
    current_user
  end

  private

  def user_from_session
    cookie = request.cookies["session"]
    return nil unless cookie.present?

    session_rec = ActiveRecord::Base.connection.select_one(
      "SELECT user_id FROM sessions WHERE token = $1 AND expires_at > NOW()",
      "SessionLookup", [cookie]
    )
    return nil unless session_rec

    User.find_by(id: session_rec["user_id"])
  rescue StandardError
    nil
  end

  def deep_camelize(obj)
    case obj
    when Hash
      obj.each_with_object({}) do |(k, v), memo|
        memo[camelize_key(k.to_s)] = deep_camelize(v)
      end
    when Array
      obj.map { |item| deep_camelize(item) }
    else
      obj
    end
  end

  def camelize_key(str)
    parts = str.split("_")
    return str if parts.length <= 1
    parts[0] + parts[1..].map(&:capitalize).join
  end
end
