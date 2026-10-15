namespace :hackatime do
  desc "Merge hackatime_project entries that were split on a comma inside a Hackatime project name. Dry run unless APPLY=1"
  task repair_comma_names: :environment do
    apply = ENV["APPLY"] == "1"
    conn = ActiveRecord::Base.connection
    rows = conn.select_all(<<~SQL).to_a
      SELECT p.id, p.status, p.hackatime_project, u.email, u.slack_id
      FROM projects p INNER JOIN users u ON u.id = p.user_id
      WHERE p.hackatime_project IS NOT NULL AND p.hackatime_project != ''
        AND (p.deleted = 0 OR p.deleted IS NULL)
    SQL

    puts "#{apply ? 'APPLY' : 'DRY RUN'}: checking #{rows.size} project(s)"
    fixed = 0
    skipped = 0

    rows.each do |row|
      entries = HackatimeService.split_project_list(row["hackatime_project"])
      next if entries.size < 2

      ht_user_id = HackatimeService.parse_hackatime_projects(row["hackatime_project"]).filter_map { |e| e[:hackatime_user_id] }.first
      ht_user_id ||= HackatimeService.get_user(row["email"], row["slack_id"])&.dig(:user_id)
      unless ht_user_id
        skipped += 1
        next
      end

      ht_projects = HackatimeService.fetch_user_projects(ht_user_id)
      unless ht_projects
        skipped += 1
        next
      end

      comma_names = ht_projects.map { |p| HackatimeService.strip_entry_id(p["name"]) }
        .select { |n| n.include?(",") }.uniq
        .map { |n| [n, n.split(",").map(&:strip).reject(&:empty?)] }
        .select { |_, pieces| pieces.size > 1 }
        .sort_by { |_, pieces| -pieces.size }
      next if comma_names.empty?

      changed = false
      comma_names.each do |full_name, pieces|
        loop do
          names = entries.map { |e| HackatimeService.strip_entry_id(e) }
          idx = (0..(names.size - pieces.size)).find { |i| names[i, pieces.size] == pieces }
          break unless idx
          prefix = entries[idx][0, entries[idx].length - names[idx].length]
          entries[idx, pieces.size] = ["#{prefix}#{full_name}"]
          changed = true
        end
      end
      next unless changed

      new_value = HackatimeService.join_project_list(entries)
      puts "project #{row['id']} (#{row['status']}): #{row['hackatime_project'].inspect} -> #{new_value.inspect}"
      fixed += 1
      next unless apply

      conn.execute("UPDATE projects SET hackatime_project = #{conn.quote(new_value)}, updated_at = NOW() WHERE id = #{row['id'].to_i}")
      result = HackatimeSyncJob.perform_now(row["id"])
      puts "  hours now #{result[:hours].inspect}#{result[:updated] ? ' (updated)' : ''}"
    end

    puts "#{fixed} project(s) #{apply ? 'fixed' : 'would be fixed'}, #{skipped} skipped (no Hackatime user or API error)"
  end
end
