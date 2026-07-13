module EffectiveHoursService
  def self.project_shipped_date(project_id)
    row = ActiveRecord::Base.connection.select_one(
      "SELECT MIN(created_at) AS first_shipped FROM project_activity WHERE project_id = $1 AND action = 'project_shipped'",
      "ProjectShippedDate", [project_id]
    )
    row && row["first_shipped"] ? Time.parse(row["first_shipped"].to_s) : nil
  end

  def self.compute_for_project(project)
    hours = (project["hours_override"] || project["hoursOverride"] || project["hours"] || 0).to_f
    hackatime_project = project["hackatime_project"] || project["hackatimeProject"]
    return { overlapping_projects: [], deducted_hours: 0, effective_hours: hours } if hackatime_project.blank?

    project_id = project["id"]
    user_id = project["user_id"] || project["userId"]
    hackatime_names = hackatime_project.split(",").map(&:strip).reject(&:empty?)
    return { overlapping_projects: [], deducted_hours: 0, effective_hours: hours } if hackatime_names.empty?

    project_shipped_date = project_shipped_date(project_id) || Time.now.utc
    deduct_before = project_shipped_date

    shipped = ActiveRecord::Base.connection.select_all(<<~SQL, "ShippedProjects", [user_id, project_id])
      SELECT id, name, hours, hours_override, hackatime_project
      FROM projects
      WHERE user_id = $1
        AND status = 'shipped'
        AND (deleted = 0 OR deleted IS NULL)
        AND id != $2
    SQL

    return { overlapping_projects: [], deducted_hours: 0, effective_hours: hours } if shipped.empty?

    shipped_ids = shipped.map { |r| r["id"] }
    shipped_dates_rows = ActiveRecord::Base.connection.select_all(<<~SQL, "ShippedDates")
      SELECT project_id, MIN(created_at) AS first_shipped
      FROM project_activity
      WHERE project_id IN (#{shipped_ids.join(",")}) AND action = 'project_shipped'
      GROUP BY project_id
    SQL
    shipped_dates = {}
    shipped_dates_rows.each do |r|
      shipped_dates[r["project_id"].to_i] = Time.parse(r["first_shipped"].to_s) if r["first_shipped"]
    end

    overlapping = []
    deducted = 0
    shipped.each do |op|
      next if op["hackatime_project"].blank?
      op_shipped_date = shipped_dates[op["id"].to_i]
      next unless op_shipped_date && op_shipped_date < deduct_before
      op_names = op["hackatime_project"].split(",").map(&:strip).reject(&:empty?)
      next unless op_names.any? { |n| hackatime_names.include?(n) }
      op_hours = (op["hours_override"] || op["hours"] || 0).to_f
      overlapping << { id: op["id"].to_i, name: op["name"], hours: op_hours }
      deducted += op_hours
    end

    { overlapping_projects: overlapping, deducted_hours: deducted, effective_hours: [0, hours - deducted].max }
  end
end
