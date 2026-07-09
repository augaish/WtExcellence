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
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
