# One plain email, used by `bin/rails mail:test[address]` to prove the mail
# server accepts what the app sends.
class TestMailer < ApplicationMailer
  def ping(to)
    mail(to: to, subject: "WTExcel mail test", body: "This is a test email from #{Rails.env}.")
  end
end
