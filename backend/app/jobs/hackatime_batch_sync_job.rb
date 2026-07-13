class HackatimeBatchSyncJob < ApplicationJob
  queue_as :default

  def perform
    project_ids = ActiveRecord::Base.connection
      .select_all("SELECT id FROM projects WHERE status != 'shipped' AND status != 'permanently_rejected' AND (deleted = 0 OR deleted IS NULL) AND hackatime_project IS NOT NULL AND hackatime_project != ''")
      .map { |r| r["id"].to_i }

    project_ids.each { |id| HackatimeSyncJob.perform_later(id) }
    Rails.logger.info("[HackatimeBatchSyncJob] Enqueued #{project_ids.length} projects")
  end
end
