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

namespace :ingestion do
  # Ground-truth inspector for "the clause tree looks empty":
  #
  #   bin/kamal app exec -d wtexcel --reuse "bin/rails ingestion:inspect"
  #
  # Prints, for the most recent standards: per-language translation coverage
  # (how many clauses actually have titles in en/ar, with samples), checkpoint
  # coverage, plus tails of the latest extracted-text and LLM-response debug
  # files so we can see what OCR fed the model and what came back.
  desc "Inspect clause translation coverage + latest OCR/LLM debug output"
  task inspect: :environment do
    Standard.order(created_at: :desc).limit(3).each do |std|
      puts "== Standard #{std.code} (#{std.display_name('en')}) =="
      std.standard_versions.order(created_at: :desc).limit(2).each do |v|
        clauses = v.clauses
        puts "  Version #{v.version_label} (#{v.status}) — #{clauses.count} clauses"
        %w[en ar].each do |lang|
          total = ClauseTranslation.joins(:clause).where(clauses: { standard_version_id: v.id }, language_code: lang).count
          titled = ClauseTranslation.joins(:clause).where(clauses: { standard_version_id: v.id }, language_code: lang).where.not(title: [ nil, "" ]).count
          samples = ClauseTranslation.joins(:clause).where(clauses: { standard_version_id: v.id }, language_code: lang).where.not(title: [ nil, "" ]).limit(3).pluck(:title)
          puts "    [#{lang}] translations=#{total} with_title=#{titled} samples=#{samples.map { |t| t.to_s[0, 40] }.inspect}"
        end
        cp_total = ChecklistItemTranslation.joins(checklist_item: :clause).where(clauses: { standard_version_id: v.id }).count
        cp_texted = ChecklistItemTranslation.joins(checklist_item: :clause).where(clauses: { standard_version_id: v.id }).where.not(text: [ nil, "" ]).count
        puts "    checkpoints: translations=#{cp_total} with_text=#{cp_texted}"
      end
    end

    puts
    puts "== Latest OCR extracted text (tmp/chunks) =="
    latest_txt = Dir.glob(Rails.root.join("tmp", "chunks", "extracted_text*ature*.txt").to_s).max_by { |f| File.mtime(f) }
    latest_txt ||= Dir.glob(Rails.root.join("tmp", "chunks", "extracted_text*.txt").to_s).max_by { |f| File.mtime(f) }
    if latest_txt
      content = File.read(latest_txt)
      puts "  #{File.basename(latest_txt)} (#{content.length} chars) — first 400:"
      puts "  " + content[0, 400].to_s.gsub("\n", " ")
    else
      puts "  (no extracted-text debug file — OCR may not have run in this container since boot)"
    end

    puts
    puts "== Latest LLM response (tmp/chunks) =="
    latest_llm = Dir.glob(Rails.root.join("tmp", "chunks", "llm_response*.txt").to_s).max_by { |f| File.mtime(f) }
    if latest_llm
      content = File.read(latest_llm)
      puts "  #{File.basename(latest_llm)} (#{content.length} chars) — first 600:"
      puts "  " + content[0, 600].to_s.gsub("\n", " ")
    else
      puts "  (no LLM response debug file found)"
    end
  end
end
