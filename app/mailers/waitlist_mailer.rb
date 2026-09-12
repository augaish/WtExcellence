class WaitlistMailer < ApplicationMailer
  def welcome_email(user, company, locale = nil)
    @user = user
    @company = company
    @locale = locale || user.locale_code || I18n.default_locale
    @is_rtl = @locale.to_s == 'ar'
    
    mail(
      from: "info@#{ENV.fetch('MAIL_DOMAIN') { ENV.fetch('APP_DOMAIN', 'wtexcel.com') }}",
      to: @user.email,
      subject: @is_rtl ? "مرحباً بك في Way to Excellence - أنت في قائمة الانتظار!" : "Welcome to Way to Excellence - You're on the Waitlist!"
    )
  end
end
