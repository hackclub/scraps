module HackatimeService
  HACKATIME_API = "https://hackatime.hackclub.com/api/admin/v1"
  SCRAPS_START_DATE = "2026-02-03"

  # Thread-safe in-memory caches (reset per Sidekiq job run)
  @user_cache = {}
  @projects_cache = {}

  class << self
    attr_accessor :user_cache, :projects_cache

    def clear_caches
      @user_cache = {}
      @projects_cache = {}
    end

    def get_user(email, slack_id = nil)
      cache_key = email.presence || slack_id || ""
      return @user_cache[cache_key] if @user_cache.key?(cache_key)

      user_id = nil

      begin
        resp = HTTParty.post(
          "#{HACKATIME_API}/user/get_user_by_email",
          headers: auth_headers,
          body: { email: email }.to_json
        )
        user_id = resp.parsed_response["user_id"]&.to_i if resp.success?
      rescue StandardError => e
        Rails.logger.warn("[HACKATIME] email lookup failed: #{e.message}")
      end

      if user_id.nil? && slack_id.present?
        begin
          resp = HTTParty.post(
            "#{HACKATIME_API}/user/search_fuzzy",
            headers: auth_headers,
            body: { query: slack_id }.to_json
          )
          if resp.success?
            users = resp.parsed_response["users"] || []
            user_id = users[0]["id"]&.to_i if users.length == 1
          end
        rescue StandardError => e
          Rails.logger.warn("[HACKATIME] fuzzy lookup failed: #{e.message}")
        end
      end

      return nil if user_id.nil?

      user = fetch_user_info(user_id)
      @user_cache[cache_key] = user
      user
    end

    def fetch_user_projects(user_id)
      return @projects_cache[user_id] if @projects_cache.key?(user_id)

      begin
        resp = HTTParty.get(
          "#{HACKATIME_API}/user/projects?user_id=#{user_id}&start_date=#{SCRAPS_START_DATE}",
          headers: auth_headers
        )
        return nil unless resp.success?
        projects = resp.parsed_response["projects"] || []
        @projects_cache[user_id] = projects
        projects
      rescue StandardError
        nil
      end
    end

    def parse_hackatime_projects(hackatime_project)
      return [] if hackatime_project.blank?
      hackatime_project.split(",").map(&:strip).filter_map do |entry|
        next nil if entry.blank?
        parse_entry(entry)
      end
    end

    def strip_hackatime_ids(hackatime_project)
      return nil if hackatime_project.blank?
      hackatime_project.split(",").map do |entry|
        entry = entry.strip
        colon_idx = entry.index(":")
        if colon_idx && !entry.start_with?("U")
          entry[(colon_idx + 1)..]
        elsif (slash_idx = entry.index("/")) && entry.start_with?("U")
          entry[(slash_idx + 1)..]
        else
          entry
        end
      end.join(",")
    end

    private

    def auth_headers
      {
        "Authorization" => "Bearer #{ENV['HACKATIME_ADMIN']}",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }
    end

    def fetch_user_info(user_id)
      resp = HTTParty.get(
        "#{HACKATIME_API}/user/info?user_id=#{user_id}",
        headers: auth_headers
      )
      return nil unless resp.success?
      data = resp.parsed_response
      obj = data["user"] || data
      {
        user_id: obj["user_id"]&.to_i || user_id,
        username: obj["username"],
        slack_uid: obj["slack_uid"],
        banned: obj["banned"] || false,
        suspected: obj["suspected"] || false
      }
    rescue StandardError
      nil
    end

    def parse_entry(entry)
      colon_idx = entry.index(":")
      if colon_idx && !entry.start_with?("U")
        id_str = entry[0...colon_idx]
        id = id_str.to_i
        return {
          slack_id: nil,
          hackatime_user_id: id.nonzero?,
          project_name: entry[(colon_idx + 1)..]
        }
      end

      slash_idx = entry.index("/")
      if slash_idx && entry.start_with?("U")
        return {
          slack_id: entry[0...slash_idx],
          hackatime_user_id: nil,
          project_name: entry[(slash_idx + 1)..]
        }
      end

      { slack_id: nil, hackatime_user_id: nil, project_name: entry }
    end
  end
end
