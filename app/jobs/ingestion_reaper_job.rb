# Safety net for crashed ingestion workers. Open-source Sidekiq permanently
# loses a job whose process dies mid-run (crash recovery is a Sidekiq Pro
# feature), which left IngestionJob rows in "processing" forever with nothing
# surfaced to the user. This reaper marks any processing job whose heartbeat
# has gone stale as failed, with a clear reason shown in the standards UI.
#
# Runs every 5 minutes via sidekiq-cron (registered in
# config/initializers/sidekiq.rb) on the cron_small queue.
class IngestionReaperJob
  include Sidekiq::Job

  sidekiq_options queue: :cron_small, retry: false

  # OCR heartbeats every page (seconds apart); the LLM call can legitimately
  # run several minutes without one. 15 minutes of silence means the worker
  # is gone.
  STALE_AFTER = 15.minutes

  def perform
    IngestionJob.processing.find_each do |job|
      next unless job.heartbeat_stale?(STALE_AFTER)

      Rails.logger.warn "IngestionReaper: job #{job.id} stale (last heartbeat #{job.heartbeat_at || job.started_at}), marking failed"
      job.fail!(
        "Worker stopped mid-processing (no progress for #{(STALE_AFTER / 60).to_i}+ minutes) — " \
        "most likely the server ran out of memory. Use Retry or re-upload the PDF."
      )
    end
  end
end
