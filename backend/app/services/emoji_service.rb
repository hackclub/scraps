module EmojiService
  CACHET_EMOJIS_URL = "https://cachet.dunkirk.sh/emojis"
  STANDARD_EMOJIS_URL = "https://cdn.jsdelivr.net/npm/emoji-datasource@15.1.2/emoji.json"
  STANDARD_IMG_BASE = "https://cdn.jsdelivr.net/npm/emoji-datasource-apple@15.1.2/img/apple/64/"
  REFRESH_SECONDS = 12 * 60 * 60

  @emojis = []
  @by_name = {}
  @loaded_at = 0
  @lock = Mutex.new

  class << self
    def search(query, limit = 20)
      ensure_loaded
      q = query.to_s.downcase.delete(":")
      return [] if q.empty?

      exact = @by_name[q]
      standard_prefix = []
      custom_prefix = []
      contains = []
      @emojis.each do |e|
        next if e.equal?(exact)
        if e[:name].start_with?(q)
          (e[:standard] ? standard_prefix : custom_prefix) << e
        elsif contains.length < limit && e[:name].include?(q)
          contains << e
        end
      end

      [exact, *standard_prefix, *custom_prefix, *contains]
        .compact
        .first(limit)
        .map { |e| { name: e[:name], image_url: e[:image_url] } }
    end

    def lookup(names)
      ensure_loaded
      names.each_with_object({}) do |name, found|
        e = @by_name[name.to_s.downcase]
        found[name] = e[:image_url] if e
      end
    end

    private

    def ensure_loaded
      return if @emojis.any? && Time.now.to_i - @loaded_at < REFRESH_SECONDS

      @lock.synchronize do
        return if @emojis.any? && Time.now.to_i - @loaded_at < REFRESH_SECONDS
        refresh
      end
    rescue StandardError => e
      Rails.logger.error("EmojiService refresh failed: #{e.message}")
      raise if @emojis.empty?
    end

    def refresh
      custom = fetch_json(CACHET_EMOJIS_URL)
      standard = fetch_json(STANDARD_EMOJIS_URL)

      next_map = {}
      standard.each do |e|
        Array(e["short_names"]).each do |name|
          next_map[name] = { name: name, image_url: STANDARD_IMG_BASE + e["image"].to_s, standard: true }
        end
      end
      custom.each do |e|
        name = e["name"].to_s
        next if name.empty? || next_map.key?(name)
        next_map[name] = { name: name, image_url: e["imageUrl"], standard: false }
      end

      @by_name = next_map
      @emojis = next_map.values.sort_by { |e| e[:name] }
      @loaded_at = Time.now.to_i
    end

    def fetch_json(url)
      resp = HTTParty.get(url, timeout: 15)
      raise "#{url} returned #{resp.code}" unless resp.success?
      data = JSON.parse(resp.body)
      raise "#{url} returned non-array" unless data.is_a?(Array)
      data
    end
  end
end
