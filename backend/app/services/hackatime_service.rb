module HackatimeService
  HACKATIME_API = "https://hackatime.hackclub.com/api/admin/v1"
  SCRAPS_START_DATE = "2026-08-01"
  START_DATE_OVERRIDES = { "U09KEHH8LCV" => "2026-05-01" }.freeze

  # In-memory caches shared across every request/job in the process. Entries
  # expire after CACHE_TTL so a batch pass stays warm (jobs run within seconds of
  # each other) but the next pass 2 minutes later always re-fetches from Hackatime.
  CACHE_TTL = 90 # seconds
  @user_cache = {}
  @projects_cache = {}
  @category_cache = {}
  @override_ids = {}
  HEARTBEAT_PAGE = 5000
  HEARTBEAT_MAX = 100_000
  HEARTBEAT_TIMEOUT = 120

  class << self
    attr_accessor :user_cache, :projects_cache, :category_cache, :override_ids

    def clear_caches
      @user_cache = {}
      @projects_cache = {}
      @category_cache = {}
    end

    def cache_get(store, key)
      entry = store[key]
      return nil unless entry
      return nil if Time.now.to_f - entry[:at] > CACHE_TTL
      entry
    end

    def cache_put(store, key, value)
      store[key] = { value: value, at: Time.now.to_f }
      value
    end

    def get_user(email, slack_id = nil)
      cache_key = email.presence || slack_id || ""
      if (hit = cache_get(@user_cache, cache_key))
        return hit[:value]
      end

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

      cache_put(@user_cache, cache_key, fetch_user_info(user_id))
    end

    def get_user_by_id(hackatime_user_id)
      fetch_user_info(hackatime_user_id.to_i)
    end

    def start_date_for(user_id)
      START_DATE_OVERRIDES.each do |slack_id, date|
        return date if override_hackatime_id(slack_id) == user_id.to_i
      end
      SCRAPS_START_DATE
    end

    def fetch_user_projects(user_id)
      if (hit = cache_get(@projects_cache, user_id))
        return hit[:value]
      end

      begin
        resp = HTTParty.get(
          "#{HACKATIME_API}/user/projects?user_id=#{user_id}&start_date=#{start_date_for(user_id)}",
          headers: auth_headers
        )
        return nil unless resp.success?
        cache_put(@projects_cache, user_id, resp.parsed_response["projects"] || [])
      rescue StandardError
        nil
      end
    end

    def fetch_category_seconds(user_id, project_name)
      cache_key = "#{user_id}:#{project_name}"
      if (hit = cache_get(@category_cache, cache_key))
        return hit[:value]
      end

      heartbeats = []
      offset = 0
      loop do
        resp = HTTParty.get(
          "#{HACKATIME_API}/user/heartbeats",
          headers: auth_headers,
          query: { user_id: user_id, start_date: start_date_for(user_id), project: project_name, limit: HEARTBEAT_PAGE, offset: offset }
        )
        return nil unless resp.success?
        page = resp.parsed_response["heartbeats"] || []
        heartbeats.concat(page.map { |hb| [hb["time"].to_f, hb["category"].to_s] })
        offset += page.length
        break if page.empty? || !resp.parsed_response["has_more"] || offset >= HEARTBEAT_MAX
      end

      totals = Hash.new(0.0)
      heartbeats.sort_by!(&:first)
      heartbeats.each_cons(2) { |(prev, _), (time, category)| totals[category] += [time - prev, HEARTBEAT_TIMEOUT].min }
      cache_put(@category_cache, cache_key, totals)
    rescue StandardError
      nil
    end

    def ai_category?(category)
      category.to_s.match?(/\bai\b/i)
    end

    def split_project_list(hackatime_project)
      return [] if hackatime_project.blank?
      hackatime_project.to_s.scan(/(?:\\[\\,]|[^,])+/)
        .map { |entry| entry.strip.gsub(/\\([\\,])/, '\1') }
        .reject(&:empty?)
    end

    def join_project_list(entries)
      entries.map { |entry| entry.to_s.gsub(/[\\,]/) { |c| "\\#{c}" } }.join(",")
    end

    def parse_hackatime_projects(hackatime_project)
      split_project_list(hackatime_project).map { |entry| parse_entry(entry) }
    end

    def strip_entry_id(entry)
      entry = entry.to_s.strip
      colon_idx = entry.index(":")
      if colon_idx && !entry.start_with?("U")
        entry[(colon_idx + 1)..]
      elsif (slash_idx = entry.index("/")) && entry.start_with?("U")
        entry[(slash_idx + 1)..]
      else
        entry
      end
    end

    def project_names(hackatime_project)
      split_project_list(hackatime_project).map { |entry| strip_entry_id(entry) }
    end

    def strip_hackatime_ids(hackatime_project)
      return nil if hackatime_project.blank?
      join_project_list(project_names(hackatime_project))
    end

    private

    def auth_headers
      {
        "Authorization" => "Bearer #{ENV['HACKATIME_ADMIN']}",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }
    end

    def override_hackatime_id(slack_id)
      return @override_ids[slack_id] if @override_ids[slack_id]
      id = ActiveRecord::Base.connection.select_value(
        "SELECT hackatime_user_id FROM users WHERE slack_id = #{ActiveRecord::Base.connection.quote(slack_id)} AND hackatime_user_id IS NOT NULL LIMIT 1"
      )&.to_i
      if id.nil?
        resp = HTTParty.post("#{HACKATIME_API}/user/search_fuzzy", headers: auth_headers, body: { query: slack_id }.to_json)
        users = resp.success? ? (resp.parsed_response["users"] || []) : []
        id = users[0]["id"]&.to_i if users.length == 1
      end
      @override_ids[slack_id] = id if id
      id
    rescue StandardError => e
      Rails.logger.warn("[HACKATIME] override lookup failed: #{e.message}")
      nil
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
        suspected: obj["suspected"] || false,
        trust_level: obj["trust_level"]
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
