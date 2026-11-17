class ReviewQueueService
  def self.positions(conn, project_ids)
    ids = Array(project_ids).map(&:to_i).select(&:positive?).uniq
    return {} if ids.empty?

    conn.select_all(<<~SQL).to_a.each_with_object({}) { |r, h| h[r["id"].to_i] = { position: r["position"].to_i, total: r["total"].to_i } }
      SELECT id, position, total FROM (
        SELECT id, ROW_NUMBER() OVER (ORDER BY updated_at ASC, id ASC) AS position, COUNT(*) OVER () AS total
        FROM projects WHERE status = 'waiting_for_review'
      ) q
      WHERE id IN (#{ids.join(',')})
    SQL
  end
end
