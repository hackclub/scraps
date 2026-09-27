class UploadController < ApplicationController
  MAX_MB = 5
  STAFF_MAX_MB = 15

  def image
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    file = params[:file]
    return render_json({ error: "No file provided" }, status: :unprocessable_entity) unless file.respond_to?(:tempfile)
    max_mb = %w[admin creator].include?(current_user.role) ? STAFF_MAX_MB : MAX_MB
    return render_json({ error: "Image must be under #{max_mb}MB" }, status: :unprocessable_entity) if file.size > max_mb * 1024 * 1024

    detected = self.class.detect_image_type(file.tempfile)
    return render_json({ error: "Only JPEG, PNG, GIF or WebP images are allowed" }, status: :unprocessable_entity) unless detected

    unless r2_configured?
      return render_json({ error: "Upload service not configured" }, status: :service_unavailable)
    end

    content_type, ext = detected
    filename = "scrap-#{Time.now.to_i * 1000}-#{SecureRandom.hex(6)}.#{ext}"
    render_json({ url: upload_to_r2(file, filename, content_type) })
  rescue StandardError => e
    Rails.logger.error("[UPLOAD] Error: #{e.message}")
    render_json({ error: "Failed to upload image" }, status: :internal_server_error)
  end

  def self.detect_image_type(io)
    io.rewind
    head = io.read(12).to_s.b
    io.rewind
    return ["image/jpeg", "jpg"] if head.start_with?("\xFF\xD8\xFF".b)
    return ["image/png", "png"] if head.start_with?("\x89PNG\r\n\x1A\n".b)
    return ["image/gif", "gif"] if head.start_with?("GIF87a".b, "GIF89a".b)
    return ["image/webp", "webp"] if head.start_with?("RIFF".b) && head[8, 4] == "WEBP".b
    nil
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
