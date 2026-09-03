class SlackChannelJoinJob < ApplicationJob
  queue_as :default

  # The scraps-related channels new users are auto-invited to on first login:
  # #scraps, #scraps-activity, #scraps-bulletin, #scraps-help.
  CHANNELS = %w[C0ADMQFFU56 C0AE5RQV26S C0AE36DGR36 C0ACV8C3MPH].freeze

  # Safe to re-run — "already in channel" is treated as success.
  #
  # Note: a bot token can only invite full workspace members. Guest / restricted
  # accounts (common for new Hack Club folks) will fail here; those need a
  # user-token invite flow, which this deliberately does not do.
  def perform(user_id)
    token = ENV["SLACK_BOT_TOKEN"]
    return if token.blank?

    slack_id = ActiveRecord::Base.connection.select_value(
      "SELECT slack_id FROM users WHERE id = #{user_id.to_i}"
    )
    return if slack_id.blank?

    CHANNELS.each do |cid|
      SlackService.invite_to_channel(token: token, channel_id: cid, user_slack_id: slack_id)
    end
  end
end
