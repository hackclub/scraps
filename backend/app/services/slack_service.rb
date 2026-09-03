module SlackService
  SCRAPS_URL = "https://scraps.hackclub.com"

  def self.post(token, method, payload)
    HTTParty.post(
      "https://slack.com/api/#{method}",
      headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" },
      body: payload.to_json
    )
  end

  # Adds a user to a Slack channel. The bot must be a member of the channel and
  # have channels:manage (public) / groups:write (private). Returns true if the
  # user is in the channel afterwards (including "was already in it").
  def self.invite_to_channel(token:, channel_id:, user_slack_id:)
    return false unless token.present? && channel_id.present? && user_slack_id.present?

    resp = post(token, "conversations.invite", { channel: channel_id, users: user_slack_id })
    body = resp.parsed_response.is_a?(Hash) ? resp.parsed_response : {}
    return true if body["ok"]
    return true if body["error"] == "already_in_channel"

    Rails.logger.warn("[SlackService] invite #{user_slack_id} -> #{channel_id} failed: #{body['error'] || resp.code}")
    false
  rescue StandardError => e
    Rails.logger.warn("[SlackService] invite error: #{e.message}")
    false
  end

  def self.notify_project_review(user_slack_id:, project_name:, project_id:, action:, feedback_for_author:, reviewer_slack_id: nil, admin_slack_ids: [], scraps_awarded: 0, frontend_url: SCRAPS_URL, token:, rejection_reason: nil)
    return unless token.present? && user_slack_id.present?

    emoji, status_text = case action
    when "approved" then [":tada:", "approved and shipped"]
    when "denied" then [":x:", "needs more work"]
    when "permanently_rejected" then [":no_entry:", "permanently rejected"]
    else [":question:", action]
    end

    author_blocks = [
      { type: "section", text: { type: "mrkdwn", text: "#{emoji} Your project *#{project_name}* has been #{status_text}!" } },
      { type: "section", text: { type: "mrkdwn", text: "*Feedback from reviewer:*\n#{feedback_for_author}" } }
    ]
    author_blocks << { type: "section", text: { type: "mrkdwn", text: ":scraps: You earned *#{scraps_awarded} scraps*!" } } if action == "approved" && scraps_awarded > 0
    author_blocks << { type: "section", text: { type: "mrkdwn", text: "*Reason:* #{rejection_reason}" } } if action == "permanently_rejected" && rejection_reason.present?
    author_blocks << { type: "actions", elements: [{ type: "button", text: { type: "plain_text", text: "View Project" }, url: "#{frontend_url}/projects/#{project_id}", action_id: "view_project" }] }

    post(token, "chat.postMessage", { channel: user_slack_id, text: "Your project has been #{status_text}", blocks: author_blocks }) rescue nil

    if action == "permanently_rejected" && admin_slack_ids.any?
      admin_blocks = [{ type: "section", text: { type: "mrkdwn", text: ":no_entry: *Project permanently rejected*\n*Project:* #{project_name} (ID: #{project_id})\n*Rejected by:* <@#{reviewer_slack_id}>\n*Reason:* #{rejection_reason}" } }]
      admin_slack_ids.each do |admin_id|
        post(token, "chat.postMessage", { channel: admin_id, text: "Project permanently rejected", blocks: admin_blocks }) rescue nil
      end
    end
  end

  def self.notify_shop_win(token:, user_slack_id:, item_name:, item_image: nil, frontend_url: SCRAPS_URL, activity_channel_id: nil)
    return unless token.present?

    if user_slack_id.present?
      blocks = [
        { type: "section", text: { type: "mrkdwn", text: ":tada: *You won #{item_name} from the Scraps shop!*\nCheck your orders to set your shipping address." } },
        { type: "actions", elements: [{ type: "button", text: { type: "plain_text", text: "View Orders" }, url: "#{frontend_url}/shop/orders", action_id: "view_orders" }] }
      ]
      post(token, "chat.postMessage", { channel: user_slack_id, text: "You won #{item_name}!", blocks: blocks }) rescue nil
    end

    # Public announcement in the scraps activity channel.
    if activity_channel_id.present?
      who = user_slack_id.present? ? "<@#{user_slack_id}>" : "Someone"
      feed_blocks = [{ type: "section", text: { type: "mrkdwn", text: ":scraps: :tada: #{who} just won *#{item_name}* from the shop!" } }]
      feed_blocks << { type: "image", image_url: item_image, alt_text: item_name } if item_image.present?
      post(token, "chat.postMessage", { channel: activity_channel_id, text: "#{user_slack_id.present? ? 'A user' : 'Someone'} won #{item_name}", blocks: feed_blocks, unfurl_links: false }) rescue nil
    end
  end

  def self.notify_order_fulfilled(user_slack_id:, item_name:, tracking_number: nil, token:, frontend_url: SCRAPS_URL)
    return unless token.present? && user_slack_id.present?

    text = tracking_number.present? ? ":package: *Your order for #{item_name} has been shipped!*\nTracking: `#{tracking_number}`" : ":package: *Your order for #{item_name} has been fulfilled!*"

    post(token, "chat.postMessage", { channel: user_slack_id, text: text, blocks: [{ type: "section", text: { type: "mrkdwn", text: text } }] }) rescue nil
  end
end
