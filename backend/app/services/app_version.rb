module AppVersion
  REPO_URL = "https://github.com/hackclub/scraps".freeze

  # Resolved once at boot. Order of preference:
  #   1. an explicit env var (set by the deploy, or a Docker build arg)
  #   2. a REVISION file written at image build time
  #   3. the local git checkout (dev) — read directly, no shelling out
  def self.from_git
    root = Rails.root
    root = root.parent while root != root.parent && !root.join(".git").exist?
    git = root.join(".git")
    return nil unless git.exist?

    head = File.read(git.join("HEAD")).strip
    return head unless head.start_with?("ref:")

    ref = head.sub("ref: ", "")
    packed = git.join("packed-refs")
    File.read(git.join(ref)).strip
  rescue StandardError
    (File.foreach(packed).find { |l| l.include?(ref) }&.split&.first if defined?(packed) && packed&.exist?)
  end

  SHA = (
    ENV["GIT_SHA"].presence ||
    ENV["SOURCE_VERSION"].presence ||
    ENV["RENDER_GIT_COMMIT"].presence ||
    ENV["COOLIFY_GIT_COMMIT_SHA"].presence ||
    ENV["NOMAD_META_git_sha"].presence ||
    (File.read(Rails.root.join("REVISION")).strip.presence rescue nil) ||
    from_git.presence ||
    "unknown"
  ).freeze

  SHORT = SHA == "unknown" ? "unknown" : SHA[0, 7]

  def self.commit_url
    SHA == "unknown" ? nil : "#{REPO_URL}/commit/#{SHA}"
  end

  def self.info
    { sha: SHA, short: SHORT, url: commit_url }
  end
end
