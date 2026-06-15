class IngestionJobProcessor
  def self.process_next_job
    job = IngestionJob.process_next_queued_job

    if job
      Rails.logger.info "Found queued job: #{job.id}"
      ProcessIngestionJob.perform_async(job.id)
      Rails.logger.info "Enqueued job #{job.id} for processing"
      job
    else
      Rails.logger.info "No queued jobs found"
      nil
    end
  end

  def self.process_all_queued_jobs
    queued_jobs = IngestionJob.queued.order(:created_at)

    Rails.logger.info "Found #{queued_jobs.count} queued jobs"

    queued_jobs.each do |job|
      ProcessIngestionJob.perform_async(job.id)
      Rails.logger.info "Enqueued job #{job.id} for processing"
    end

    queued_jobs.count
  end
end
