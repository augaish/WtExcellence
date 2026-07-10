namespace :ingestion do
  desc "Process the next queued ingestion job"
  task process_next: :environment do
    job = IngestionJobProcessor.process_next_job
    if job
      puts "Enqueued job #{job.id} for processing"
    else
      puts "No queued jobs found"
    end
  end

  desc "Process all queued ingestion jobs"
  task process_all: :environment do
    count = IngestionJobProcessor.process_all_queued_jobs
    puts "Enqueued #{count} jobs for processing"
  end

  desc "Show status of all ingestion jobs"
  task status: :environment do
    puts "\n=== Ingestion Jobs Status ==="
    puts "Queued: #{IngestionJob.queued.count}"
    puts "Processing: #{IngestionJob.processing.count}"
    puts "Completed: #{IngestionJob.completed.count}"
    puts "Failed: #{IngestionJob.failed.count}"
    puts "Total: #{IngestionJob.count}"

    if IngestionJob.queued.any?
      puts "\n=== Queued Jobs ==="
      IngestionJob.queued.order(:created_at).each do |job|
        puts "ID: #{job.id} | Created: #{job.created_at} | File: #{job.input_pdf.filename}"
      end
    end

    if IngestionJob.failed.any?
      puts "\n=== Failed Jobs ==="
      IngestionJob.failed.order(:created_at).each do |job|
        puts "ID: #{job.id} | Failed: #{job.finished_at} | Error: #{job.message}"
      end
    end
  end

  # Deeper diagnostic for a slow/stuck "Processing…" upload: recent jobs with
  # durations, stuck-job detection, ingestion config, and Sidekiq queue state.
  #
  #   bin/kamal app exec -d wtexcel --reuse "bin/rails ingestion:doctor"
  desc "Diagnose stuck/slow standard ingestion (jobs + Sidekiq state)"
  task doctor: :environment do
    puts "== Ingestion config =="
    puts "INGESTION_SERVICE:  #{ENV['INGESTION_SERVICE'].presence || '(unset → multi_stage; falls back to OpenRouter when OLLAMA_URL is blank)'}"
    puts "OLLAMA_URL:         #{ENV['OLLAMA_URL'].presence || '(unset → OpenRouter path used)'}"
    puts "OPENROUTER_MODEL:   #{ENV['OPENROUTER_MODEL'].presence || '(unset → default)'}"
    puts

    puts "== Recent ingestion jobs (newest first) =="
    IngestionJob.order(created_at: :desc).limit(10).each do |j|
      code = begin
        j.standard&.code
      rescue
        "?"
      end
      hb = j.heartbeat_at ? "hb #{((Time.current - j.heartbeat_at) / 60).round(1)}m ago" : "no heartbeat"
      detail = j.progress_detail.present? ? " page #{j.progress_detail}" : ""
      puts "  ##{j.id}  #{j.status.ljust(10)}  #{j.duration_formatted.to_s.ljust(12)}  stage=#{j.progress_stage || '-'}#{detail}  #{hb}  standard=#{code}  created=#{j.created_at&.strftime('%Y-%m-%d %H:%M')}"
      puts "      message: #{j.message}" if j.message.present?
    end
    puts "  (none)" if IngestionJob.count.zero?
    puts

    stuck = IngestionJob.processing.select { |j| j.heartbeat_stale?(15.minutes) }
    if stuck.any?
      puts "⚠️  #{stuck.count} job(s) stuck in 'processing' for >15 min (likely an OOM-killed worker or a hung call)."
      puts "    Re-run one with:"
      puts "    IngestionJob.find(ID).update!(status: 'queued'); ProcessIngestionJob.perform_async(ID)"
      puts
    end

    puts "== Sidekiq =="
    begin
      require "sidekiq/api"
      stats = Sidekiq::Stats.new
      puts "  processed=#{stats.processed}  failed=#{stats.failed}  enqueued=#{stats.enqueued}  busy=#{Sidekiq::Workers.new.size}"
      Sidekiq::Queue.all.each { |q| puts "  queue '#{q.name}': size=#{q.size} latency=#{q.latency.round(1)}s" }
      retries = Sidekiq::RetrySet.new
      puts "  retry set: #{retries.size}"
      retries.first(5).each { |r| puts "    #{r.klass} args=#{r.args.inspect} error=#{r['error_message'].to_s[0, 120]}" }
      dead = Sidekiq::DeadSet.new
      puts "  dead set: #{dead.size}"
      dead.first(5).each { |d| puts "    #{d.klass} args=#{d.args.inspect} error=#{d['error_message'].to_s[0, 120]}" }
    rescue => e
      puts "  Could not read Sidekiq stats: #{e.class}: #{e.message}"
    end
  end
end
