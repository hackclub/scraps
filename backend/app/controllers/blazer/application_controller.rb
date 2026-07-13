module Blazer
  # Blazer::BaseController hardcodes `ApplicationController` as its superclass.
  # Ruby's lexical constant lookup resolves that reference to this class (Blazer::ApplicationController)
  # before it falls back to the top-level ApplicationController, which is an ActionController::API
  # used by every JSON endpoint. Keeping Blazer on its own ActionController::Base subclass means its
  # sessions/CSRF/views don't leak into (or get broken by) the rest of the API.
  class ApplicationController < ActionController::Base
    def current_user
      return @current_user if defined?(@current_user)

      cookie = request.cookies["session"]
      session_rec = cookie.present? && ActiveRecord::Base.connection.select_one(
        "SELECT user_id FROM sessions WHERE token = $1 AND expires_at > NOW()",
        "SessionLookup", [cookie]
      )
      @current_user = session_rec && User.find_by(id: session_rec["user_id"])
    end
    helper_method :current_user

    private

    def require_blazer_admin
      unless current_user && %w[admin creator].include?(current_user.role)
        render plain: "Not authorized", status: :forbidden
      end
    end
  end
end
