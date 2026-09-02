module LapseService
  API = "https://api.lapse.hackclub.com/api/hackatime".freeze

  # Timelapses a user recorded with Lapse (lapse.hackclub.com) for the given
  # Hackatime project names, created within [start_time, end_time].
  #
  # Without LAPSE_API_KEY only public timelapses are returned; with it, the
  # user's unlisted ones too. Returns [] on any failure — this is supplementary
  # evidence, never load-bearing.
  def self.timelapses_for(hackatime_user_id:, project_names:, start_time:, end_time:)
    return [] if hackatime_user_id.blank? || project_names.blank?

    start_ms = start_time.to_i * 1000
    end_ms = end_time.to_i * 1000
    headers = {}
    headers["Authorization"] = "Bearer #{ENV['LAPSE_API_KEY']}" if ENV["LAPSE_API_KEY"].present?

    project_names.flat_map do |name|
      resp = HTTParty.get("#{API}/timelapsesForProject",
        query: { hackatimeUserId: hackatime_user_id, projectKey: name },
        headers: headers, timeout: 8)
      next [] unless resp.success?

      body = resp.parsed_response
      next [] unless body.is_a?(Hash) && body["ok"] && body.dig("data", "timelapses")

      body["data"]["timelapses"].select do |t|
        ms = t["createdAt"].to_i
        ms >= start_ms && ms <= end_ms
      end
    rescue StandardError
      []
    end
  end

  # Formats the timelapse list for the Airtable hours justification, or "" if none.
  def self.justification_section(timelapses)
    return "" if timelapses.blank?

    lines = timelapses.map do |t|
      date = Time.at(t["createdAt"].to_i / 1000.0).utc
      date_str = "#{date.strftime('%B')} #{date.day.ordinalize}, #{date.year}"
      "- https://lapse.hackclub.com/timelapse/#{t['id']} (#{format_duration(t['duration'])} on #{date_str})"
    end
    plural = timelapses.length == 1 ? "" : "s"
    "This project has #{timelapses.length} timelapse#{plural} recorded with Lapse:\n#{lines.join("\n")}"
  end

  def self.format_duration(seconds)
    total_minutes = (seconds.to_f / 60).round
    "#{total_minutes / 60}h #{total_minutes % 60}m"
  end
end
