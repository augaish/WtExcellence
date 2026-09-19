# Notices about a person's own account.
class AccountMailer < ApplicationMailer
  # Sent to both the new and the old address, so a change nobody asked for is
  # noticed at the old one.
  def email_changed(user, old_email)
    @user = user
    @old_email = old_email
    mail(to: [ user.email, old_email ].uniq, subject: I18n.t("account_email.mail_subject"))
  end
end
