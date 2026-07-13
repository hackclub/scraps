class HackatimeSyncJob < ApplicationJob
  queue_as :default

  def perform(project_id)
    conn = ActiveRecord::Base.connection

    project = conn.select_one("SELECT p.*, u.email, u.slack_id FROM projects p INNER JOIN users u ON u.id = p.user_id WHERE p.id = #{project_id.to_i}")
    return { hours: nil, updated: false } unless project
    return { hours: project["hours"], updated: false } if project["status"] == "shipped"

    email = project["email"]
    slack_id = project["slack_id"]
    hackatime_project_str = project["hackatime_project"]

    return { hours: project["hours"], updated: false } unless email.present? && hackatime_project_str.present?

    ht_user = HackatimeService.get_user(email, slack_id)
    return { hours: project["hours"], updated: false } unless ht_user

    ht_projects = HackatimeService.fetch_user_projects(ht_user[:user_id])
    return { hours: project["hours"], updated: false } unless ht_projects

    stripped_names = HackatimeService.parse_hackatime_projects(hackatime_project_str)

    total_seconds = ht_projects
      .select { |p| stripped_names.include?(HackatimeService.strip_hackatime_ids(p["name"])) }
      .sum { |p| p["total_duration"].to_f }

    hours = (total_seconds / 3600.0 * 100).round / 100.0
    return { hours: project["hours"].to_f, updated: false } if hours == project["hours"].to_f

    conn.execute("UPDATE projects SET hours = #{hours}, updated_at = NOW() WHERE id = #{project_id.to_i}")
    { hours: hours, updated: true }
  rescue StandardError => e
    Rails.logger.error("[HackatimeSyncJob] Failed for project #{project_id}: #{e.message}")
    { hours: nil, updated: false }
  end
end
