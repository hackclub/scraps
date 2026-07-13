class UploadController < ApplicationController
  HCCDN_URL = "https://cdn.hackclub.com/api/v4/upload"

  EXT_MAP = {
    "image/jpeg" => "jpg",
    "image/jpg" => "jpg",
    "image/png" => "png",
    "image/gif" => "gif",
    "image/webp" => "webp"
  }.freeze

  def image
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    key = ENV["HCCDN_KEY"]
    unless key.present?
      return render_json({ error: "Upload service not configured" }, status: :service_unavailable)
    end

    file = params[:file]
    return render_json({ error: "No file provided" }, status: :unprocessable_entity) unless file

    content_type = file.content_type.to_s
    ext = EXT_MAP[content_type] || "png"
    filename = "scrap-#{Time.now.to_i * 1000}.#{ext}"

    resp = HTTParty.post(
      HCCDN_URL,
      headers: { "Authorization" => "Bearer #{key}" },
      multipart: true,
      body: { file: file.tempfile, filename: filename, content_type: content_type }
    )

    unless resp.success?
      Rails.logger.error("[UPLOAD] CDN error: #{resp.code} #{resp.body}")
      return render_json({ error: "Failed to upload image" }, status: :bad_gateway)
    end

    data = resp.parsed_response
    render_json({ url: data["url"] })
  rescue StandardError => e
    Rails.logger.error("[UPLOAD] Error: #{e.message}")
    render_json({ error: "Failed to upload image" }, status: :internal_server_error)
  end
end
