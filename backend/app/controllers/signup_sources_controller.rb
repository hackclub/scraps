class SignupSourcesController < ApplicationController
  before_action :require_admin_role

  def index
    conn = ActiveRecord::Base.connection
    counts = conn.select_all(<<~SQL).to_a.index_by { |r| r["signup_source"] }
      SELECT signup_source,
        COUNT(*) AS signups,
        COUNT(*) FILTER (WHERE verification_status = 'verified') AS verified
      FROM users
      WHERE signup_source IS NOT NULL
      GROUP BY signup_source
    SQL

    sources = SignupSource.order(created_at: :desc).map do |s|
      c = counts.delete(s.slug) || {}
      { id: s.id, slug: s.slug, note: s.note, created_at: s.created_at, signups: c["signups"].to_i, verified: c["verified"].to_i }
    end

    untracked = counts.values.map do |c|
      { slug: c["signup_source"], signups: c["signups"].to_i, verified: c["verified"].to_i }
    end.sort_by { |c| -c[:signups] }

    render_json({ sources: sources, untracked: untracked })
  end

  def create
    slug = params[:slug].to_s.strip.downcase
    unless SignupSource.valid_slug?(slug)
      return render_json({ error: "Use 1-32 lowercase letters, numbers, - or _" }, status: :bad_request)
    end
    if SignupSource.exists?(slug: slug)
      return render_json({ error: "That source already exists" }, status: :conflict)
    end

    source = SignupSource.create!(slug: slug, note: params[:note].to_s.strip.presence)
    render_json({ id: source.id, slug: source.slug })
  end

  def destroy
    source = SignupSource.find_by(id: params[:id])
    return render_json({ error: "Not found" }, status: :not_found) unless source
    source.destroy
    render_json({ success: true })
  end
end
