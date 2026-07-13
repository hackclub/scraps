class HackatimeController < ApplicationController
  def projects
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    unless current_user.email.present?
      return render_json({ error: "No email found for user", projects: [] })
    end

    ht_user = HackatimeService.get_user(current_user.email, current_user.slack_id)
    unless ht_user
      return render_json({ projects: [] })
    end

    raw_projects = HackatimeService.fetch_user_projects(ht_user[:user_id])
    unless raw_projects
      return render_json({ projects: [] })
    end

    render_json({
      slack_id: current_user.slack_id,
      projects: raw_projects.map do |p|
        {
          name: p["name"],
          hours: (p["total_duration"].to_f / 3600.0 * 10).round / 10.0,
          repo_url: p["repo"],
          languages: p["languages"] || []
        }
      end
    })
  rescue StandardError => e
    Rails.logger.error("[HACKATIME] Error fetching projects: #{e.message}")
    render_json({ projects: [] })
  end
end
