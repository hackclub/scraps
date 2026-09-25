class UploadController < ApplicationController
  EXT_MAP = {
    "image/jpeg" => "jpg",
    "image/jpg" => "jpg",
    "image/png" => "png",
    "image/gif" => "gif",
    "image/webp" => "webp"
  }.freeze

  def image
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    file = params[:file]
    return render_json({ error: "No file provided" }, status: :unprocessable_entity) unless file

    content_type = file.content_type.to_s
    ext = EXT_MAP[content_type] || "png"
    filename = "scrap-#{Time.now.to_i * 1000}.#{ext}"

    unless r2_configured?
      return render_json({ error: "Upload service not configured" }, status: :service_unavailable)
    end

    render_json({ url: upload_to_r2(file, filename, content_type) })
  rescue StandardError => e
    Rails.logger.error("[UPLOAD] Error: #{e.message}")
    render_json({ error: "Failed to upload image" }, status: :internal_server_error)
  end

  private

  def r2_configured?
    ENV["R2_ENDPOINT"].present? && ENV["R2_ACCESS_KEY_ID"].present? &&
      ENV["R2_SECRET_ACCESS_KEY"].present? && ENV["R2_BUCKET"].present? && ENV["R2_PUBLIC_URL"].present?
  end

  def r2_client
    require "aws-sdk-s3"
    @r2_client ||= Aws::S3::Client.new(
      access_key_id: ENV["R2_ACCESS_KEY_ID"],
      secret_access_key: ENV["R2_SECRET_ACCESS_KEY"],
      endpoint: ENV["R2_ENDPOINT"],
      region: "auto",
      force_path_style: true
    )
  end

  def upload_to_r2(file, filename, content_type)
    key = "uploads/#{filename}"
    r2_client.put_object(
      bucket: ENV["R2_BUCKET"],
      key: key,
      body: file.tempfile,
      content_type: content_type
    )
    "#{ENV['R2_PUBLIC_URL'].chomp('/')}/#{key}"
  end
end
