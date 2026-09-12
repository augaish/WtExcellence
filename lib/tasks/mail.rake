namespace :mail do
  # Sends one test email straight through SMTP and prints the real error when
  # it fails, instead of the silence a queued email leaves behind.
  #
  #   bin/rails "mail:test[you@example.com]"
  desc "Send a test email and print the SMTP settings in use and any error"
  task :test, [ :to ] => :environment do |_, args|
    to = args[:to].to_s.strip
    abort "Usage: bin/rails \"mail:test[you@example.com]\"" if to.blank?

    settings = ActionMailer::Base.smtp_settings
    puts "Delivery method: #{ActionMailer::Base.delivery_method}"
    puts "SMTP server:     #{settings[:address].presence || '(missing)'}:#{settings[:port].presence || '(missing)'}"
    puts "SMTP login:      #{settings[:user_name].present? ? 'set' : '(missing)'}"
    puts "SMTP password:   #{settings[:password].present? ? 'set' : '(missing)'}"
    puts "SMTP domain:     #{settings[:domain].presence || '(missing)'}"
    puts "From:            #{ApplicationMailer.default[:from]}"
    puts "Link host:       #{Rails.application.config.action_mailer.default_url_options.inspect}"

    begin
      TestMailer.ping(to).deliver_now
      puts "Sent to #{to}. Check the inbox and the spam folder."
    rescue => e
      puts "FAILED: #{e.class}: #{e.message}"
      exit 1
    end
  end
end
