# require 'sidekiq-scheduler'

class KamalCronSmall
  include Sidekiq::Worker

  sidekiq_options queue: "cron_small"

  def perform(code)
    Rails.logger.info "Running KamalCronSmall #{code}"
    eval(code)
    Rails.logger.info "Finished Running KamalCronSmall #{code}"
  end
end
