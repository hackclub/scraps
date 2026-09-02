class ProjectsController < ApplicationController
  ALLOWED_IMAGE_DOMAIN = "cdn.hackclub.com"
  ALLOWED_SLACK_ID = "U0828FYS2UC"

  def explore
    page = [params[:page].to_i, 1].max
    limit = [[params[:limit].to_i.nonzero? || 18, 48].min, 1].max
    offset = (page - 1) * limit
    search = params[:search].to_s.strip
    tier = params[:tier].to_i.nonzero?
    status_filter = params[:status].to_s.presence
    sort_by = params[:sortBy].to_s.presence || "default"

    visible_statuses = %w[shipped in_progress waiting_for_review pending_admin_approval]

    where_parts = ["(p.deleted = 0 OR p.deleted IS NULL)", "p.status IN ('shipped','in_progress','waiting_for_review','pending_admin_approval')"]
    bind_values = []

    if search.present?
      bind_idx = bind_values.size + 1
      where_parts << "(p.name ILIKE $#{bind_idx} OR p.description ILIKE $#{bind_idx + 1})"
      bind_values << "%#{search}%" << "%#{search}%"
    end

    if tier && tier.between?(1, 4)
      bind_idx = bind_values.size + 1
      where_parts << "p.tier = $#{bind_idx}"
      bind_values << tier
    end

    if status_filter == "shipped" || status_filter == "in_progress"
      where_parts[1] = "p.status = '#{ActiveRecord::Base.connection.quote_string(status_filter)}'"
    elsif status_filter == "waiting_for_review"
      where_parts[1] = "p.status IN ('waiting_for_review','pending_admin_approval')"
    end

    where_sql = where_parts.join(" AND ")

    order_sql = case sort_by
    when "views" then "p.views DESC"
    when "random" then "RANDOM()"
    else "p.updated_at DESC"
    end

    conn = ActiveRecord::Base.connection
    # Single round trip: join the username in directly and use a window function
    # to get the total count alongside the page, instead of separate queries.
    rows = conn.select_all(
      "SELECT p.id, p.name, p.description, p.image, p.hours, p.hours_override, p.tier, p.status, p.views, p.user_id, u.username,
              COUNT(*) OVER() AS full_count
       FROM projects p
       LEFT JOIN users u ON u.id = p.user_id
       WHERE #{where_sql} ORDER BY #{order_sql} LIMIT #{limit} OFFSET #{offset}",
      "ExploreProjects",
      bind_values.each_with_index.map { |v, i| [nil, v] }
    ).to_a

    # The window function only returns a count when at least one row comes back;
    # fall back to a real count query for out-of-range pages (empty result set).
    total = if rows.any?
      rows.first["full_count"].to_i
    else
      conn.select_one(
        "SELECT COUNT(*) AS cnt FROM projects p WHERE #{where_sql}",
        "ExploreCount",
        bind_values.each_with_index.map { |v, i| [nil, v] }
      )["cnt"].to_i
    end

    data = rows.map do |p|
      desc = p["description"].to_s
      desc_truncated = desc.length > 150 ? "#{desc[0, 150]}..." : desc
      display_status = p["status"] == "pending_admin_approval" ? "waiting_for_review" : p["status"]
      {
        id: p["id"].to_i,
        name: p["name"],
        description: desc_truncated,
        image: p["image"],
        hours: (p["hours_override"] || p["hours"]).to_f,
        tier: p["tier"].to_i,
        status: display_status,
        views: p["views"].to_i,
        username: p["username"]
      }
    end

    render_json({
      data: data,
      pagination: { page: page, limit: limit, total: total, total_pages: (total.to_f / limit).ceil }
    })
  end

  def index
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    page = [params[:page].to_i, 1].max
    limit = [[params[:limit].to_i.nonzero? || 20, 100].min, 1].max
    offset = (page - 1) * limit

    conn = ActiveRecord::Base.connection
    rows = conn.select_all(
      "SELECT p.*, COUNT(*) OVER() AS full_count
       FROM projects p
       WHERE p.user_id = #{current_user.id} AND (p.deleted = 0 OR p.deleted IS NULL)
       ORDER BY p.updated_at DESC LIMIT #{limit} OFFSET #{offset}"
    ).to_a

    total = if rows.any?
      rows.first["full_count"].to_i
    else
      conn.select_one(
        "SELECT COUNT(*) AS cnt FROM projects WHERE user_id = #{current_user.id} AND (deleted = 0 OR deleted IS NULL)"
      )["cnt"].to_i
    end

    data = rows.map { |p| project_row_to_h(p, strip_ids: true) }

    render_json({
      data: data,
      pagination: { page: page, limit: limit, total: total, total_pages: (total.to_f / limit).ceil }
    })
  end

  def show
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    conn = ActiveRecord::Base.connection
    # Single round trip: pull the owner's username/avatar in via join instead of
    # a second lookup.
    project = conn.select_one(
      "SELECT p.*, u.username AS owner_username, u.avatar AS owner_avatar
       FROM projects p
       LEFT JOIN users u ON u.id = p.user_id
       WHERE p.id = #{params[:id].to_i}"
    )
    return render_json({ error: "Not found" }, status: :not_found) unless project

    is_owner = project["user_id"].to_i == current_user.id
    is_staff = %w[admin reviewer creator].include?(current_user.role)

    visible_statuses = %w[shipped in_progress waiting_for_review pending_admin_approval]
    unless is_owner || visible_statuses.include?(project["status"])
      return render_json({ error: "Not found" }, status: :not_found)
    end

    conn.execute("UPDATE projects SET views = views + 1 WHERE id = #{params[:id].to_i}") unless is_owner

    # Only fetch reviewer identity from the DB at all when the viewer is staff -
    # non-staff viewers never see it, so it's never even selected for them.
    reviews_rows = if is_staff
      conn.select_all(
        "SELECT r.id, r.reviewer_id, r.action, r.feedback_for_author, r.created_at, u.username AS reviewer_username, u.avatar AS reviewer_avatar
         FROM reviews r
         LEFT JOIN users u ON u.id = r.reviewer_id
         WHERE r.project_id = #{params[:id].to_i}"
      ).to_a
    else
      conn.select_all(
        "SELECT id, reviewer_id, action, feedback_for_author, created_at FROM reviews WHERE project_id = #{params[:id].to_i}"
      ).to_a
    end

    is_pending_admin = project["status"] == "pending_admin_approval"

    activity = []
    reviews_rows.each do |r|
      next if is_pending_admin && r["action"] == "approved"
      activity << {
        type: "review",
        action: r["action"],
        feedback_for_author: r["feedback_for_author"],
        created_at: r["created_at"],
        reviewer: is_staff ? { id: r["reviewer_id"].to_i, username: r["reviewer_username"], avatar: r["reviewer_avatar"] } : nil
      }
    end

    act_rows = conn.select_all(
      "SELECT action, created_at FROM project_activity WHERE project_id = #{params[:id].to_i} AND (action = 'project_submitted' OR action = 'project_unsubmitted' OR action LIKE 'earned % scraps')"
    )
    act_rows.each do |entry|
      case entry["action"]
      when "project_submitted"
        activity << { type: "submitted", created_at: entry["created_at"] }
      when "project_unsubmitted"
        activity << { type: "unsubmitted", created_at: entry["created_at"] }
      else
        activity << { type: "scraps_earned", action: entry["action"], created_at: entry["created_at"] }
      end
    end

    activity << { type: "created", created_at: project["created_at"] }
    activity.sort_by! { |a| a[:created_at] ? -Time.parse(a[:created_at].to_s).to_i : 0 }

    eff = EffectiveHoursService.compute_for_project(project)
    project_hours = (project["hours_override"] || project["hours"]).to_f

    display_status = project["status"] == "pending_admin_approval" ? "waiting_for_review" : project["status"]

    render_json({
      project: {
        id: project["id"].to_i,
        name: project["name"],
        description: project["description"],
        image: project["image"],
        github_url: project["github_url"],
        playable_url: project["playable_url"],
        hackatime_project: is_owner ? HackatimeService.strip_hackatime_ids(project["hackatime_project"]) : nil,
        hours: project_hours,
        hours_override: is_owner ? project["hours_override"]&.to_f : nil,
        tier: project["tier"].to_i,
        tier_override: is_owner ? project["tier_override"]&.to_i : nil,
        status: display_status,
        scraps_awarded: project["scraps_awarded"].to_i,
        views: project["views"].to_i,
        update_description: project["update_description"],
        ai_description: is_owner ? project["ai_description"] : nil,
        reviewer_notes: is_owner ? project["reviewer_notes"] : nil,
        used_ai: project["ai_description"].present?,
        effective_hours: eff[:effective_hours],
        deducted_hours: eff[:deducted_hours],
        created_at: project["created_at"],
        updated_at: project["updated_at"]
      },
      owner: project["user_id"] ? { id: project["user_id"].to_i, username: project["owner_username"], avatar: project["owner_avatar"] } : nil,
      is_owner: is_owner,
      activity: activity
    })
  end

  def create
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    unless current_user.slack_id == ALLOWED_SLACK_ID
      return render_json({ error: "Scraps has ended. Project creation is disabled." }, status: :forbidden)
    end

    image = params[:image].to_s.presence
    unless valid_image_url?(image)
      return render_json({ error: "Image must be from cdn.hackclub.com" }, status: :unprocessable_entity)
    end

    parsed_ht = parse_hackatime_projects(params[:hackatimeProject].to_s.presence)
    prefixed_ht = prefix_hackatime_ids(parsed_ht, current_user.email, current_user.slack_id)
    tier = [[params[:tier].to_i.nonzero? || 1, 1].max, 4].min

    conn = ActiveRecord::Base.connection
    result = conn.select_one(<<~SQL)
      INSERT INTO projects (user_id, name, description, image, github_url, hackatime_project, hours, tier, update_description, ai_description, status, deleted, views, created_at, updated_at)
      VALUES (
        #{current_user.id},
        #{conn.quote(params[:name])},
        #{conn.quote(params[:description])},
        #{conn.quote(image)},
        #{conn.quote(params[:githubUrl].to_s.presence)},
        #{conn.quote(prefixed_ht)},
        0, #{tier},
        #{conn.quote(params[:updateDescription].to_s.presence)},
        #{conn.quote(params[:aiDescription].to_s.presence)},
        'in_progress', 0, 0, NOW(), NOW()
      ) RETURNING *
    SQL

    if prefixed_ht.present?
      HackatimeSyncJob.perform_later(result["id"].to_i)
    end

    conn.execute(
      "INSERT INTO project_activity (user_id, project_id, action, created_at) VALUES (#{current_user.id}, #{result['id'].to_i}, 'project_created', NOW())"
    )

    render_json(project_row_to_h(result, strip_ids: true), status: :created)
  end

  def update
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    conn = ActiveRecord::Base.connection
    existing = conn.select_one(
      "SELECT * FROM projects WHERE id = #{params[:id].to_i} AND user_id = #{current_user.id}"
    )
    return render_json({ error: "Not found" }, status: :not_found) unless existing

    if %w[waiting_for_review pending_admin_approval].include?(existing["status"])
      return render_json({ error: "Cannot edit project while waiting for review" }, status: :unprocessable_entity)
    end

    image = params.key?(:image) ? params[:image].to_s.presence : :not_set
    if image != :not_set && !valid_image_url?(image)
      return render_json({ error: "Image must be from cdn.hackclub.com" }, status: :unprocessable_entity)
    end

    playable_url = params.key?(:playableUrl) ? params[:playableUrl].to_s.presence : :not_set
    if playable_url != :not_set && playable_url
      err = validate_playable_url(playable_url)
      return render_json({ error: err }, status: :unprocessable_entity) if err
    end

    ht_raw = params.key?(:hackatimeProject) ? params[:hackatimeProject].to_s.presence : :not_set
    prefixed_ht = if ht_raw != :not_set
      prefix_hackatime_ids(parse_hackatime_projects(ht_raw), current_user.email, current_user.slack_id)
    else
      :not_set
    end

    set_parts = ["updated_at = NOW()"]
    set_parts << "name = #{conn.quote(params[:name])}" if params.key?(:name)
    set_parts << "description = #{conn.quote(params[:description])}" if params.key?(:description)
    set_parts << "image = #{conn.quote(image)}" if image != :not_set
    set_parts << "github_url = #{conn.quote(params[:githubUrl].to_s.presence)}" if params.key?(:githubUrl)
    set_parts << "playable_url = #{conn.quote(playable_url)}" if playable_url != :not_set
    set_parts << "hackatime_project = #{conn.quote(prefixed_ht)}" if prefixed_ht != :not_set
    if params.key?(:tier)
      t = [[params[:tier].to_i, 1].max, 4].min
      set_parts << "tier = #{t}"
    end
    set_parts << "update_description = #{conn.quote(params[:updateDescription].to_s.presence)}" if params.key?(:updateDescription)
    set_parts << "ai_description = #{conn.quote(params[:aiDescription].to_s.presence)}" if params.key?(:aiDescription)
    set_parts << "reviewer_notes = #{conn.quote(params[:reviewerNotes].to_s.presence)}" if params.key?(:reviewerNotes)

    updated = conn.select_one(
      "UPDATE projects SET #{set_parts.join(', ')} WHERE id = #{params[:id].to_i} AND user_id = #{current_user.id} RETURNING *"
    )
    return render_json({ error: "Not found" }, status: :not_found) unless updated

    if prefixed_ht != :not_set && prefixed_ht.present?
      HackatimeSyncJob.perform_later(updated["id"].to_i)
    end

    render_json(project_row_to_h(updated, strip_ids: true))
  end

  def destroy
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    conn = ActiveRecord::Base.connection
    updated = conn.select_one(
      "UPDATE projects SET deleted = 1, updated_at = NOW() WHERE id = #{params[:id].to_i} AND user_id = #{current_user.id} RETURNING id"
    )
    return render_json({ error: "Not found" }, status: :not_found) unless updated

    conn.execute(
      "INSERT INTO project_activity (user_id, project_id, action, created_at) VALUES (#{current_user.id}, #{params[:id].to_i}, 'project_deleted', NOW())"
    )

    render_json({ success: true })
  end

  def submit
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    conn = ActiveRecord::Base.connection
    project = conn.select_one(
      "SELECT * FROM projects WHERE id = #{params[:id].to_i} AND user_id = #{current_user.id}"
    )
    return render_json({ error: "Not found" }, status: :not_found) unless project

    unless %w[in_progress shipped].include?(project["status"])
      return render_json({ error: "Project cannot be submitted in current status" }, status: :unprocessable_entity)
    end

    if project["hackatime_project"].present?
      HackatimeSyncJob.perform_now(params[:id].to_i)
    end

    updated = conn.select_one(<<~SQL)
      UPDATE projects SET
        status = 'waiting_for_review',
        updated_at = NOW()
      WHERE id = #{params[:id].to_i}
      RETURNING *
    SQL

    conn.execute(
      "INSERT INTO project_activity (user_id, project_id, action, created_at) VALUES (#{current_user.id}, #{params[:id].to_i}, 'project_submitted', NOW())"
    )

    if ENV["SLACK_BOT_TOKEN"].present? && current_user.slack_id.present?
      SlackService.notify_project_submitted(
        token: ENV["SLACK_BOT_TOKEN"],
        reviewer_channel_id: ENV["SLACK_REVIEWER_CHANNEL_ID"],
        submitter_slack_id: current_user.slack_id,
        project: updated,
        frontend_url: ENV.fetch("FRONTEND_URL") { "http://localhost:5173" }
      ) rescue nil
    end

    render_json(project_row_to_h(updated, strip_ids: true))
  end

  def unsubmit
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    conn = ActiveRecord::Base.connection
    project = conn.select_one(
      "SELECT * FROM projects WHERE id = #{params[:id].to_i} AND user_id = #{current_user.id}"
    )
    return render_json({ error: "Not found" }, status: :not_found) unless project

    unless %w[waiting_for_review pending_admin_approval].include?(project["status"])
      return render_json({ error: "Project can only be unsubmitted while waiting for review" }, status: :unprocessable_entity)
    end

    if project["status"] == "pending_admin_approval"
      conn.execute("DELETE FROM reviews WHERE project_id = #{params[:id].to_i} AND action = 'approved'")
    end

    updated = conn.select_one(
      "UPDATE projects SET status = 'in_progress', updated_at = NOW() WHERE id = #{params[:id].to_i} RETURNING *"
    )

    conn.execute(
      "INSERT INTO project_activity (user_id, project_id, action, created_at) VALUES (#{current_user.id}, #{params[:id].to_i}, 'project_unsubmitted', NOW())"
    )

    render_json(project_row_to_h(updated, strip_ids: true))
  end

  def reviews
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    conn = ActiveRecord::Base.connection
    # Only need `status` afterwards - no reason to pull every column across the
    # wire just to confirm the project exists and belongs to this user.
    project = conn.select_one(
      "SELECT status FROM projects WHERE id = #{params[:id].to_i} AND user_id = #{current_user.id}"
    )
    return render_json({ error: "Not found" }, status: :not_found) unless project

    is_staff = %w[admin reviewer creator].include?(current_user.role)
    # Only fetch reviewer identity from the DB at all when the viewer is staff.
    reviews_rows = if is_staff
      conn.select_all(
        "SELECT r.id, r.reviewer_id, r.action, r.feedback_for_author, r.created_at, u.username AS reviewer_username, u.avatar AS reviewer_avatar
         FROM reviews r
         LEFT JOIN users u ON u.id = r.reviewer_id
         WHERE r.project_id = #{params[:id].to_i}"
      ).to_a
    else
      conn.select_all(
        "SELECT id, action, feedback_for_author, created_at FROM reviews WHERE project_id = #{params[:id].to_i}"
      ).to_a
    end

    is_pending_admin = project["status"] == "pending_admin_approval"
    filtered = is_pending_admin ? reviews_rows.reject { |r| r["action"] == "approved" } : reviews_rows

    render_json(filtered.map do |r|
      {
        id: r["id"].to_i,
        action: r["action"],
        feedback_for_author: r["feedback_for_author"],
        created_at: r["created_at"],
        reviewer: is_staff ? { id: r["reviewer_id"].to_i, username: r["reviewer_username"], avatar: r["reviewer_avatar"] } : nil
      }
    end)
  end

  private

  def valid_image_url?(url)
    return true if url.blank?
    uri = URI.parse(url)
    uri.host == ALLOWED_IMAGE_DOMAIN
  rescue URI::InvalidURIError
    false
  end

  def validate_playable_url(url)
    return nil if url.blank?
    uri = URI.parse(url.strip)
    return "Playable URL must use http or https" unless %w[http https].include?(uri.scheme)
    return "Playable URL must be a valid public URL" unless uri.host&.include?(".")
    nil
  rescue URI::InvalidURIError
    "Playable URL is not a valid URL"
  end

  def parse_hackatime_projects(str)
    return nil if str.blank?
    cleaned = str.split(",").map(&:strip).reject(&:empty?).join(",")
    cleaned.presence
  end

  def prefix_hackatime_ids(hackatime_project, email, slack_id)
    return nil if hackatime_project.blank?
    names = hackatime_project.split(",").map(&:strip).reject(&:empty?)
    return hackatime_project if names.empty?

    already_prefixed = names.all? do |n|
      colon_idx = n.index(":")
      colon_idx && !n.start_with?("U") && n[0, colon_idx].match?(/\A\d+\z/)
    end
    return hackatime_project if already_prefixed

    ht_user = HackatimeService.get_user(email, slack_id)
    return hackatime_project unless ht_user && ht_user[:user_id].is_a?(Integer)

    names.map do |name|
      colon_idx = name.index(":")
      if colon_idx && !name.start_with?("U") && name[0, colon_idx].match?(/\A\d+\z/)
        name
      else
        slash_idx = name.index("/")
        bare_name = (slash_idx && name.start_with?("U")) ? name[(slash_idx + 1)..] : name
        "#{ht_user[:user_id]}:#{bare_name}"
      end
    end.join(",")
  end

  def project_row_to_h(p, strip_ids: false)
    ht = p["hackatime_project"]
    ht = HackatimeService.strip_hackatime_ids(ht) if strip_ids
    display_status = p["status"] == "pending_admin_approval" ? "waiting_for_review" : p["status"]
    {
      id: p["id"].to_i,
      user_id: p["user_id"].to_i,
      name: p["name"],
      description: p["description"],
      image: p["image"],
      github_url: p["github_url"],
      playable_url: p["playable_url"],
      hackatime_project: ht,
      hours: p["hours"].to_f,
      hours_override: p["hours_override"]&.to_f,
      tier: p["tier"].to_i,
      tier_override: p["tier_override"]&.to_i,
      status: display_status,
      scraps_awarded: p["scraps_awarded"].to_i,
      scraps_paid_amount: p["scraps_paid_amount"].to_i,
      views: p["views"].to_i,
      update_description: p["update_description"],
      ai_description: p["ai_description"],
      reviewer_notes: p["reviewer_notes"],
      created_at: p["created_at"],
      updated_at: p["updated_at"]
    }
  end
end
