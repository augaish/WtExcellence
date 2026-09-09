# config/initializers/sidekiq.rb

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

  # Standard ingestion (OCR + LLM) is CPU/memory-heavy. Run it in a dedicated
  # single-threaded capsule so only ONE standard is processed at a time — this
  # prevents concurrent OCR jobs from thrashing memory on a small box, while the
  # main capsule keeps processing light jobs concurrently.
  #
  # Gated by an env var so the capsule only runs on the container meant to
  # handle heavy ingestion (the `job` role) — never on the tiny `cron_small`
  # container, which would OOM.
  if ENV["SIDEKIQ_INGESTION_CAPSULE"] == "1"
    config.capsule("ingestion") do |cap|
      cap.concurrency = 1
      cap.queues = %w[ingestion]
    end
  end

  # Reaper for crashed ingestion workers: marks stale "processing" jobs as
  # failed with a clear reason (see IngestionReaperJob). Registered on boot;
  # create is idempotent by name. Runs on the cron_small queue.
  config.on(:startup) do
    Sidekiq::Cron::Job.create(
      name: "ingestion_reaper",
      cron: "*/5 * * * *",
      class: "IngestionReaperJob",
      queue: "cron_small"
    )
  rescue => e
    Rails.logger.error "Failed to register ingestion_reaper cron: #{e.class}: #{e.message}"
  end

  # Warns before a delegation of authority lapses. Daily is enough: the warning
  # window is thirty days, and an hourly run would only repeat itself.
  config.on(:startup) do
    Sidekiq::Cron::Job.create(
      name: "delegation_expiry_notice",
      cron: "0 6 * * *",
      class: "DelegationExpiryNoticeJob",
      queue: "cron_small"
    )
  rescue => e
    Rails.logger.error "Failed to register delegation_expiry_notice cron: #{e.class}: #{e.message}"
  end

  # Silence counts as approval once the P&P Manager's period has passed.
  config.on(:startup) do
    Sidekiq::Cron::Job.create(
      name: "approval_auto_approve",
      cron: "0 7 * * *",
      class: "ApprovalAutoApproveJob",
      queue: "cron_small"
    )
  rescue => e
    Rails.logger.error "Failed to register approval_auto_approve cron: #{e.class}: #{e.message}"
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
