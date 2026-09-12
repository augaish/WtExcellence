class ApplicationMailer < ActionMailer::Base
  default from: "noreply@#{ENV.fetch('APP_DOMAIN', 'wtexcel.com')}"
  layout "mailer"
end
