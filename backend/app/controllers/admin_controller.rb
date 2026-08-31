class AdminController < ApplicationController
  before_action :authenticate_reviewer, only: %i[stats users show_user update_notes update_project_notes reviews show_review submit_review second_pass show_second_pass export_review_csv export_review_json sync_hours]
  before_action :authenticate_admin, only: %i[update_role create_bonus user_bonuses delete_bonus second_pass_submit orders update_order delete_order restore_order shop_items create_shop_item update_shop_item delete_shop_item news_index create_news update_news delete_news scraps_payout_info trigger_payout reject_payout compute_pricing compute_roll_costs fix_negative_balances reset_non_buyer_refinery unship_project user_timeline sync_airtable unified_duplicates recalculate_shop_pricing login_allowlist add_login_allowlist delete_login_allowlist]
  before_action :authenticate_creator, only: %i[delete_user]

  def stats
    conn = ActiveRecord::Base.connection

    users_count = conn.select_one("SELECT COUNT(*) AS cnt FROM users")["cnt"].to_i
    projects_count = conn.select_one("SELECT COUNT(*) AS cnt FROM projects WHERE (deleted = 0 OR deleted IS NULL)")["cnt"].to_i

    shipped = conn.select_all("SELECT id, user_id, hours, hours_override, hackatime_project, tier, tier_override FROM projects WHERE status = 'shipped' AND (deleted = 0 OR deleted IS NULL)").to_a
    pending = conn.select_all("SELECT id, user_id, hours, hours_override, hackatime_project FROM projects WHERE status = 'waiting_for_review'").to_a
    in_progress = conn.select_all("SELECT id, user_id, hours, hours_override, hackatime_project FROM projects WHERE status = 'in_progress'").to_a

    def raw_hours(p)
      (p["hours_override"] || p["hours"]).to_f
    end

    total_hours = shipped.sum { |p| raw_hours(p) }.round(1)
    pending_hours = pending.sum { |p| raw_hours(p) }.round(1)
    in_progress_hours = in_progress.sum { |p| raw_hours(p) }.round(1)

    tier_breakdown = {}
    shipped.each do |p|
      t = (p["tier_override"] || p["tier"] || 1).to_i
      tier_breakdown[t] ||= { hours: 0.0, projects: 0 }
      tier_breakdown[t][:hours] += raw_hours(p)
      tier_breakdown[t][:projects] += 1
    end

    tier_cost_breakdown = tier_breakdown.map do |tier, data|
      mult = ScrapsService::TIER_MULTIPLIERS[tier] || 1.0
      dph = ScrapsService::DOLLARS_PER_HOUR * mult
      { tier: tier, multiplier: mult, dollars_per_hour: (dph * 100).round / 100.0, hours: (data[:hours] * 10).round / 10.0, projects: data[:projects], total_cost: (data[:hours] * dph * 100).round / 100.0 }
    end.sort_by { |t| t[:tier] }

    total_tier_cost = tier_cost_breakdown.sum { |t| t[:total_cost] }

    shop_row = conn.select_one(<<~SQL)
      SELECT
        COALESCE(SUM(total_price),0) AS total_spent,
        COALESCE(SUM(CASE WHEN order_type='purchase' THEN total_price ELSE 0 END),0) AS purchase_spent,
        COALESCE(SUM(CASE WHEN order_type='consolation' THEN total_price ELSE 0 END),0) AS consolation_spent,
        COALESCE(SUM(CASE WHEN order_type='luck_win' THEN total_price ELSE 0 END),0) AS luck_win_spent
      FROM shop_orders
    SQL
    refinery_row = conn.select_one("SELECT COALESCE(SUM(cost),0) AS total FROM refinery_spending_history")

    shop_total = shop_row["total_spent"].to_f
    refinery_total = refinery_row["total"].to_f
    total_scraps_spent = shop_total + refinery_total

    hcb_balance_cents = 0
    if ENV["HCB_ORG_SLUG"].present?
      begin
        resp = HTTParty.get("https://hcb.hackclub.com/api/v3/organizations/#{ENV['HCB_ORG_SLUG']}", headers: { "Accept" => "application/json" })
        hcb_balance_cents = resp.parsed_response.dig("balances", "balance_cents").to_i if resp.success?
      rescue StandardError; end
    end

    render_json({
      total_users: users_count,
      total_projects: projects_count,
      total_hours: total_hours,
      weighted_grants: (total_hours / 10.0 * 100).round / 100.0,
      pending_hours: pending_hours,
      pending_weighted_grants: (pending_hours / 10.0 * 100).round / 100.0,
      in_progress_hours: in_progress_hours,
      in_progress_weighted_grants: (in_progress_hours / 10.0 * 100).round / 100.0,
      shop_stats: {
        total_scraps_spent: total_scraps_spent,
        shop_purchases: shop_row["purchase_spent"].to_f,
        shop_consolations: shop_row["consolation_spent"].to_f,
        shop_luck_wins: shop_row["luck_win_spent"].to_f,
        refinery_upgrades: refinery_total
      },
      tier_cost_breakdown: tier_cost_breakdown,
      total_tier_cost: (total_tier_cost * 100).round / 100.0,
      hcb_balance_cents: hcb_balance_cents
    })
  end

  def users
    page = [params[:page].to_i, 1].max
    limit = [[params[:limit].to_i.nonzero? || 20, 100].min, 1].max
    offset = (page - 1) * limit
    search = params[:search].to_s.strip

    conn = ActiveRecord::Base.connection
    where = "1=1"
    if search.present?
      if search.match?(/\A\d+\z/)
        where = "(id = #{search.to_i} OR username ILIKE #{conn.quote('%' + search + '%')} OR email ILIKE #{conn.quote('%' + search + '%')} OR slack_id ILIKE #{conn.quote('%' + search + '%')})"
        order = "CASE WHEN id = #{search.to_i} THEN 0 ELSE 1 END, created_at DESC"
      else
        where = "(username ILIKE #{conn.quote('%' + search + '%')} OR email ILIKE #{conn.quote('%' + search + '%')} OR slack_id ILIKE #{conn.quote('%' + search + '%')})"
        order = "created_at DESC"
      end
    else
      order = "created_at DESC"
    end

    rows = conn.select_all("SELECT id, username, avatar, slack_id, email, role, internal_notes, created_at FROM users WHERE #{where} ORDER BY #{order} LIMIT #{limit} OFFSET #{offset}").to_a
    total = conn.select_one("SELECT COUNT(*) AS cnt FROM users WHERE #{where}")["cnt"].to_i

    is_admin_user = %w[admin creator].include?(current_user.role)

    data = rows.map do |u|
      bal = ScrapsService.get_user_scraps_balance(u["id"].to_i)[:balance]
      { id: u["id"].to_i, username: u["username"], avatar: u["avatar"], slack_id: u["slack_id"], email: is_admin_user ? u["email"] : nil, scraps: bal, role: u["role"], internal_notes: u["internal_notes"], created_at: u["created_at"] }
    end

    render_json({ data: data, pagination: { page: page, limit: limit, total: total, total_pages: (total.to_f / limit).ceil } })
  end

  def show_user
    target_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    target = conn.select_one("SELECT id, username, avatar, slack_id, email, role, internal_notes, created_at FROM users WHERE id = #{target_id}")
    return render_json({ error: "User not found" }, status: :not_found) unless target

    projects = conn.select_all("SELECT * FROM projects WHERE user_id = #{target_id} ORDER BY updated_at DESC").to_a
    stats = {
      total: projects.length,
      shipped: projects.count { |p| p["status"] == "shipped" },
      in_progress: projects.count { |p| p["status"] == "in_progress" },
      waiting_for_review: projects.count { |p| p["status"] == "waiting_for_review" },
      rejected: projects.count { |p| p["status"] == "permanently_rejected" },
      total_hours: projects.sum { |p| (p["hours_override"] || p["hours"]).to_f }
    }

    balance = ScrapsService.get_user_scraps_balance(target_id)
    ht_suspected = false
    ht_banned = false
    if target["email"].present?
      begin
        ht = HackatimeService.get_user(target["email"], target["slack_id"])
        ht_suspected = ht[:suspected] || false
        ht_banned = ht[:banned] || false
      rescue StandardError; end
    end

    is_admin_user = %w[admin creator].include?(current_user.role)
    render_json({
      user: { id: target["id"].to_i, username: target["username"], avatar: target["avatar"], slack_id: target["slack_id"], email: is_admin_user ? target["email"] : nil, scraps: balance[:balance], role: target["role"], internal_notes: target["internal_notes"], created_at: target["created_at"] },
      hackatime_suspected: ht_suspected,
      hackatime_banned: ht_banned,
      projects: projects,
      stats: stats
    })
  end

  def update_role
    role = params[:role].to_s
    return render_json({ error: "Invalid role" }, status: :bad_request) unless %w[member reviewer admin creator banned].include?(role)
    return render_json({ error: "Cannot change your own role" }, status: :bad_request) if current_user.id == params[:id].to_i

    conn = ActiveRecord::Base.connection
    updated = conn.select_one("UPDATE users SET role = #{conn.quote(role)}, updated_at = NOW() WHERE id = #{params[:id].to_i} RETURNING id")
    return render_json({ error: "Not Found" }, status: :not_found) unless updated
    render_json({ success: true })
  end

  def update_notes
    notes = params[:internalNotes].to_s
    return render_json({ error: "Note is too long or it's malformed!" }, status: :bad_request) if notes.length > 2500

    conn = ActiveRecord::Base.connection
    updated = conn.select_one("UPDATE users SET internal_notes = #{conn.quote(notes)}, updated_at = NOW() WHERE id = #{params[:id].to_i} RETURNING id")
    return render_json({ error: "Not Found" }, status: :not_found) unless updated
    render_json({ success: true })
  end

  def update_project_notes
    notes = params[:internalNotes].to_s
    return render_json({ error: "Note is too long or it's malformed!" }, status: :bad_request) if notes.length > 2500

    conn = ActiveRecord::Base.connection
    updated = conn.select_one("UPDATE projects SET internal_notes = #{conn.quote(notes)}, updated_at = NOW() WHERE id = #{params[:id].to_i} RETURNING id")
    return render_json({ error: "Not Found" }, status: :not_found) unless updated
    render_json({ success: true })
  end

  def create_bonus
    amount = params[:amount].to_i
    reason = params[:reason].to_s.strip
    return render_json({ error: "Amount is required and must be a non-zero integer" }, status: :bad_request) if amount == 0
    return render_json({ error: "Reason is required" }, status: :bad_request) if reason.blank?
    return render_json({ error: "Reason is too long (max 500 characters)" }, status: :bad_request) if reason.length > 500

    conn = ActiveRecord::Base.connection
    target = conn.select_one("SELECT id FROM users WHERE id = #{params[:id].to_i}")
    return render_json({ error: "User not found" }, status: :not_found) unless target

    bonus = conn.select_one(<<~SQL)
      INSERT INTO user_bonuses (user_id, amount, reason, given_by, created_at)
      VALUES (#{params[:id].to_i}, #{amount}, #{conn.quote(reason)}, #{current_user.id}, NOW())
      RETURNING *
    SQL
    render_json({ id: bonus["id"].to_i, amount: bonus["amount"].to_i, reason: bonus["reason"], given_by: bonus["given_by"]&.to_i, created_at: bonus["created_at"] })
  end

  def user_bonuses
    rows = ActiveRecord::Base.connection.select_all(<<~SQL).to_a
      SELECT ub.id, ub.amount, ub.reason, ub.given_by, u.username AS given_by_username, ub.created_at
      FROM user_bonuses ub
      LEFT JOIN users u ON u.id = ub.given_by
      WHERE ub.user_id = #{params[:id].to_i}
      ORDER BY ub.created_at DESC
    SQL
    render_json(rows.map { |b| { id: b["id"].to_i, amount: b["amount"].to_i, reason: b["reason"], given_by: b["given_by"]&.to_i, given_by_username: b["given_by_username"], created_at: b["created_at"] } })
  end

  def delete_bonus
    bonus_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    bonus = conn.select_one("SELECT id FROM user_bonuses WHERE id = #{bonus_id}")
    return render_json({ error: "Bonus not found" }, status: :not_found) unless bonus
    conn.execute("DELETE FROM user_bonuses WHERE id = #{bonus_id}")
    render_json({ success: true })
  end

  def reviews
    page = [params[:page].to_i, 1].max
    limit = [[params[:limit].to_i.nonzero? || 20, 100].min, 1].max
    offset = (page - 1) * limit
    sort = params[:sort] == "newest" ? "updated_at DESC" : "updated_at ASC"

    conn = ActiveRecord::Base.connection
    rows = conn.select_all("SELECT * FROM projects WHERE status = 'waiting_for_review' ORDER BY #{sort} LIMIT #{limit} OFFSET #{offset}").to_a
    total = conn.select_one("SELECT COUNT(*) AS cnt FROM projects WHERE status = 'waiting_for_review'")["cnt"].to_i

    data = rows.map do |p|
      eff = EffectiveHoursService.compute_for_project(p)
      p.merge("effective_hours" => eff[:effective_hours], "deducted_hours" => eff[:deducted_hours])
    end

    render_json({ data: data, pagination: { page: page, limit: limit, total: total, total_pages: (total.to_f / limit).ceil } })
  end

  def show_review
    conn = ActiveRecord::Base.connection
    project = conn.select_one("SELECT * FROM projects WHERE id = #{params[:id].to_i}")
    return render_json({ error: "Project not found!" }, status: :not_found) unless project

    project_user = conn.select_one("SELECT id, username, email, slack_id, avatar, internal_notes FROM users WHERE id = #{project['user_id'].to_i}")
    reviews_rows = conn.select_all("SELECT * FROM reviews WHERE project_id = #{params[:id].to_i}").to_a

    reviewer_ids = reviews_rows.map { |r| r["reviewer_id"].to_i }.uniq
    reviewers = {}
    conn.select_all("SELECT id, username, avatar FROM users WHERE id IN (#{reviewer_ids.join(',')})").each { |u| reviewers[u["id"].to_i] = u } if reviewer_ids.any?

    ht_user_id = nil
    ht_suspected = false
    ht_banned = false
    if project_user&.dig("email")
      begin
        ht = HackatimeService.get_user(project_user["email"], project_user["slack_id"])
        if ht
          ht_user_id = ht[:user_id]
          ht_suspected = ht[:suspected] || false
          ht_banned = ht[:banned] || false
        end
      rescue StandardError; end
    end

    ysws_dupes = search_unified_airtable(project["github_url"], project["playable_url"]) rescue []

    is_admin_user = %w[admin creator].include?(current_user.role)
    masked_project = (!is_admin_user && project["status"] == "pending_admin_approval") ? project.merge("status" => "waiting_for_review") : project
    # Show the bare Hackatime project name(s) in the review UI, not the stored "<id>:name" form.
    masked_project = masked_project.merge("hackatime_project" => HackatimeService.strip_hackatime_ids(masked_project["hackatime_project"]))
    visible_reviews = (!is_admin_user && project["status"] == "pending_admin_approval") ? reviews_rows.reject { |r| r["action"] == "approved" } : reviews_rows

    eff = EffectiveHoursService.compute_for_project(project)

    # Per-Hackatime-project hour breakdown for the project(s) attached to this submission.
    ht_breakdown = []
    if ht_user_id && project["hackatime_project"].present?
      begin
        target_names = HackatimeService.strip_hackatime_ids(project["hackatime_project"])
          .to_s.split(",").map(&:strip).reject(&:empty?)
        by_name = (HackatimeService.fetch_user_projects(ht_user_id) || [])
          .group_by { |p| HackatimeService.strip_hackatime_ids(p["name"]) }
        ht_breakdown = target_names.map do |name|
          secs = (by_name[name] || []).sum { |p| p["total_duration"].to_f }
          { name: name, hours: (secs / 3600.0 * 100).round / 100.0, found: by_name.key?(name) }
        end
      rescue StandardError
        ht_breakdown = []
      end
    end

    render_json({
      project: masked_project,
      hackatime_user_id: ht_user_id,
      hackatime_suspected: ht_suspected,
      hackatime_banned: ht_banned,
      hackatime_projects: ht_breakdown,
      project_internal_notes: project["internal_notes"],
      ysws_duplicates: ysws_dupes,
      user: project_user ? { id: project_user["id"].to_i, username: project_user["username"], email: is_admin_user ? project_user["email"] : nil, avatar: project_user["avatar"], internal_notes: project_user["internal_notes"] } : nil,
      reviews: visible_reviews.map { |r| r.merge("reviewer_name" => reviewers[r["reviewer_id"].to_i]&.dig("username"), "reviewer_avatar" => reviewers[r["reviewer_id"].to_i]&.dig("avatar")) },
      effective_hours: eff[:effective_hours],
      deducted_hours: eff[:deducted_hours]
    })
  end

  def submit_review
    action = params[:action].to_s
    feedback = params[:feedbackForAuthor].to_s.strip
    rejection_reason = params[:rejectionReason].to_s.strip
    hours_override = params[:hoursOverride]&.to_f
    tier_override = params[:tierOverride]&.to_i
    user_notes = params[:userInternalNotes]
    project_notes = params[:projectInternalNotes]

    return render_json({ error: "Invalid action" }) unless %w[approved denied permanently_rejected].include?(action)
    return render_json({ error: "Feedback for author is required" }) if feedback.blank?
    return render_json({ error: "Reason shown to user is required for permanent rejection" }) if action == "permanently_rejected" && rejection_reason.blank?

    project_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    project = conn.select_one("SELECT * FROM projects WHERE id = #{project_id}")
    return render_json({ error: "Project not found" }, status: :not_found) unless project
    return render_json({ error: "Hours override cannot exceed project hours" }) if hours_override && hours_override > project["hours"].to_f
    return render_json({ error: "Cannot review a deleted project" }) if project["deleted"].to_i == 1
    return render_json({ error: "Project is not marked for review" }) unless project["status"] == "waiting_for_review"

    if action == "approved" && project["github_url"].present?
      dupe = conn.select_one("SELECT id FROM projects WHERE github_url = #{conn.quote(project['github_url'])} AND status = 'shipped' AND (deleted = 0 OR deleted IS NULL) AND user_id != #{project['user_id'].to_i} LIMIT 1")
      return render_json({ error: "A shipped project with this Code URL already exists (from another user).", duplicate_code_url: true }) if dupe
    end

    conn.execute(<<~SQL)
      INSERT INTO reviews (project_id, reviewer_id, action, feedback_for_author, internal_justification, created_at)
      VALUES (#{project_id}, #{current_user.id}, #{conn.quote(action)}, #{conn.quote(feedback)}, #{conn.quote(params[:internalJustification].to_s.presence)}, NOW())
    SQL

    can_ship = %w[admin creator].include?(current_user.role)
    new_status = case action
    when "approved" then can_ship ? "shipped" : "pending_admin_approval"
    when "denied" then "in_progress"
    when "permanently_rejected" then "permanently_rejected"
    end

    set_parts = ["status = '#{new_status}'", "updated_at = NOW()"]
    set_parts << "hours_override = #{hours_override}" if hours_override
    set_parts << "tier_override = #{tier_override}" if tier_override

    scraps_awarded = 0
    if action == "approved" && can_ship
      tier = (tier_override || project["tier_override"] || project["tier"] || 1).to_i
      proj_with_override = project.merge("hours_override" => hours_override || project["hours_override"])
      eff = EffectiveHoursService.compute_for_project(proj_with_override)
      new_scraps = ScrapsService.calculate_scraps_from_hours(eff[:effective_hours], tier)
      previously_shipped = conn.select_one("SELECT 1 FROM project_activity WHERE project_id = #{project_id} AND action = 'project_shipped' LIMIT 1")
      scraps_awarded = (previously_shipped && project["scraps_awarded"].to_i > 0) ? [0, new_scraps - project["scraps_awarded"].to_i].max : new_scraps
      set_parts << "scraps_awarded = #{new_scraps}"
      set_parts << "scraps_paid_at = NULL" if previously_shipped
    end

    conn.execute("UPDATE projects SET #{set_parts.join(', ')} WHERE id = #{project_id}")

    if action == "approved" && can_ship
      previously_shipped = conn.select_one("SELECT 1 FROM project_activity WHERE project_id = #{project_id} AND action = 'project_shipped' LIMIT 1")
      if scraps_awarded > 0
        conn.execute("INSERT INTO project_activity (user_id, project_id, action, created_at) VALUES (#{project['user_id'].to_i}, #{project_id}, #{conn.quote(previously_shipped ? "earned #{scraps_awarded} additional scraps (update)" : "earned #{scraps_awarded} scraps")}, NOW())")
      end
      conn.execute("INSERT INTO project_activity (user_id, project_id, action, created_at) VALUES (#{project['user_id'].to_i}, #{project_id}, '#{previously_shipped ? 'project_updated' : 'project_shipped'}', NOW())")
      AirtableSyncJob.perform_later rescue nil
    end

    if user_notes.present? && user_notes.length <= 2500
      conn.execute("UPDATE users SET internal_notes = #{conn.quote(user_notes)}, updated_at = NOW() WHERE id = #{project['user_id'].to_i}")
    end

    unless project_notes.nil?
      pn = project_notes.to_s
      conn.execute("UPDATE projects SET internal_notes = #{conn.quote(pn)}, updated_at = NOW() WHERE id = #{project_id}") if pn.length <= 2500
    end

    should_notify = can_ship || action != "approved"
    if ENV["SLACK_BOT_TOKEN"].present? && should_notify
      author = conn.select_one("SELECT slack_id FROM users WHERE id = #{project['user_id'].to_i}")
      if author&.dig("slack_id")
        admin_slack_ids = []
        if action == "permanently_rejected"
          admin_slack_ids = conn.select_all("SELECT slack_id FROM users WHERE role IN ('admin','creator')").map { |r| r["slack_id"] }.compact
        end
        SlackService.notify_project_review(
          user_slack_id: author["slack_id"],
          project_name: project["name"],
          project_id: project_id,
          action: action,
          feedback_for_author: feedback,
          rejection_reason: rejection_reason.presence,
          reviewer_slack_id: current_user.slack_id,
          admin_slack_ids: admin_slack_ids,
          scraps_awarded: scraps_awarded,
          frontend_url: ENV.fetch("FRONTEND_URL") { "http://localhost:5173" },
          token: ENV["SLACK_BOT_TOKEN"]
        ) rescue nil
      end
    end

    render_json({ success: true })
  end

  def second_pass
    page = [params[:page].to_i, 1].max
    limit = [[params[:limit].to_i.nonzero? || 20, 100].min, 1].max
    offset = (page - 1) * limit
    sort = params[:sort] == "newest" ? "DESC" : "ASC"

    conn = ActiveRecord::Base.connection
    rows = conn.select_all(<<~SQL).to_a
      SELECT p.*, COALESCE((SELECT MAX(pa.created_at) FROM project_activity pa WHERE pa.project_id = p.id AND pa.action = 'project_submitted'), p.updated_at) AS submitted_at
      FROM projects p
      WHERE p.status = 'pending_admin_approval'
      ORDER BY submitted_at #{sort}
      LIMIT #{limit} OFFSET #{offset}
    SQL
    total = conn.select_one("SELECT COUNT(*) AS cnt FROM projects WHERE status = 'pending_admin_approval'")["cnt"].to_i

    data = rows.map { |p| eff = EffectiveHoursService.compute_for_project(p); p.merge("effective_hours" => eff[:effective_hours], "deducted_hours" => eff[:deducted_hours]) }
    render_json({ data: data, pagination: { page: page, limit: limit, total: total, total_pages: (total.to_f / limit).ceil } })
  end

  def show_second_pass
    conn = ActiveRecord::Base.connection
    project = conn.select_one("SELECT * FROM projects WHERE id = #{params[:id].to_i}")
    return render_json({ error: "Project not found!" }, status: :not_found) unless project
    return render_json({ error: "Project is not pending admin approval" }) unless project["status"] == "pending_admin_approval"

    project_user = conn.select_one("SELECT id, username, email, slack_id, avatar, internal_notes FROM users WHERE id = #{project['user_id'].to_i}")
    reviews_rows = conn.select_all("SELECT * FROM reviews WHERE project_id = #{params[:id].to_i}").to_a
    reviewer_ids = reviews_rows.map { |r| r["reviewer_id"].to_i }.uniq
    reviewers = {}
    conn.select_all("SELECT id, username, avatar FROM users WHERE id IN (#{reviewer_ids.join(',')})").each { |u| reviewers[u["id"].to_i] = u } if reviewer_ids.any?

    ht_user_id = nil; ht_suspected = false; ht_banned = false
    if project_user&.dig("email")
      begin
        ht = HackatimeService.get_user(project_user["email"], project_user["slack_id"])
        if ht; ht_user_id = ht[:user_id]; ht_suspected = ht[:suspected] || false; ht_banned = ht[:banned] || false; end
      rescue StandardError; end
    end

    eff = EffectiveHoursService.compute_for_project(project)
    render_json({
      project: project.merge("hackatime_project" => HackatimeService.strip_hackatime_ids(project["hackatime_project"])),
      hackatime_user_id: ht_user_id,
      hackatime_suspected: ht_suspected,
      hackatime_banned: ht_banned,
      user: project_user ? { id: project_user["id"].to_i, username: project_user["username"], email: project_user["email"], avatar: project_user["avatar"], internal_notes: project_user["internal_notes"] } : nil,
      reviews: reviews_rows.map { |r| r.merge("reviewer_name" => reviewers[r["reviewer_id"].to_i]&.dig("username"), "reviewer_avatar" => reviewers[r["reviewer_id"].to_i]&.dig("avatar")) },
      effective_hours: eff[:effective_hours],
      deducted_hours: eff[:deducted_hours]
    })
  end

  def second_pass_submit
    action = params[:action].to_s
    return render_json({ error: 'Invalid action. Must be "accept" or "reject"' }) unless %w[accept reject].include?(action)

    project_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    project = conn.select_one("SELECT * FROM projects WHERE id = #{project_id}")
    return render_json({ error: "Project not found" }, status: :not_found) unless project
    return render_json({ error: "Project is not pending admin approval" }) unless project["status"] == "pending_admin_approval"

    if action == "accept"
      hours_override = params[:hoursOverride]&.to_f
      conn.execute("UPDATE projects SET hours_override = #{hours_override} WHERE id = #{project_id}") if hours_override
      proj_for_calc = conn.select_one("SELECT * FROM projects WHERE id = #{project_id}")
      tier = (proj_for_calc["tier_override"] || proj_for_calc["tier"] || 1).to_i
      eff = EffectiveHoursService.compute_for_project(proj_for_calc)
      new_scraps = ScrapsService.calculate_scraps_from_hours(eff[:effective_hours], tier)
      previously_shipped = conn.select_one("SELECT 1 FROM project_activity WHERE project_id = #{project_id} AND action = 'project_shipped' LIMIT 1")
      scraps_awarded = (previously_shipped && project["scraps_awarded"].to_i > 0) ? [0, new_scraps - project["scraps_awarded"].to_i].max : new_scraps

      set_sql = "status = 'shipped', scraps_awarded = #{new_scraps}, updated_at = NOW()"
      set_sql += ", scraps_paid_at = NULL" if previously_shipped
      conn.execute("UPDATE projects SET #{set_sql} WHERE id = #{project_id}")

      if scraps_awarded > 0
        conn.execute("INSERT INTO project_activity (user_id, project_id, action, created_at) VALUES (#{project['user_id'].to_i}, #{project_id}, #{conn.quote(previously_shipped ? "earned #{scraps_awarded} additional scraps (update)" : "earned #{scraps_awarded} scraps")}, NOW())")
      end
      conn.execute("INSERT INTO project_activity (user_id, project_id, action, created_at) VALUES (#{project['user_id'].to_i}, #{project_id}, '#{previously_shipped ? 'project_updated' : 'project_shipped'}', NOW())")

      if ENV["SLACK_BOT_TOKEN"].present?
        author = conn.select_one("SELECT slack_id FROM users WHERE id = #{project['user_id'].to_i}")
        if author&.dig("slack_id")
          SlackService.notify_project_review(user_slack_id: author["slack_id"], project_name: project["name"], project_id: project_id, action: "approved", feedback_for_author: "Your project has been approved and shipped!", reviewer_slack_id: current_user.slack_id, admin_slack_ids: [], scraps_awarded: scraps_awarded, frontend_url: ENV.fetch("FRONTEND_URL") { "http://localhost:5173" }, token: ENV["SLACK_BOT_TOKEN"]) rescue nil
        end
      end
      AirtableSyncJob.perform_later rescue nil
      render_json({ success: true, scraps_awarded: scraps_awarded })
    else
      conn.execute("DELETE FROM reviews WHERE project_id = #{project_id} AND action = 'approved'")
      feedback = params[:feedbackForAuthor].to_s.presence || "The admin has rejected the initial approval. Please make improvements and resubmit."
      conn.execute(<<~SQL)
        INSERT INTO reviews (project_id, reviewer_id, action, feedback_for_author, internal_justification, created_at)
        VALUES (#{project_id}, #{current_user.id}, 'denied', #{conn.quote(feedback)}, 'Second-pass rejection', NOW())
      SQL
      conn.execute("UPDATE projects SET status = 'in_progress', updated_at = NOW() WHERE id = #{project_id}")
      if ENV["SLACK_BOT_TOKEN"].present?
        author = conn.select_one("SELECT slack_id FROM users WHERE id = #{project['user_id'].to_i}")
        if author&.dig("slack_id")
          SlackService.notify_project_review(user_slack_id: author["slack_id"], project_name: project["name"], project_id: project_id, action: "denied", feedback_for_author: feedback, reviewer_slack_id: current_user.slack_id, admin_slack_ids: [], scraps_awarded: 0, frontend_url: ENV.fetch("FRONTEND_URL") { "http://localhost:5173" }, token: ENV["SLACK_BOT_TOKEN"]) rescue nil
        end
      end
      render_json({ success: true })
    end
  end

  def scraps_payout_info
    conn = ActiveRecord::Base.connection
    pending = conn.select_all("SELECT p.id, p.name, p.image, p.scraps_awarded, p.hours, p.hours_override, p.user_id, p.status, p.created_at FROM projects p WHERE p.status = 'shipped' AND p.scraps_paid_at IS NULL AND p.scraps_awarded > 0 AND (p.deleted = 0 OR p.deleted IS NULL)").to_a
    user_ids = pending.map { |p| p["user_id"].to_i }.uniq
    users = {}
    conn.select_all("SELECT id, username, avatar FROM users WHERE id IN (#{user_ids.join(',')})").each { |u| users[u["id"].to_i] = u } if user_ids.any?

    render_json({
      pending_projects: pending.length,
      pending_scraps: pending.sum { |p| p["scraps_awarded"].to_i },
      projects: pending.map { |p| p.merge("owner" => users[p["user_id"].to_i]) },
      next_payout_date: ScrapsService.next_payout_date.iso8601
    })
  end

  def trigger_payout
    result = ScrapPayoutJob.perform_now_sync
    render_json({ success: true, paid_count: result[:paid_count], total_scraps: result[:total_scraps] })
  rescue StandardError => e
    render_json({ error: "Failed to trigger payout: #{e.message}" }, status: :internal_server_error)
  end

  def reject_payout
    project_id = params[:projectId].to_i
    reason = params[:reason].to_s.strip
    return render_json({ error: "Project ID is required" }, status: :bad_request) unless project_id > 0
    return render_json({ error: "A reason is required" }, status: :bad_request) if reason.blank?

    conn = ActiveRecord::Base.connection
    project = conn.select_one("SELECT id, user_id, scraps_awarded, scraps_paid_at, status, name FROM projects WHERE id = #{project_id}")
    return render_json({ error: "Project not found" }, status: :not_found) unless project
    return render_json({ error: "Scraps have already been paid out" }, status: :bad_request) if project["scraps_paid_at"]
    return render_json({ error: "No scraps to reject" }, status: :bad_request) if project["scraps_awarded"].to_i <= 0

    previous = project["scraps_awarded"].to_i
    conn.execute("UPDATE projects SET scraps_awarded = 0, status = 'in_progress', updated_at = NOW() WHERE id = #{project_id}")
    conn.execute(<<~SQL)
      INSERT INTO reviews (project_id, reviewer_id, action, feedback_for_author, created_at)
      VALUES (#{project_id}, #{current_user.id}, 'scraps_unawarded', #{conn.quote("Payout rejected (#{previous} scraps): #{reason}")}, NOW())
    SQL
    render_json({ success: true, previous_scraps: previous })
  end

  def orders
    conn = ActiveRecord::Base.connection
    status_filter = params[:status].to_s.presence
    where = status_filter ? "WHERE so.status = #{conn.quote(status_filter)}" : ""

    rows = conn.select_all(<<~SQL).to_a
      SELECT so.id, so.quantity, so.price_per_item, so.total_price, so.status, so.order_type,
             so.notes, so.tracking_number, so.is_fulfilled, so.shipping_address, so.phone, so.created_at,
             si.id AS item_id, si.name AS item_name, si.image AS item_image,
             u.id AS user_id, u.username, u.slack_id, u.email AS user_email
      FROM shop_orders so
      INNER JOIN shop_items si ON si.id = so.shop_item_id
      INNER JOIN users u ON u.id = so.user_id
      #{where}
      ORDER BY so.created_at DESC
    SQL

    emails = rows.map { |r| r["user_email"] }.compact.uniq
    ban_map = {}
    slack_map = rows.each_with_object({}) { |r, h| h[r["user_email"]] = r["slack_id"] if r["user_email"] }
    emails.each do |email|
      begin
        ht = HackatimeService.get_user(email, slack_map[email])
        ban_map[email] = ht&.dig(:banned) || false
      rescue StandardError
        ban_map[email] = false
      end
    end

    render_json(rows.map { |r|
      { id: r["id"].to_i, quantity: r["quantity"].to_i, price_per_item: r["price_per_item"].to_i, total_price: r["total_price"].to_i, status: r["status"], order_type: r["order_type"], notes: r["notes"], tracking_number: r["tracking_number"], is_fulfilled: r["is_fulfilled"], shipping_address: r["shipping_address"], phone: r["phone"], created_at: r["created_at"], item_id: r["item_id"].to_i, item_name: r["item_name"], item_image: r["item_image"], user_id: r["user_id"].to_i, username: r["username"], slack_id: r["slack_id"], email: r["user_email"], hackatime_banned: ban_map[r["user_email"]] || false }
    })
  end

  def update_order
    order_id = params[:id].to_i
    order_status = params[:status].to_s.presence
    valid_statuses = %w[pending processing shipped delivered cancelled deleted]
    return render_json({ error: "Invalid status" }, status: :bad_request) if order_status && !valid_statuses.include?(order_status)

    conn = ActiveRecord::Base.connection
    current_order = conn.select_one("SELECT id, status, order_type, shop_item_id, quantity FROM shop_orders WHERE id = #{order_id}")
    return render_json({ error: "Not found" }, status: :not_found) unless current_order

    if order_status && %w[purchase luck_win].include?(current_order["order_type"])
      was_inactive = %w[cancelled deleted].include?(current_order["status"])
      will_be_inactive = %w[cancelled deleted].include?(order_status)
      qty = current_order["quantity"].to_i

      if !was_inactive && will_be_inactive
        conn.execute("UPDATE shop_items SET count = count + #{qty}, updated_at = NOW() WHERE id = #{current_order['shop_item_id'].to_i}")
      elsif was_inactive && !will_be_inactive
        conn.execute("UPDATE shop_items SET count = GREATEST(count - #{qty}, 0), updated_at = NOW() WHERE id = #{current_order['shop_item_id'].to_i}")
      end
    end

    set_parts = ["updated_at = NOW()"]
    set_parts << "status = #{conn.quote(order_status)}" if order_status
    set_parts << "notes = #{conn.quote(params[:notes].to_s)}" if params.key?(:notes)
    set_parts << "tracking_number = #{conn.quote(params[:trackingNumber].to_s)}" if params.key?(:trackingNumber)
    set_parts << "is_fulfilled = #{params[:isFulfilled] ? 'true' : 'false'}" if params.key?(:isFulfilled)

    updated = conn.select_one("UPDATE shop_orders SET #{set_parts.join(', ')} WHERE id = #{order_id} RETURNING *")
    return render_json({ error: "Not found" }, status: :not_found) unless updated

    if params[:isFulfilled] && ENV["SLACK_BOT_TOKEN"].present?
      order_user = conn.select_one("SELECT u.slack_id, si.name AS item_name FROM shop_orders so INNER JOIN users u ON u.id = so.user_id INNER JOIN shop_items si ON si.id = so.shop_item_id WHERE so.id = #{order_id}")
      if order_user&.dig("slack_id")
        SlackService.notify_order_fulfilled(user_slack_id: order_user["slack_id"], item_name: order_user["item_name"], tracking_number: updated["tracking_number"], token: ENV["SLACK_BOT_TOKEN"]) rescue nil
      end
    end

    render_json({ id: updated["id"].to_i, status: updated["status"], order_type: updated["order_type"], notes: updated["notes"], tracking_number: updated["tracking_number"], is_fulfilled: updated["is_fulfilled"], shipping_address: updated["shipping_address"], created_at: updated["created_at"] })
  end

  def delete_order
    order_id = params[:id].to_i
    reason = params[:reason].to_s.strip
    return render_json({ error: "Provide a short reason (min 3 chars)" }, status: :bad_request) if reason.length < 3

    conn = ActiveRecord::Base.connection
    order = conn.select_one("SELECT so.*, si.name AS item_name FROM shop_orders so INNER JOIN shop_items si ON si.id = so.shop_item_id WHERE so.id = #{order_id}")
    return render_json({ error: "Order not found" }, status: :not_found) unless order

    already = conn.select_one("SELECT 1 FROM admin_deleted_orders WHERE original_order_id = #{order_id} AND restored = false LIMIT 1") rescue nil
    return render_json({ error: "Order already archived" }, status: :conflict) if already

    refinery_orders = conn.select_all("SELECT * FROM refinery_orders WHERE user_id = #{order['user_id'].to_i} AND shop_item_id = #{order['shop_item_id'].to_i}").to_a
    refinery_history = conn.select_all("SELECT * FROM refinery_spending_history WHERE user_id = #{order['user_id'].to_i} AND shop_item_id = #{order['shop_item_id'].to_i}").to_a
    rolls = conn.select_all("SELECT * FROM shop_rolls WHERE user_id = #{order['user_id'].to_i} AND shop_item_id = #{order['shop_item_id'].to_i}").to_a
    penalties = conn.select_all("SELECT * FROM shop_penalties WHERE user_id = #{order['user_id'].to_i} AND shop_item_id = #{order['shop_item_id'].to_i}").to_a

    payload = { order: order, refineryOrders: refinery_orders, refineryHistory: refinery_history, shopRolls: rolls, shopPenalties: penalties }.to_json

    ActiveRecord::Base.transaction do
      conn.execute(<<~SQL)
        INSERT INTO admin_deleted_orders (original_order_id, user_id, shop_item_id, quantity, price_per_item, total_price, status, order_type, shipping_address, phone, item_name, created_at, deleted_payload, deleted_by, deleted_at, reason)
        VALUES (#{order_id}, #{order['user_id'].to_i}, #{order['shop_item_id'].to_i}, #{order['quantity'].to_i}, #{order['price_per_item'].to_i}, #{order['total_price'].to_i}, #{conn.quote(order['status'])}, #{conn.quote(order['order_type'])}, #{conn.quote(order['shipping_address'])}, #{conn.quote(order['phone'])}, #{conn.quote(order['item_name'])}, #{conn.quote(order['created_at'].to_s)}, #{conn.quote(payload)}::jsonb, #{current_user.id}, NOW(), #{conn.quote(reason)})
      SQL

      conn.execute("DELETE FROM refinery_spending_history WHERE user_id = #{order['user_id'].to_i} AND shop_item_id = #{order['shop_item_id'].to_i}")
      conn.execute("DELETE FROM refinery_orders WHERE user_id = #{order['user_id'].to_i} AND shop_item_id = #{order['shop_item_id'].to_i}")
      conn.execute("DELETE FROM shop_rolls WHERE user_id = #{order['user_id'].to_i} AND shop_item_id = #{order['shop_item_id'].to_i}")

      if order["order_type"] == "luck_win"
        penalty = conn.select_one("SELECT probability_multiplier FROM shop_penalties WHERE user_id = #{order['user_id'].to_i} AND shop_item_id = #{order['shop_item_id'].to_i}")
        if penalty
          restored = [100, penalty["probability_multiplier"].to_f * 2].min
          if restored >= 100
            conn.execute("DELETE FROM shop_penalties WHERE user_id = #{order['user_id'].to_i} AND shop_item_id = #{order['shop_item_id'].to_i}")
          else
            conn.execute("UPDATE shop_penalties SET probability_multiplier = #{restored}, updated_at = NOW() WHERE user_id = #{order['user_id'].to_i} AND shop_item_id = #{order['shop_item_id'].to_i}")
          end
        end
      else
        conn.execute("DELETE FROM shop_penalties WHERE user_id = #{order['user_id'].to_i} AND shop_item_id = #{order['shop_item_id'].to_i}")
      end

      conn.execute("DELETE FROM shop_orders WHERE id = #{order_id}")

      not_inactive = !%w[cancelled deleted].include?(order["status"])
      if not_inactive && %w[purchase luck_win].include?(order["order_type"])
        qty = order["quantity"].to_i
        conn.execute("UPDATE shop_items SET count = count + #{qty}, updated_at = NOW() WHERE id = #{order['shop_item_id'].to_i}")
      end
    end

    render_json({ success: true })
  rescue StandardError => e
    render_json({ error: "Failed to delete order: #{e.message}" }, status: :internal_server_error)
  end

  def restore_order
    original_order_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    archived = conn.select_one("SELECT * FROM admin_deleted_orders WHERE original_order_id = #{original_order_id} AND restored = false LIMIT 1")
    return render_json({ error: "Archived order not found or already restored" }, status: :not_found) unless archived

    payload = archived["deleted_payload"]
    parsed = payload.is_a?(String) ? JSON.parse(payload) : payload
    order_payload = parsed["order"]
    return render_json({ error: "Archived order payload missing" }, status: :unprocessable_entity) unless order_payload

    ActiveRecord::Base.transaction do
      existing = conn.select_one("SELECT 1 FROM shop_orders WHERE id = #{order_payload['id']} LIMIT 1")
      raise "Active order with that id already exists" if existing

      conn.execute(<<~SQL)
        INSERT INTO shop_orders (id, user_id, shop_item_id, quantity, price_per_item, total_price, status, order_type, shipping_address, phone, notes, is_fulfilled, created_at, updated_at)
        OVERRIDING SYSTEM VALUE
        VALUES (#{order_payload['id'].to_i}, #{order_payload['user_id'].to_i || order_payload['userId'].to_i}, #{order_payload['shop_item_id'].to_i || order_payload['shopItemId'].to_i}, #{order_payload['quantity'].to_i}, #{order_payload['price_per_item'].to_i || order_payload['pricePerItem'].to_i}, #{order_payload['total_price'].to_i || order_payload['totalPrice'].to_i}, #{conn.quote(order_payload['status'])}, #{conn.quote(order_payload['order_type'] || order_payload['orderType'])}, #{conn.quote(order_payload['shipping_address'] || order_payload['shippingAddress'])}, #{conn.quote(order_payload['phone'])}, #{conn.quote(order_payload['notes'])}, #{order_payload['is_fulfilled'] || order_payload['isFulfilled'] ? 'true' : 'false'}, #{conn.quote(order_payload['created_at'] || order_payload['createdAt'])}, NOW())
      SQL

      (parsed["refineryOrders"] || []).each do |r|
        uid = r["user_id"] || r["userId"]; iid = r["shop_item_id"] || r["shopItemId"]
        conn.execute("INSERT INTO refinery_orders (user_id, shop_item_id, cost, boost_amount, created_at, updated_at) VALUES (#{uid.to_i}, #{iid.to_i}, #{r['cost'].to_i}, #{r['boost_amount'] || r['boostAmount']}, #{conn.quote(r['created_at'] || r['createdAt'])}, NOW())")
      end
      (parsed["refineryHistory"] || []).each do |h|
        uid = h["user_id"] || h["userId"]; iid = h["shop_item_id"] || h["shopItemId"]
        conn.execute("INSERT INTO refinery_spending_history (user_id, shop_item_id, cost, created_at) VALUES (#{uid.to_i}, #{iid.to_i}, #{h['cost'].to_i}, #{conn.quote(h['created_at'] || h['createdAt'])})")
      end
      (parsed["shopRolls"] || []).each do |r|
        uid = r["user_id"] || r["userId"]; iid = r["shop_item_id"] || r["shopItemId"]
        conn.execute("INSERT INTO shop_rolls (user_id, shop_item_id, rolled, threshold, won, created_at) VALUES (#{uid.to_i}, #{iid.to_i}, #{r['rolled'].to_i}, #{r['threshold'].to_i}, #{r['won'] ? 'true' : 'false'}, #{conn.quote(r['created_at'] || r['createdAt'])})")
      end

      uid = order_payload["user_id"] || order_payload["userId"]
      iid = order_payload["shop_item_id"] || order_payload["shopItemId"]
      order_type = order_payload["order_type"] || order_payload["orderType"]

      if order_type == "luck_win"
        current_penalty = conn.select_one("SELECT probability_multiplier FROM shop_penalties WHERE user_id = #{uid.to_i} AND shop_item_id = #{iid.to_i}")
        if current_penalty
          halved = [1, (current_penalty["probability_multiplier"].to_f / 2).floor].max
          conn.execute("UPDATE shop_penalties SET probability_multiplier = #{halved}, updated_at = NOW() WHERE user_id = #{uid.to_i} AND shop_item_id = #{iid.to_i}")
        else
          conn.execute("INSERT INTO shop_penalties (user_id, shop_item_id, probability_multiplier, created_at, updated_at) VALUES (#{uid.to_i}, #{iid.to_i}, 50, NOW(), NOW())")
        end
      else
        (parsed["shopPenalties"] || []).each do |p|
          puid = p["user_id"] || p["userId"]; piid = p["shop_item_id"] || p["shopItemId"]
          conn.execute("INSERT INTO shop_penalties (user_id, shop_item_id, probability_multiplier, created_at, updated_at) VALUES (#{puid.to_i}, #{piid.to_i}, #{p['probability_multiplier'].to_i}, #{conn.quote(p['created_at'] || p['createdAt'])}, NOW())")
        end
      end

      order_status = order_payload["status"]
      was_inactive = %w[cancelled deleted].include?(order_status)
      if !was_inactive && %w[purchase luck_win].include?(order_type)
        qty = order_payload["quantity"].to_i
        conn.execute("UPDATE shop_items SET count = GREATEST(count - #{qty}, 0), updated_at = NOW() WHERE id = #{iid.to_i}")
      end

      conn.execute("UPDATE admin_deleted_orders SET restored = true, restored_by = #{current_user.id}, restored_at = NOW() WHERE id = #{archived['id'].to_i}")
    end

    render_json({ success: true })
  rescue StandardError => e
    render_json({ error: "Failed to restore archived order: #{e.message}" }, status: :internal_server_error)
  end

  def shop_items
    rows = ActiveRecord::Base.connection.select_all("SELECT * FROM shop_items ORDER BY created_at DESC").to_a
    render_json(rows)
  end

  def create_shop_item
    name = params[:name].to_s.strip; image = params[:image].to_s.strip; description = params[:description].to_s.strip; category = params[:category].to_s.strip
    price = params[:price].to_i; count = params[:count].to_i
    base_prob = params[:baseProbability]&.to_i
    roll_cost_override = params[:rollCostOverride]&.to_i
    per_roll_mult = (params[:perRollMultiplier] || 0.05).to_f
    upgrade_budget_mult = (params[:upgradeBudgetMultiplier] || 3.0).to_f

    return render_json({ error: "All fields are required" }, status: :bad_request) if [name, image, description, category].any?(&:blank?)
    return render_json({ error: "Invalid price" }, status: :bad_request) if price < 0

    pricing = ShopPricingService.compute_item_pricing(price.to_f / ScrapsService::SCRAPS_PER_DOLLAR, base_prob, count)

    conn = ActiveRecord::Base.connection
    conn.execute(<<~SQL)
      INSERT INTO shop_items (name, image, description, price, category, count, base_probability, base_upgrade_cost, cost_multiplier, boost_amount, roll_cost_override, per_roll_multiplier, upgrade_budget_multiplier, created_at, updated_at)
      VALUES (#{conn.quote(name)}, #{conn.quote(image)}, #{conn.quote(description)}, #{price}, #{conn.quote(category)}, #{count}, #{pricing[:base_probability]}, #{pricing[:base_upgrade_cost]}, #{pricing[:cost_multiplier]}, #{pricing[:boost_amount]}, #{conn.quote(roll_cost_override)}, #{per_roll_mult}, #{upgrade_budget_mult}, NOW(), NOW())
    SQL
    render_json({ success: true }, status: :created)
  end

  def update_shop_item
    conn = ActiveRecord::Base.connection
    set_parts = ["updated_at = NOW()"]
    set_parts << "name = #{conn.quote(params[:name].to_s.strip)}" if params.key?(:name)
    set_parts << "image = #{conn.quote(params[:image].to_s.strip)}" if params.key?(:image)
    set_parts << "description = #{conn.quote(params[:description].to_s.strip)}" if params.key?(:description)
    set_parts << "price = #{params[:price].to_i}" if params.key?(:price)
    set_parts << "category = #{conn.quote(params[:category].to_s.strip)}" if params.key?(:category)
    set_parts << "count = #{params[:count].to_i}" if params.key?(:count)
    set_parts << "base_probability = #{params[:baseProbability].to_i}" if params.key?(:baseProbability)
    set_parts << "base_upgrade_cost = #{params[:baseUpgradeCost].to_i}" if params.key?(:baseUpgradeCost)
    set_parts << "cost_multiplier = #{params[:costMultiplier].to_f}" if params.key?(:costMultiplier)
    set_parts << "boost_amount = #{params[:boostAmount].to_f}" if params.key?(:boostAmount)
    set_parts << "roll_cost_override = #{conn.quote(params[:rollCostOverride])}" if params.key?(:rollCostOverride)

    updated = conn.select_one("UPDATE shop_items SET #{set_parts.join(', ')} WHERE id = #{params[:id].to_i} RETURNING id")
    return render_json({ error: "Not found" }, status: :not_found) unless updated
    render_json({ success: true })
  end

  def delete_shop_item
    item_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    conn.execute("DELETE FROM shop_hearts WHERE shop_item_id = #{item_id}")
    conn.execute("DELETE FROM shop_rolls WHERE shop_item_id = #{item_id}")
    conn.execute("DELETE FROM refinery_orders WHERE shop_item_id = #{item_id}")
    conn.execute("DELETE FROM shop_penalties WHERE shop_item_id = #{item_id}")
    conn.execute("DELETE FROM shop_orders WHERE shop_item_id = #{item_id}")
    conn.execute("DELETE FROM shop_items WHERE id = #{item_id}")
    render_json({ success: true })
  end

  def news_index
    rows = ActiveRecord::Base.connection.select_all("SELECT * FROM news ORDER BY created_at DESC").to_a
    render_json(rows)
  end

  def create_news
    title = params[:title].to_s.strip; content = params[:content].to_s.strip
    return render_json({ error: "Title and content are required" }, status: :bad_request) if title.blank? || content.blank?
    active = params.key?(:active) ? params[:active] : true

    conn = ActiveRecord::Base.connection
    inserted = conn.select_one(<<~SQL)
      INSERT INTO news (title, content, active, created_at, updated_at)
      VALUES (#{conn.quote(title)}, #{conn.quote(content)}, #{active ? 'true' : 'false'}, NOW(), NOW())
      RETURNING *
    SQL
    render_json(inserted, status: :created)
  end

  def update_news
    conn = ActiveRecord::Base.connection
    set_parts = ["updated_at = NOW()"]
    set_parts << "title = #{conn.quote(params[:title].to_s.strip)}" if params.key?(:title)
    set_parts << "content = #{conn.quote(params[:content].to_s.strip)}" if params.key?(:content)
    set_parts << "active = #{params[:active] ? 'true' : 'false'}" if params.key?(:active)

    updated = conn.select_one("UPDATE news SET #{set_parts.join(', ')} WHERE id = #{params[:id].to_i} RETURNING *")
    return render_json({ error: "Not found" }, status: :not_found) unless updated
    render_json(updated)
  end

  def delete_news
    ActiveRecord::Base.connection.execute("DELETE FROM news WHERE id = #{params[:id].to_i}")
    render_json({ success: true })
  end

  def compute_pricing
    dollar_cost = params[:dollarCost].to_f
    base_prob = params[:baseProbability]&.to_i
    stock_count = (params[:stockCount] || 1).to_i
    return render_json({ error: "dollarCost must be a positive number" }, status: :bad_request) unless dollar_cost > 0
    render_json(ShopPricingService.compute_item_pricing(dollar_cost, base_prob, stock_count))
  end

  def compute_roll_costs
    item_ids = params[:itemIds]
    items_param = params[:items]
    conn = ActiveRecord::Base.connection

    rows = if item_ids.is_a?(Array) && item_ids.any?
      conn.select_all("SELECT id, price, base_probability, roll_cost_override, per_roll_multiplier FROM shop_items WHERE id IN (#{item_ids.map(&:to_i).join(',')})").to_a
    elsif items_param.is_a?(Array)
      items_param.map { |it| { "id" => it[:id], "price" => it[:price], "base_probability" => (it[:baseProbability] || 50), "roll_cost_override" => it[:rollCostOverride], "per_roll_multiplier" => (it[:perRollMultiplier] || 0.05), "roll_count" => (it[:rollCount] || 0), "user_boost_percent" => (it[:userBoostPercent] || 0) } }
    else
      return render_json({ error: "itemIds or items required" }, status: :bad_request)
    end

    results = rows.map do |r|
      eff_prob = [(r["base_probability"].to_f + r["user_boost_percent"].to_f), 100].min
      per_roll = (r["per_roll_multiplier"] || 0.05).to_f
      base_roll = ScrapsService.calculate_roll_cost(r["price"].to_i, eff_prob, r["roll_cost_override"]&.to_i, r["base_probability"].to_f)
      prev = r["roll_count"].to_i
      { id: r["id"].to_i, base_roll_cost: base_roll, display_roll_cost: (base_roll * (1 + per_roll * prev)).round }
    end
    render_json({ results: results })
  end

  def fix_negative_balances
    all_users = ActiveRecord::Base.connection.select_all("SELECT id FROM users").to_a
    fixed = []
    all_users.each do |u|
      bal = ScrapsService.get_user_scraps_balance(u["id"].to_i)[:balance]
      if bal < 0
        deficit = bal.abs
        ActiveRecord::Base.connection.execute("INSERT INTO user_bonuses (user_id, amount, reason, given_by, created_at) VALUES (#{u['id'].to_i}, #{deficit}, 'negative_balance_fix', #{current_user.id}, NOW())")
        fixed << { user_id: u["id"].to_i, deficit: deficit }
      end
    end
    render_json({ success: true, fixed_count: fixed.length, fixed: fixed })
  end

  def reset_non_buyer_refinery
    conn = ActiveRecord::Base.connection
    refinery_users = conn.select_all("SELECT user_id, shop_item_id FROM refinery_orders GROUP BY user_id, shop_item_id").to_a
    buyers = conn.select_all("SELECT user_id, shop_item_id FROM shop_orders WHERE order_type IN ('purchase','luck_win') GROUP BY user_id, shop_item_id").to_a
    buyer_set = buyers.map { |b| "#{b['user_id']}-#{b['shop_item_id']}" }.to_set

    to_reset = refinery_users.reject { |r| buyer_set.include?("#{r['user_id']}-#{r['shop_item_id']}") }
    deleted_orders = 0; deleted_history = 0
    to_reset.each do |r|
      uid = r["user_id"].to_i; iid = r["shop_item_id"].to_i
      deleted_orders += conn.execute("DELETE FROM refinery_orders WHERE user_id = #{uid} AND shop_item_id = #{iid}").cmd_tuples rescue 0
      deleted_history += conn.execute("DELETE FROM refinery_spending_history WHERE user_id = #{uid} AND shop_item_id = #{iid}").cmd_tuples rescue 0
    end
    render_json({ success: true, reset_count: to_reset.length, deleted_orders: deleted_orders, deleted_history: deleted_history })
  end

  def unship_project
    project_id = params[:id].to_i
    reason = params[:reason].to_s.strip.presence || "Project has been unshipped by an admin."
    conn = ActiveRecord::Base.connection
    project = conn.select_one("SELECT id, user_id, name, status, scraps_awarded FROM projects WHERE id = #{project_id}")
    return render_json({ error: "Project not found" }, status: :not_found) unless project
    return render_json({ error: "Project is not shipped" }, status: :bad_request) unless project["status"] == "shipped"

    previous = project["scraps_awarded"].to_i
    conn.execute("UPDATE projects SET status = 'in_progress', scraps_awarded = 0, scraps_paid_amount = 0, scraps_paid_at = NULL, updated_at = NOW() WHERE id = #{project_id}")
    conn.execute("INSERT INTO reviews (project_id, reviewer_id, action, feedback_for_author, internal_justification, created_at) VALUES (#{project_id}, #{current_user.id}, 'denied', #{conn.quote(reason)}, 'Unshipped: removed #{previous} scraps', NOW())")
    render_json({ success: true, previous_scraps: previous })
  end

  def user_timeline
    target_id = params[:id].to_i
    conn = ActiveRecord::Base.connection

    paid_projects = conn.select_all("SELECT id, name, scraps_awarded, scraps_paid_at, status, created_at FROM projects WHERE user_id = #{target_id} AND scraps_awarded > 0").to_a
    bonuses = conn.select_all("SELECT id, amount, reason, given_by, created_at FROM user_bonuses WHERE user_id = #{target_id}").to_a
    shop_orders = conn.select_all("SELECT so.id, so.shop_item_id, so.total_price, so.order_type, so.status, so.created_at, si.name AS item_name FROM shop_orders so INNER JOIN shop_items si ON si.id = so.shop_item_id WHERE so.user_id = #{target_id}").to_a
    refinery_rows = conn.select_all("SELECT ro.id, ro.shop_item_id, ro.cost, ro.boost_amount, ro.created_at, si.name AS item_name FROM refinery_orders ro INNER JOIN shop_items si ON si.id = ro.shop_item_id WHERE ro.user_id = #{target_id}").to_a
    refinery_history = conn.select_all("SELECT rsh.id, rsh.shop_item_id, rsh.cost, rsh.created_at, si.name AS item_name FROM refinery_spending_history rsh INNER JOIN shop_items si ON si.id = rsh.shop_item_id WHERE rsh.user_id = #{target_id}").to_a

    last_purchase_by_item = {}
    shop_orders.each do |o|
      next unless %w[purchase luck_win].include?(o["order_type"])
      iid = o["shop_item_id"].to_i
      date = Time.parse(o["created_at"].to_s) rescue nil
      next unless date
      last_purchase_by_item[iid] = date if !last_purchase_by_item[iid] || date > last_purchase_by_item[iid]
    end

    timeline = []
    paid_projects.each { |p| timeline << { type: "earned", amount: p["scraps_awarded"].to_i, description: "project \"#{p['name']}\"", date: (p["scraps_paid_at"] || p["created_at"]).to_s, paid: !p["scraps_paid_at"].nil? } }
    bonuses.each { |b| timeline << { type: "bonus", amount: b["amount"].to_i, description: b["reason"], date: b["created_at"].to_s, bonus_id: b["id"].to_i } }
    shop_orders.each { |o| timeline << { type: "shop_#{o['order_type']}", amount: -o["total_price"].to_i, description: o["item_name"], date: o["created_at"].to_s, item_name: o["item_name"], order_id: o["id"].to_i } }

    refinery_rows.each do |r|
      iid = r["shop_item_id"].to_i
      last = last_purchase_by_item[iid]
      r_date = Time.parse(r["created_at"].to_s) rescue nil
      locked = last && r_date && r_date <= last
      timeline << { type: "refinery_upgrade", amount: -r["cost"].to_i, description: "+#{r['boost_amount']}% boost for \"#{r['item_name']}\"", date: r["created_at"].to_s, locked: locked, item_name: r["item_name"] }
    end

    order_count_by_item = Hash.new(0)
    refinery_rows.each { |r| order_count_by_item[r["shop_item_id"].to_i] += 1 }
    history_by_item = {}
    refinery_history.each { |h| (history_by_item[h["shop_item_id"].to_i] ||= []) << h }
    history_by_item.each do |item_id, entries|
      active_count = order_count_by_item[item_id]
      entries.sort_by! { |h| Time.parse(h["created_at"].to_s) rescue Time.now }
      consumed_count = [0, entries.length - active_count].max
      entries.first(consumed_count).each do |h|
        timeline << { type: "refinery_consumed", amount: -h["cost"].to_i, description: "upgrade consumed by win for \"#{h['item_name']}\"", date: h["created_at"].to_s, item_name: h["item_name"] }
      end
    end

    timeline.sort_by! { |e| -Time.parse(e[:date].to_s).to_i rescue 0 }
    balance = ScrapsService.get_user_scraps_balance(target_id)
    render_json({ timeline: timeline, balance: balance })
  end

  def sync_hours
    project_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    proj = conn.select_one("SELECT status, github_url, playable_url FROM projects WHERE id = #{project_id}")
    return render_json({ error: "Project not found" }, status: :not_found) unless proj
    return render_json({ error: "Cannot sync hours for shipped projects" }, status: :bad_request) if proj["status"] == "shipped"

    result = HackatimeSyncJob.perform_now(project_id)
    render_json({ hours: result[:hours], updated: result[:updated] })
  end

  def export_review_csv
    conn = ActiveRecord::Base.connection
    projects = conn.select_all(<<~SQL).to_a
      SELECT p.name, p.github_url, p.playable_url, p.hackatime_project, u.slack_id
      FROM projects p
      INNER JOIN users u ON u.id = p.user_id
      WHERE (p.status = 'waiting_for_review' OR p.status = 'pending_admin_approval')
        AND (p.deleted = 0 OR p.deleted IS NULL)
      ORDER BY p.updated_at DESC
    SQL

    def escape_csv(val)
      return "" if val.nil? || val.empty?
      val.include?(",") || val.include?('"') || val.include?("\n") ? "\"#{val.gsub('"', '""')}\"" : val
    end

    rows = ["name,code_link,demo_link,slack_id,hackatime_projects"]
    projects.each do |p|
      rows << [escape_csv(p["name"]), escape_csv(p["github_url"]), escape_csv(p["playable_url"]), escape_csv(p["slack_id"]), escape_csv(p["hackatime_project"])].join(",")
    end

    send_data rows.join("\n"), type: "text/csv; charset=utf-8", filename: "scraps-review-projects.csv"
  end

  def export_review_json
    conn = ActiveRecord::Base.connection
    projects = conn.select_all(<<~SQL).to_a
      SELECT p.name, p.github_url, p.playable_url, p.hackatime_project, u.slack_id
      FROM projects p INNER JOIN users u ON u.id = p.user_id
      WHERE (p.status = 'waiting_for_review' OR p.status = 'pending_admin_approval') AND (p.deleted = 0 OR p.deleted IS NULL)
      ORDER BY p.updated_at DESC
    SQL

    render_json(projects.map { |p|
      ht_projects = p["hackatime_project"]&.split(",")&.map(&:strip)&.reject(&:empty?) || []
      { name: p["name"], code_link: p["github_url"] || "", demo_link: p["playable_url"] || "", submitter: { slack_id: p["slack_id"] || "" }, hackatime_projects: ht_projects }
    })
  end

  def sync_airtable
    AirtableSyncJob.perform_later
    render_json({ success: true })
  end

  # --- Login allowlist ---

  def login_allowlist
    rows = LoginAllowlistEntry.order(created_at: :desc).map do |e|
      { id: e.id, identifier: e.identifier, identifier_type: e.identifier_type, note: e.note, created_at: e.created_at }
    end
    render_json({ gating: LoginAllowlistEntry.gating?, entries: rows })
  end

  def add_login_allowlist
    raw = params[:identifier].to_s.strip
    return render_json({ error: "Identifier required" }, status: :bad_request) if raw.blank?

    type = params[:identifier_type].to_s.presence || (raw.include?("@") ? "email" : "slack_id")
    return render_json({ error: "Invalid type" }, status: :bad_request) unless LoginAllowlistEntry::TYPES.include?(type)

    identifier = type == "email" ? raw.downcase : raw
    entry = LoginAllowlistEntry.new(identifier: identifier, identifier_type: type, note: params[:note].to_s.strip.presence, added_by_user_id: current_user.id)
    return render_json({ error: entry.errors.full_messages.join(", ") }, status: :unprocessable_entity) unless entry.save

    render_json({ id: entry.id, identifier: entry.identifier, identifier_type: entry.identifier_type, note: entry.note, created_at: entry.created_at }, status: :created)
  end

  def delete_login_allowlist
    entry = LoginAllowlistEntry.find_by(id: params[:id])
    return render_json({ error: "Not found" }, status: :not_found) unless entry
    entry.destroy
    render_json({ success: true })
  end

  def unified_duplicates
    return render_json({ error: "Unified Airtable not configured" }, status: :service_unavailable) unless unified_airtable_configured?
    conn = ActiveRecord::Base.connection
    projects = conn.select_all("SELECT id, github_url, playable_url FROM projects WHERE (status IN ('waiting_for_review','pending_admin_approval','shipped')) AND (deleted = 0 OR deleted IS NULL)").to_a
    code_urls = projects.map { |p| p["github_url"] }.compact.to_set
    playable_urls = projects.map { |p| p["playable_url"] }.compact.to_set
    matches = search_unified_airtable_batch(code_urls, playable_urls) rescue []
    render_json({ total_checked: code_urls.size + playable_urls.size, non_scraps_matches: matches })
  end

  def recalculate_shop_pricing
    count = ShopPricingService.update_all_items
    render_json({ success: true, updated_count: count })
  end

  def delete_user
    target_id = params[:id].to_i
    return render_json({ error: "Cannot delete yourself" }, status: :bad_request) if current_user.id == target_id

    conn = ActiveRecord::Base.connection
    project_ids = conn.select_all("SELECT id FROM projects WHERE user_id = #{target_id}").map { |r| r["id"].to_i }

    conn.execute("DELETE FROM sessions WHERE user_id = #{target_id}")
    conn.execute("DELETE FROM user_activity WHERE user_id = #{target_id}")
    conn.execute("DELETE FROM shop_hearts WHERE user_id = #{target_id}")
    conn.execute("DELETE FROM shop_penalties WHERE user_id = #{target_id}")
    conn.execute("DELETE FROM shop_rolls WHERE user_id = #{target_id}")
    conn.execute("DELETE FROM refinery_spending_history WHERE user_id = #{target_id}")
    conn.execute("DELETE FROM refinery_orders WHERE user_id = #{target_id}")
    conn.execute("DELETE FROM shop_orders WHERE user_id = #{target_id}")
    conn.execute("UPDATE user_bonuses SET given_by = NULL WHERE given_by = #{target_id}")
    conn.execute("DELETE FROM user_bonuses WHERE user_id = #{target_id}")
    conn.execute("DELETE FROM reviews WHERE reviewer_id = #{target_id}")

    if project_ids.any?
      ids_sql = project_ids.join(",")
      conn.execute("DELETE FROM project_activity WHERE project_id IN (#{ids_sql})")
      conn.execute("DELETE FROM reviews WHERE project_id IN (#{ids_sql})")
    end

    conn.execute("DELETE FROM project_activity WHERE user_id = #{target_id}")
    conn.execute("DELETE FROM projects WHERE user_id = #{target_id}")

    deleted = conn.select_one("DELETE FROM users WHERE id = #{target_id} RETURNING id")
    return render_json({ error: "User not found" }, status: :not_found) unless deleted

    render_json({ success: true })
  end

  def pricing_config
    render_json({
      scraps_per_dollar: ScrapsService::SCRAPS_PER_DOLLAR,
      dollars_per_hour: ScrapsService::DOLLARS_PER_HOUR,
      tier_multipliers: ScrapsService::TIER_MULTIPLIERS
    })
  end

  private

  def authenticate_reviewer
    return if %w[reviewer admin creator].include?(current_user&.role)
    render_json({ error: "Unauthorized" }, status: :unauthorized)
  end

  def authenticate_admin
    return if %w[admin creator].include?(current_user&.role)
    render_json({ error: "Unauthorized" }, status: :unauthorized)
  end

  def authenticate_creator
    return if current_user&.role == "creator"
    render_json({ error: "Unauthorized" }, status: :unauthorized)
  end

  def unified_airtable_configured?
    ENV["UNIFIED_AIRTABLE_TOKEN"].present? && ENV["UNIFIED_AIRTABLE_BASE_ID"].present? && ENV["UNIFIED_AIRTABLE_TABLE_ID"].present?
  end

  def search_unified_airtable(code_url, playable_url)
    return [] unless unified_airtable_configured?
    base_url = "https://api.airtable.com/v0/#{ENV['UNIFIED_AIRTABLE_BASE_ID']}/#{ENV['UNIFIED_AIRTABLE_TABLE_ID']}"
    seen = {}; matches = []

    [[code_url, "code_url"], [playable_url, "playable_url"]].each do |url, match_type|
      next unless url.present?
      field = match_type == "code_url" ? "Code URL" : "Playable URL"
      formula = "AND(YSWS!='scraps',{#{field}}='#{url.gsub("'", "\\'")}')"
      fetch_airtable_records(base_url, formula).each do |r|
        if seen[r["id"]]
          seen[r["id"]][:match_type] = "code_url, playable_url"
        else
          seen[r["id"]] = r.merge("match_type" => match_type)
          matches << seen[r["id"]]
        end
      end
    end
    matches
  end

  def search_unified_airtable_batch(code_urls, playable_urls)
    return [] unless unified_airtable_configured?
    base_url = "https://api.airtable.com/v0/#{ENV['UNIFIED_AIRTABLE_BASE_ID']}/#{ENV['UNIFIED_AIRTABLE_TABLE_ID']}"
    seen = {}; matches = []

    [[code_urls.to_a, "Code URL", "code_url"], [playable_urls.to_a, "Playable URL", "playable_url"]].each do |urls, field, match_type|
      urls.each_slice(15) do |batch|
        or_parts = batch.map { |u| "{#{field}}='#{u.gsub("'", "\\'")}'" }.join(",")
        formula = "AND(YSWS!='scraps',OR(#{or_parts}))"
        fetch_airtable_records(base_url, formula).each do |r|
          if seen[r["id"]]
            seen[r["id"]][:match_type] = "code_url, playable_url"
          else
            seen[r["id"]] = r.merge("match_type" => match_type)
            matches << seen[r["id"]]
          end
        end
      end
    end
    matches
  end

  def fetch_airtable_records(base_url, formula)
    results = []
    offset = nil
    loop do
      query = URI.encode_www_form([["filterByFormula", formula], ["pageSize", "100"], ["fields[]", "YSWS"], ["fields[]", "Playable URL"], ["fields[]", "Code URL"]] + (offset ? [["offset", offset]] : []))
      resp = HTTParty.get("#{base_url}?#{query}", headers: { "Authorization" => "Bearer #{ENV['UNIFIED_AIRTABLE_TOKEN']}" })
      break unless resp.success?
      data = resp.parsed_response
      (data["records"] || []).each do |rec|
        results << { "id" => rec["id"], "ysws" => rec.dig("fields", "YSWS") || "", "playable_url" => rec.dig("fields", "Playable URL") || "", "code_url" => rec.dig("fields", "Code URL") || "" }
      end
      offset = data["offset"]
      break unless offset
    end
    results
  rescue StandardError
    []
  end
end
