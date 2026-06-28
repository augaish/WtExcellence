class ApplicationMailer < ActionMailer::Base
  default from: "noreply@#{ENV.fetch('APP_DOMAIN', 'wtexcellence.com')}"
  layout "mailer"
end
