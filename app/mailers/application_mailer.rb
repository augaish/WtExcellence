class ApplicationMailer < ActionMailer::Base
  # Emails leave from the domain verified at the mail provider (MAIL_DOMAIN),
  # which may differ from the site's domain for a while.
  default from: "noreply@#{ENV.fetch('MAIL_DOMAIN') { ENV.fetch('APP_DOMAIN', 'wtexcel.com') }}"
  layout "mailer"
end
