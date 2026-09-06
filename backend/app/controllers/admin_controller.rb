class AdminController < ApplicationController
  class GachaponError < StandardError; end

  before_action :authenticate_reviewer, only: %i[stats users show_user update_notes update_project_notes reviews show_review submit_review export_review_csv export_review_json sync_hours]
  before_action :authenticate_admin, only: %i[update_role create_bonus user_bonuses delete_bonus orders orders_needs_info_count show_order update_order update_order_notes delete_order restore_order shop_items create_shop_item update_shop_item delete_shop_item gachapons create_gachapon update_gachapon delete_gachapon news_index create_news update_news delete_news compute_pricing compute_roll_costs fix_negative_balances unship_project user_timeline sync_airtable unified_duplicates recalculate_shop_pricing login_allowlist login_allowlist_users add_login_allowlist delete_login_allowlist]
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
      { tier: tier, multiplier: mult, hours: (data[:hours] * 10).round / 10.0, projects: data[:projects] }
    end.sort_by { |t| t[:tier] }

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
      tier_cost_breakdown: tier_cost_breakdown
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
    target = conn.select_one("SELECT id, username, avatar, slack_id, email, role, internal_notes, created_at, legal_first_name, legal_last_name, phone, address_line1, address_line2, address_city, address_state, address_postal_code, address_country FROM users WHERE id = #{target_id}")
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
      user: {
        id: target["id"].to_i, username: target["username"], avatar: target["avatar"], slack_id: target["slack_id"],
        email: is_admin_user ? target["email"] : nil, scraps: balance[:balance], role: target["role"],
        internal_notes: target["internal_notes"], created_at: target["created_at"],
        legal_first_name: is_admin_user ? target["legal_first_name"] : nil,
        legal_last_name: is_admin_user ? target["legal_last_name"] : nil,
        phone: is_admin_user ? target["phone"] : nil,
        address_line1: is_admin_user ? target["address_line1"] : nil,
        address_line2: is_admin_user ? target["address_line2"] : nil,
        address_city: is_admin_user ? target["address_city"] : nil,
        address_state: is_admin_user ? target["address_state"] : nil,
        address_postal_code: is_admin_user ? target["address_postal_code"] : nil,
        address_country: is_admin_user ? target["address_country"] : nil
      },
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
    # NB: not params[:action] — Rails' routing reserves :action for the controller method name.
    action = params[:decision].presence.to_s
    feedback = params[:feedbackForAuthor].to_s.strip
    rejection_reason = params[:rejectionReason].to_s.strip
    # The reviewer-confirmed hours to grant on (the "hours to approve" field).
    approved_hours = params[:hoursOverride]&.to_f
    reviewer_score = params[:reviewerScore]&.to_f
    user_notes = params[:userInternalNotes]
    project_notes = params[:projectInternalNotes]
    reship_flag = params.key?(:isReship) ? ActiveModel::Type::Boolean.new.cast(params[:isReship]) : nil

    return render_json({ error: "Invalid action" }) unless %w[approved denied permanently_rejected].include?(action)
    return render_json({ error: "Feedback for author is required" }) if feedback.blank? && action != "permanently_rejected"
    return render_json({ error: "Reason shown to user is required for permanent rejection" }) if action == "permanently_rejected" && rejection_reason.blank?
    return render_json({ error: "Reviewer score is required (1-3)" }) if action == "approved" && (reviewer_score.nil? || reviewer_score < 1 || reviewer_score > 3)

    project_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    project = conn.select_one("SELECT * FROM projects WHERE id = #{project_id}")
    return render_json({ error: "Project not found" }, status: :not_found) unless project
    return render_json({ error: "Approved hours cannot exceed logged hours" }) if approved_hours && approved_hours > project["hours"].to_f
    return render_json({ error: "Cannot review a deleted project" }) if project["deleted"].to_i == 1
    return render_json({ error: "Project is not marked for review" }) unless project["status"] == "waiting_for_review"

    if action == "approved" && project["github_url"].present?
      dupe = conn.select_one("SELECT id FROM projects WHERE github_url = #{conn.quote(project['github_url'])} AND status = 'shipped' AND (deleted = 0 OR deleted IS NULL) AND user_id != #{project['user_id'].to_i} LIMIT 1")
      return render_json({ error: "A shipped project with this Code URL already exists (from another user).", duplicate_code_url: true }) if dupe
    end

    conn.execute(<<~SQL)
      INSERT INTO reviews (project_id, reviewer_id, action, feedback_for_author, internal_justification, reviewer_score, created_at)
      VALUES (#{project_id}, #{current_user.id}, #{conn.quote(action)}, #{conn.quote(feedback)}, #{conn.quote(params[:internalJustification].to_s.presence)}, #{action == "approved" ? reviewer_score : "NULL"}, NOW())
    SQL

    can_ship = true
    new_status = case action
    when "approved" then "shipped"
    when "denied" then "in_progress"
    when "permanently_rejected" then "permanently_rejected"
    end

    set_parts = ["status = '#{new_status}'", "updated_at = NOW()"]
    set_parts << "is_reship = #{reship_flag ? 'true' : 'false'}" unless reship_flag.nil?

    # On approval the reviewer's "hours to approve" value is final — store it as
    # hours_override and grant on it directly (deductions were already shown in
    # the review UI to inform the number, not re-applied here).
    grant_hours =
      if approved_hours
        approved_hours
      else
        EffectiveHoursService.compute_for_project(project)[:effective_hours]
      end
    set_parts << "hours_override = #{grant_hours}" if action == "approved" && approved_hours

    scraps_awarded = 0
    if action == "approved" && can_ship
      new_scraps = ScrapsService.calculate_scraps_from_score(grant_hours, reviewer_score)
      previously_shipped = conn.select_one("SELECT 1 FROM project_activity WHERE project_id = #{project_id} AND action = 'project_shipped' LIMIT 1")
      scraps_awarded = (previously_shipped && project["scraps_awarded"].to_i > 0) ? [0, new_scraps - project["scraps_awarded"].to_i].max : new_scraps
      set_parts << "scraps_awarded = #{new_scraps}"
      set_parts << "scraps_paid_at = NOW()"
      set_parts << "scraps_paid_amount = #{new_scraps}"
    end

    conn.execute("UPDATE projects SET #{set_parts.join(', ')} WHERE id = #{project_id}")

    if action == "approved" && can_ship
      previously_shipped = conn.select_one("SELECT 1 FROM project_activity WHERE project_id = #{project_id} AND action = 'project_shipped' LIMIT 1")
      if scraps_awarded > 0
        conn.execute("INSERT INTO project_activity (user_id, project_id, action, created_at) VALUES (#{project['user_id'].to_i}, #{project_id}, #{conn.quote(previously_shipped ? "earned #{scraps_awarded} additional scraps (update)" : "earned #{scraps_awarded} scraps")}, NOW())")
      end
      conn.execute("INSERT INTO project_activity (user_id, project_id, action, created_at) VALUES (#{project['user_id'].to_i}, #{project_id}, '#{previously_shipped ? 'project_updated' : 'project_shipped'}', NOW())")
      AirtableSyncJob.perform_later(project_id) rescue nil
    end

    if user_notes.present? && user_notes.length <= 2500
      conn.execute("UPDATE users SET internal_notes = #{conn.quote(user_notes)}, updated_at = NOW() WHERE id = #{project['user_id'].to_i}")
    end

    unless project_notes.nil?
      pn = project_notes.to_s
      conn.execute("UPDATE projects SET internal_notes = #{conn.quote(pn)}, updated_at = NOW() WHERE id = #{project_id}") if pn.length <= 2500
    end

    if ENV["SLACK_BOT_TOKEN"].present?
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
          feedback_for_author: action == "denied" ? feedback : nil,
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

  def orders_needs_info_count
    conn = ActiveRecord::Base.connection
    rows = conn.select_all(<<~SQL).to_a
      SELECT shipping_address FROM shop_orders
      WHERE order_type IN ('purchase', 'luck_win') AND is_fulfilled = false
    SQL

    count = rows.count do |r|
      addr = r["shipping_address"] ? (JSON.parse(r["shipping_address"]) rescue nil) : nil
      addr.nil? || addr["firstName"].blank? || addr["lastName"].blank? ||
        addr["address1"].blank? || addr["phone"].blank?
    end

    render_json({ count: count })
  end

  def orders
    conn = ActiveRecord::Base.connection
    status_filter = params[:status].to_s.presence
    where = status_filter ? "WHERE so.status = #{conn.quote(status_filter)}" : ""

    rows = conn.select_all(<<~SQL).to_a
      SELECT so.id, so.quantity, so.price_per_item, so.total_price, so.status, so.order_type,
             so.notes, so.internal_notes, so.user_note, so.tracking_number, so.is_fulfilled, so.shipping_address, so.phone, so.created_at,
             si.id AS item_id, si.name AS item_name, si.image AS item_image,
             u.id AS user_id, u.username, u.avatar AS user_avatar, u.slack_id, u.email AS user_email
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
      { id: r["id"].to_i, quantity: r["quantity"].to_i, price_per_item: r["price_per_item"].to_i, total_price: r["total_price"].to_i, status: r["status"], order_type: r["order_type"], notes: r["notes"], internal_notes: r["internal_notes"], user_note: r["user_note"], tracking_number: r["tracking_number"], is_fulfilled: r["is_fulfilled"], shipping_address: r["shipping_address"], phone: r["phone"], created_at: r["created_at"], item_id: r["item_id"].to_i, item_name: r["item_name"], item_image: r["item_image"], user_id: r["user_id"].to_i, username: r["username"], user_avatar: r["user_avatar"], slack_id: r["slack_id"], email: r["user_email"], hackatime_banned: ban_map[r["user_email"]] || false }
    })
  end

  def show_order
    conn = ActiveRecord::Base.connection
    r = conn.select_one(<<~SQL)
      SELECT so.id, so.quantity, so.price_per_item, so.total_price, so.status, so.order_type,
             so.notes, so.internal_notes, so.user_note, so.tracking_number, so.is_fulfilled, so.shipping_address, so.phone, so.created_at,
             si.id AS item_id, si.name AS item_name, si.image AS item_image,
             u.id AS user_id, u.username, u.avatar AS user_avatar, u.slack_id, u.email AS user_email
      FROM shop_orders so
      INNER JOIN shop_items si ON si.id = so.shop_item_id
      INNER JOIN users u ON u.id = so.user_id
      WHERE so.id = #{params[:id].to_i}
    SQL
    return render_json({ error: "Not found" }, status: :not_found) unless r

    hackatime_banned = false
    begin
      ht = HackatimeService.get_user(r["user_email"], r["slack_id"])
      hackatime_banned = ht&.dig(:banned) || false
    rescue StandardError
      hackatime_banned = false
    end

    render_json({
      id: r["id"].to_i, quantity: r["quantity"].to_i, price_per_item: r["price_per_item"].to_i, total_price: r["total_price"].to_i,
      status: r["status"], order_type: r["order_type"], notes: r["notes"], internal_notes: r["internal_notes"], user_note: r["user_note"],
      tracking_number: r["tracking_number"], is_fulfilled: r["is_fulfilled"], shipping_address: r["shipping_address"], phone: r["phone"],
      created_at: r["created_at"], item_id: r["item_id"].to_i, item_name: r["item_name"], item_image: r["item_image"],
      user_id: r["user_id"].to_i, username: r["username"], user_avatar: r["user_avatar"], slack_id: r["slack_id"], email: r["user_email"], hackatime_banned: hackatime_banned
    })
  end

  def update_order_notes
    notes = params[:internalNotes].to_s
    return render_json({ error: "Note is too long or it's malformed!" }, status: :bad_request) if notes.length > 2500

    conn = ActiveRecord::Base.connection
    updated = conn.select_one("UPDATE shop_orders SET internal_notes = #{conn.quote(notes)}, updated_at = NOW() WHERE id = #{params[:id].to_i} RETURNING id")
    return render_json({ error: "Not Found" }, status: :not_found) unless updated
    render_json({ success: true })
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
    set_parts << "user_note = #{conn.quote(params[:userNote].to_s)}" if params.key?(:userNote)
    set_parts << "tracking_number = #{conn.quote(params[:trackingNumber].to_s)}" if params.key?(:trackingNumber)
    set_parts << "is_fulfilled = #{params[:isFulfilled] ? 'true' : 'false'}" if params.key?(:isFulfilled)

    updated = conn.select_one("UPDATE shop_orders SET #{set_parts.join(', ')} WHERE id = #{order_id} RETURNING *")
    return render_json({ error: "Not found" }, status: :not_found) unless updated

    if params[:isFulfilled] && ENV["SLACK_BOT_TOKEN"].present?
      order_user = conn.select_one("SELECT u.slack_id, si.name AS item_name FROM shop_orders so INNER JOIN users u ON u.id = so.user_id INNER JOIN shop_items si ON si.id = so.shop_item_id WHERE so.id = #{order_id}")
      if order_user&.dig("slack_id")
        SlackService.notify_order_fulfilled(user_slack_id: order_user["slack_id"], item_name: order_user["item_name"], tracking_number: updated["tracking_number"], user_note: updated["user_note"], token: ENV["SLACK_BOT_TOKEN"]) rescue nil
      end
    end

    render_json({ id: updated["id"].to_i, status: updated["status"], order_type: updated["order_type"], notes: updated["notes"], user_note: updated["user_note"], tracking_number: updated["tracking_number"], is_fulfilled: updated["is_fulfilled"], shipping_address: updated["shipping_address"], created_at: updated["created_at"] })
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
    rows.each do |r|
      r["size_variants"] = r["size_variants"].is_a?(String) ? (JSON.parse(r["size_variants"]) rescue []) : (r["size_variants"] || [])
    end
    render_json(rows)
  end

  def create_shop_item
    name = params[:name].to_s.strip; image = params[:image].to_s.strip; description = params[:description].to_s.strip; category = params[:category].to_s.strip
    price = params[:price].to_i; count = params[:count].to_i
    base_prob = params[:baseProbability]&.to_i
    roll_cost_override = params[:rollCostOverride]&.to_i
    per_roll_mult = (params[:perRollMultiplier] || 0.05).to_f

    return render_json({ error: "All fields are required" }, status: :bad_request) if [name, image, description, category].any?(&:blank?)
    return render_json({ error: "Invalid price" }, status: :bad_request) if price < 0

    fulfillment_cost = params[:fulfillmentCost].to_s.strip.presence
    size_variants = (params[:sizeVariants] || []).map { |v| { name: v[:name].to_s.strip, count: v[:count].to_i } }.select { |v| v[:name].present? }
    gachapon_only = ActiveModel::Type::Boolean.new.cast(params[:gachaponOnly]) ? true : false

    pricing = ShopPricingService.compute_item_pricing(price.to_f / ScrapsService::SCRAPS_PER_DOLLAR, base_prob)

    conn = ActiveRecord::Base.connection
    conn.execute(<<~SQL)
      INSERT INTO shop_items (name, image, description, price, category, count, base_probability, base_upgrade_cost, boost_amount, roll_cost_override, per_roll_multiplier, fulfillment_cost, size_variants, gachapon_only, created_at, updated_at)
      VALUES (#{conn.quote(name)}, #{conn.quote(image)}, #{conn.quote(description)}, #{price}, #{conn.quote(category)}, #{count}, #{pricing[:base_probability]}, #{pricing[:base_upgrade_cost]}, #{pricing[:boost_amount]}, #{conn.quote(roll_cost_override)}, #{per_roll_mult}, #{conn.quote(fulfillment_cost)}, #{conn.quote(size_variants.to_json)}, #{gachapon_only}, NOW(), NOW())
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
    set_parts << "boost_amount = #{params[:boostAmount].to_f}" if params.key?(:boostAmount)
    set_parts << "roll_cost_override = #{conn.quote(params[:rollCostOverride])}" if params.key?(:rollCostOverride)
    set_parts << "fulfillment_cost = #{conn.quote(params[:fulfillmentCost].to_s.strip.presence)}" if params.key?(:fulfillmentCost)
    if params.key?(:sizeVariants)
      size_variants = (params[:sizeVariants] || []).map { |v| { name: v[:name].to_s.strip, count: v[:count].to_i } }.select { |v| v[:name].present? }
      set_parts << "size_variants = #{conn.quote(size_variants.to_json)}"
    end
    set_parts << "gachapon_only = #{ActiveModel::Type::Boolean.new.cast(params[:gachaponOnly]) ? true : false}" if params.key?(:gachaponOnly)

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
    conn.execute("DELETE FROM shop_retained_items WHERE shop_item_id = #{item_id}")
    conn.execute("DELETE FROM shop_gachapon_items WHERE shop_item_id = #{item_id}")
    conn.execute("DELETE FROM shop_items WHERE id = #{item_id}")
    render_json({ success: true })
  end

  def gachapons
    conn = ActiveRecord::Base.connection
    gachapons = conn.select_all("SELECT * FROM shop_gachapons ORDER BY created_at DESC").to_a
    ids = gachapons.map { |g| g["id"].to_i }
    links = ids.any? ? conn.select_all("SELECT gachapon_id, shop_item_id FROM shop_gachapon_items WHERE gachapon_id IN (#{ids.join(',')})").to_a : []
    item_ids_by_gachapon = Hash.new { |h, k| h[k] = [] }
    links.each { |l| item_ids_by_gachapon[l["gachapon_id"].to_i] << l["shop_item_id"].to_i }

    render_json(gachapons.map { |g|
      {
        id: g["id"].to_i,
        name: g["name"],
        description: g["description"],
        image: g["image"],
        price: g["price"].to_i,
        item_ids: item_ids_by_gachapon[g["id"].to_i]
      }
    })
  end

  # Resolves a gachapon's item list to shop_item ids. Each entry is either
  # { id: <existing shop item> } or { new: { name, price, image, count } },
  # where a `new` entry is created as a gachapon-only shop item first.
  # Falls back to a bare `itemIds: [id]` array. Returns de-duped ids.
  def resolve_gachapon_item_ids(conn)
    raw = params[:items]
    unless raw.is_a?(Array) && raw.any?
      return (params[:itemIds] || []).map(&:to_i).select(&:positive?).uniq
    end

    raw.filter_map { |entry|
      existing_id = (entry[:id] || entry[:shop_item_id]).to_i
      next existing_id if existing_id.positive?

      spec = entry[:new] || entry["new"]
      next unless spec

      name = spec[:name].to_s.strip
      price = spec[:price].to_i
      raise GachaponError, "New gachapon items need a name and a cost above 0" if name.blank? || price <= 0
      image = spec[:image].to_s.strip
      count = spec.key?(:count) ? spec[:count].to_i : 0

      pricing = ShopPricingService.compute_item_pricing(price.to_f / ScrapsService::SCRAPS_PER_DOLLAR, nil)
      created = conn.select_one(<<~SQL)
        INSERT INTO shop_items (name, image, description, price, category, count, base_probability, base_upgrade_cost, boost_amount, roll_cost_override, per_roll_multiplier, size_variants, gachapon_only, created_at, updated_at)
        VALUES (#{conn.quote(name)}, #{conn.quote(image)}, '', #{price}, 'gachapon', #{count}, #{pricing[:base_probability]}, #{pricing[:base_upgrade_cost]}, #{pricing[:boost_amount]}, NULL, 0.05, '[]', true, NOW(), NOW())
        RETURNING id
      SQL
      created["id"].to_i
    }.uniq
  end

  def create_gachapon
    name = params[:name].to_s.strip
    description = params[:description].to_s.strip
    image = params[:image].to_s.strip
    price = params[:price].to_i

    return render_json({ error: "Name is required" }, status: :bad_request) if name.blank?
    return render_json({ error: "Invalid price" }, status: :bad_request) if price <= 0

    conn = ActiveRecord::Base.connection
    ActiveRecord::Base.transaction do
      item_ids = resolve_gachapon_item_ids(conn)
      raise GachaponError, "Add at least one item" if item_ids.empty?

      gachapon = conn.select_one(<<~SQL)
        INSERT INTO shop_gachapons (name, description, image, price, created_at, updated_at)
        VALUES (#{conn.quote(name)}, #{conn.quote(description.presence)}, #{conn.quote(image.presence)}, #{price}, NOW(), NOW())
        RETURNING id
      SQL

      item_ids.each do |item_id|
        conn.execute("INSERT INTO shop_gachapon_items (gachapon_id, shop_item_id, created_at) VALUES (#{gachapon['id'].to_i}, #{item_id}, NOW())")
      end
    end

    render_json({ success: true }, status: :created)
  rescue GachaponError => e
    render_json({ error: e.message }, status: :bad_request)
  end

  def update_gachapon
    gachapon_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    return render_json({ error: "Not found" }, status: :not_found) unless conn.select_one("SELECT 1 FROM shop_gachapons WHERE id = #{gachapon_id}")

    set_parts = ["updated_at = NOW()"]
    set_parts << "name = #{conn.quote(params[:name].to_s.strip)}" if params.key?(:name)
    set_parts << "description = #{conn.quote(params[:description].to_s.strip.presence)}" if params.key?(:description)
    set_parts << "image = #{conn.quote(params[:image].to_s.strip.presence)}" if params.key?(:image)
    set_parts << "price = #{params[:price].to_i}" if params.key?(:price)
    conn.execute("UPDATE shop_gachapons SET #{set_parts.join(', ')} WHERE id = #{gachapon_id}")

    if params.key?(:items) || params.key?(:itemIds)
      ActiveRecord::Base.transaction do
        item_ids = resolve_gachapon_item_ids(conn)
        raise GachaponError, "Add at least one item" if item_ids.empty?

        conn.execute("DELETE FROM shop_gachapon_items WHERE gachapon_id = #{gachapon_id}")
        item_ids.each do |item_id|
          conn.execute("INSERT INTO shop_gachapon_items (gachapon_id, shop_item_id, created_at) VALUES (#{gachapon_id}, #{item_id}, NOW())")
        end
      end
    end

    render_json({ success: true })
  rescue GachaponError => e
    render_json({ error: e.message }, status: :bad_request)
  end

  def delete_gachapon
    gachapon_id = params[:id].to_i
    conn = ActiveRecord::Base.connection
    conn.execute("DELETE FROM shop_gachapon_items WHERE gachapon_id = #{gachapon_id}")
    conn.execute("DELETE FROM shop_gachapons WHERE id = #{gachapon_id}")
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
    bust_news_cache
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
    bust_news_cache
    render_json(updated)
  end

  def delete_news
    ActiveRecord::Base.connection.execute("DELETE FROM news WHERE id = #{params[:id].to_i}")
    bust_news_cache
    render_json({ success: true })
  end

  def bust_news_cache
    Rails.cache.delete("news:index:v1")
    Rails.cache.delete("news:latest:v1")
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

  # Signed-up users, for the "pick a user" flow in the allowlist UI.
  def login_allowlist_users
    conn = ActiveRecord::Base.connection
    q = params[:q].to_s.strip
    where = "1=1"
    if q.present?
      like = conn.quote("%#{q}%")
      where = "(username ILIKE #{like} OR email ILIKE #{like} OR slack_id ILIKE #{like})"
    end
    rows = conn.select_all("SELECT id, username, avatar, slack_id, email FROM users WHERE #{where} ORDER BY created_at DESC LIMIT 20").to_a

    listed = LoginAllowlistEntry.pluck(:identifier_type, :identifier)
    emails = listed.select { |t, _| t == "email" }.map { |_, i| i.downcase }.to_set
    slacks = listed.select { |t, _| t == "slack_id" }.map { |_, i| i }.to_set

    render_json(rows.map { |u|
      on_list = emails.include?(u["email"].to_s.downcase) || slacks.include?(u["slack_id"])
      { id: u["id"].to_i, username: u["username"], avatar: u["avatar"], slack_id: u["slack_id"], email: u["email"], on_list: on_list }
    })
  end

  def add_login_allowlist
    raw = params[:identifier].to_s.strip
    return render_json({ error: "Identifier required" }, status: :bad_request) if raw.blank?

    type = params[:identifier_type].to_s.presence || (raw.include?("@") ? "email" : "slack_id")
    return render_json({ error: "Invalid type" }, status: :bad_request) unless LoginAllowlistEntry::TYPES.include?(type)

    identifier = type == "email" ? raw.downcase : raw
    note = params[:note].to_s.strip.presence

    # Build the set of (type, identifier) pairs to add. If this identifier belongs to
    # a known user, pull their other identifier from the users table and add it too,
    # so an email and Slack ID for the same person are always listed together.
    pairs = [[type, identifier]]
    conn = ActiveRecord::Base.connection
    matched = if type == "email"
      conn.select_one("SELECT email, slack_id FROM users WHERE LOWER(email) = #{conn.quote(identifier)} LIMIT 1")
    else
      conn.select_one("SELECT email, slack_id FROM users WHERE slack_id = #{conn.quote(identifier)} LIMIT 1")
    end
    if matched
      pairs << ["email", matched["email"].to_s.downcase] if matched["email"].present?
      pairs << ["slack_id", matched["slack_id"]] if matched["slack_id"].present?
    end

    created = pairs.uniq.filter_map do |t, id|
      next if id.blank?
      e = LoginAllowlistEntry.find_or_initialize_by(identifier_type: t, identifier: id)
      next unless e.new_record?
      e.assign_attributes(note: note, added_by_user_id: current_user.id)
      e if e.save
    end

    if created.empty? && LoginAllowlistEntry.where(identifier_type: pairs.first[0], identifier: pairs.first[1]).none?
      return render_json({ error: "Could not add entry" }, status: :unprocessable_entity)
    end

    render_json({
      linked_user: matched.present?,
      entries: created.map { |e| { id: e.id, identifier: e.identifier, identifier_type: e.identifier_type, note: e.note, created_at: e.created_at } }
    }, status: :created)
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
      tier_multipliers: ScrapsService::TIER_MULTIPLIERS,
      reviewer_score_floor_mult: ScrapsService::SCORE_FLOOR_MULT,
      reviewer_score_neutral_mult: ScrapsService::SCORE_NEUTRAL_MULT,
      reviewer_score_ceil_mult: ScrapsService::SCORE_CEIL_MULT,
      version: AppVersion::SHORT,
      version_sha: AppVersion::SHA,
      version_url: AppVersion.commit_url
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
