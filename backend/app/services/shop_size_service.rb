class ShopSizeService
  def self.parse(raw)
    list = raw.is_a?(Array) ? raw : JSON.parse(raw.to_s.presence || "[]")
    list.is_a?(Array) ? list : []
  rescue JSON::ParserError
    []
  end

  def self.sized?(raw)
    parse(raw).any?
  end

  def self.in_stock(raw)
    parse(raw).select { |v| v["count"].to_i > 0 }
  end

  def self.available(raw, size)
    variant = parse(raw).find { |v| v["name"].to_s == size.to_s }
    variant ? variant["count"].to_i : 0
  end

  def self.shift(variants, size, delta)
    variants.map do |v|
      v["name"].to_s == size.to_s ? v.merge("count" => [v["count"].to_i + delta, 0].max) : v
    end
  end

  def self.adjust(conn, item_id, size, delta)
    return if size.blank? || delta.zero?

    row = conn.select_one("SELECT size_variants FROM shop_items WHERE id = #{item_id.to_i} FOR UPDATE")
    return unless row

    variants = parse(row["size_variants"])
    return unless variants.any? { |v| v["name"].to_s == size.to_s }

    conn.execute("UPDATE shop_items SET size_variants = #{conn.quote(shift(variants, size, delta).to_json)}, updated_at = NOW() WHERE id = #{item_id.to_i}")
  end
end
