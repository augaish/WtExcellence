class CronSetter
  # Run to reset the cron (from the console)
  def self.set_cron
    puts "Setting up schedule (sidekiq.rb)"
    hash = {}

    Sidekiq::Cron::Job.load_from_hash!(hash)

    puts "Finished setting up schedule (sidekiq.rb)"
  end
end
