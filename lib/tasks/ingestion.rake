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
end
