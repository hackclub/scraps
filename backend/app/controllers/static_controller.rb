class StaticController < ApplicationController
  def fallback
    send_file Rails.public_path.join("200.html"), type: "text/html", disposition: "inline"
  end
end
