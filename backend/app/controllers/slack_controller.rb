class SlackController < ApplicationController
  def events
    event = params.to_unsafe_h

    if event["type"] == "url_verification"
      return render json: { challenge: event["challenge"] }
    end

    if event["type"] == "event_callback" && event["event"]
      evt = event["event"]
      if evt["type"] == "app_mention"
        token = ENV["SLACK_BOT_TOKEN"]
        unless token.present?
          Rails.logger.error("No SLACK_BOT_TOKEN configured for app_mention response")
          return render json: { ok: true }
        end

        begin
          HTTParty.post(
            "https://slack.com/api/chat.postMessage",
            headers: {
              "Authorization" => "Bearer #{token}",
              "Content-Type" => "application/json"
            },
            body: {
              channel: evt["channel"],
              thread_ts: evt["ts"],
              text: ":scraps: join scraps ---> <https://scraps.hackclub.com?utm_source=slack_mention|https://scraps.hackclub.com> :scraps:",
              unfurl_links: false,
              unfurl_media: false
            }.to_json
          )
        rescue StandardError => e
          Rails.logger.error("Failed to respond to app_mention: #{e.message}")
        end
      end
    end

    render json: { ok: true }
  end
end
