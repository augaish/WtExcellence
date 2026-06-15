# Stub class to handle stale AsyncAddSource jobs in the Sidekiq queue
# This class was removed/renamed but old jobs may still be in the queue
class AsyncAddSource
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: false

  def perform(*args)
    Rails.logger.warn "AsyncAddSource job received with args: #{args.inspect}. This job class has been removed. Discarding job."
    # Job is discarded silently - no error raised
  end
end
