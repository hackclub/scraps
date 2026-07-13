class UserController < ApplicationController
  def me
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    balance = ScrapsService.get_user_scraps_balance(current_user.id)

    render_json({
      id: current_user.id,
      username: current_user.username,
      email: current_user.email,
      avatar: current_user.avatar,
      slack_id: current_user.slack_id,
      scraps: balance[:balance],
      scraps_earned: balance[:earned],
      scraps_spent: balance[:spent],
      scraps_pending: balance[:pending],
      tutorial_completed: current_user.tutorial_completed,
      language: current_user.language
    })
  end

  def update_language
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    language = params[:language].to_s.strip
    return render_json({ error: "Language is required" }, status: :unprocessable_entity) if language.blank?

    conn = ActiveRecord::Base.connection
    conn.execute("UPDATE users SET language = #{conn.quote(language)}, updated_at = NOW() WHERE id = #{current_user.id}")
    conn.execute(
      "INSERT INTO user_activity (user_id, email, action, metadata, created_at) VALUES (#{current_user.id}, #{conn.quote(current_user.email)}, 'language_changed', #{conn.quote(language)}, NOW())"
    )

    render_json({ success: true })
  end

  def complete_tutorial
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    if current_user.tutorial_completed
      return render_json({ success: true, already_completed: true })
    end

    result = ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SELECT 1 FROM users WHERE id = #{current_user.id} FOR UPDATE")

      fresh = ActiveRecord::Base.connection.select_one(
        "SELECT tutorial_completed FROM users WHERE id = #{current_user.id}"
      )
      if fresh && (fresh["tutorial_completed"] == true || fresh["tutorial_completed"] == "t" || fresh["tutorial_completed"] == 1)
        next { already_completed: true }
      end

      existing_bonus = UserBonus.find_by(user_id: current_user.id, reason: "tutorial_completion")
      if existing_bonus
        ActiveRecord::Base.connection.execute(
          "UPDATE users SET tutorial_completed = true, updated_at = NOW() WHERE id = #{current_user.id}"
        )
        next { already_completed: true }
      end

      ActiveRecord::Base.connection.execute(
        "UPDATE users SET tutorial_completed = true, updated_at = NOW() WHERE id = #{current_user.id}"
      )
      UserBonus.create!(user_id: current_user.id, reason: "tutorial_completion", amount: 5)

      { bonus_awarded: 5 }
    end

    if result[:already_completed]
      return render_json({ success: true, already_completed: true })
    end

    conn = ActiveRecord::Base.connection
    conn.execute(
      "INSERT INTO user_activity (user_id, email, action, created_at) VALUES (#{current_user.id}, #{conn.quote(current_user.email)}, 'tutorial_completed', NOW())"
    )

    render_json({ success: true, bonus_awarded: result[:bonus_awarded] })
  end

  def profile
    return render_json({ error: "Unauthorized" }, status: :unauthorized) unless current_user

    conn = ActiveRecord::Base.connection
    target = conn.select_one("SELECT id, username, avatar, role, created_at FROM users WHERE id = #{params[:id].to_i}")
    return render_json({ error: "User not found" }, status: :not_found) unless target

    all_projects = conn.select_all(
      "SELECT id, name, description, image, github_url, hours, hours_override, status, deleted, created_at FROM projects WHERE user_id = #{params[:id].to_i}"
    ).to_a

    visible = all_projects.select { |p| p["deleted"].to_i == 0 && %w[shipped in_progress waiting_for_review].include?(p["status"]) }
    shipped_count = all_projects.count { |p| p["deleted"].to_i == 0 && p["status"] == "shipped" }
    in_progress_count = all_projects.count { |p| p["deleted"].to_i == 0 && %w[in_progress waiting_for_review].include?(p["status"]) }

    shipped_hours = all_projects.select { |p| p["deleted"].to_i == 0 && p["status"] == "shipped" }
                                .sum { |p| (p["hours_override"] || p["hours"]).to_f }
    in_progress_hours = all_projects.select { |p| p["deleted"].to_i == 0 && %w[in_progress waiting_for_review].include?(p["status"]) }
                                    .sum { |p| (p["hours_override"] || p["hours"]).to_f }
    total_hours = ((shipped_hours + in_progress_hours) * 10).round / 10.0

    hearts = conn.select_all("SELECT shop_item_id FROM shop_hearts WHERE user_id = #{params[:id].to_i}").to_a
    hearted_item_ids = hearts.map { |h| h["shop_item_id"].to_i }
    hearted_items = []
    if hearted_item_ids.any?
      hearted_items = conn.select_all(
        "SELECT id, name, image, price FROM shop_items WHERE id IN (#{hearted_item_ids.join(',')})"
      ).to_a.map { |i| { id: i["id"].to_i, name: i["name"], image: i["image"], price: i["price"].to_i } }
    end

    balance = ScrapsService.get_user_scraps_balance(params[:id].to_i)

    refinements_rows = conn.select_all(<<~SQL).to_a
      SELECT ro.shop_item_id, si.name AS item_name, si.image AS item_image,
             si.base_probability, COALESCE(SUM(ro.boost_amount), 0) AS total_boost
      FROM refinery_orders ro
      INNER JOIN shop_items si ON si.id = ro.shop_item_id
      WHERE ro.user_id = #{params[:id].to_i}
      GROUP BY ro.shop_item_id, si.name, si.image, si.base_probability
      HAVING COALESCE(SUM(ro.boost_amount), 0) > 0
    SQL

    render_json({
      user: {
        id: target["id"].to_i,
        username: target["username"],
        avatar: target["avatar"],
        role: target["role"],
        scraps: balance[:balance],
        scraps_pending: balance[:pending],
        created_at: target["created_at"]
      },
      is_admin: %w[admin creator].include?(current_user.role),
      projects: visible.map { |p|
        {
          id: p["id"].to_i,
          name: p["name"],
          description: p["description"],
          image: p["image"],
          github_url: p["github_url"],
          hours: (p["hours_override"] || p["hours"]).to_f,
          status: p["status"],
          created_at: p["created_at"]
        }
      },
      hearted_items: hearted_items,
      refinements: refinements_rows.map { |r|
        base = r["base_probability"].to_f
        boost = r["total_boost"].to_f
        {
          shop_item_id: r["shop_item_id"].to_i,
          item_name: r["item_name"],
          item_image: r["item_image"],
          base_probability: base,
          total_boost: boost,
          effective_probability: [base + boost, 100].min
        }
      },
      stats: {
        project_count: shipped_count,
        in_progress_count: in_progress_count,
        total_hours: total_hours
      }
    })
  end
end
