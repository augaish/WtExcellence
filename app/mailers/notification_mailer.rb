# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  def notification_email(notification)
    @notification = notification
    @recipient = notification.recipient
    @link_url = build_notification_link_url(notification)
    # Both languages for the email body
    @title_en = notification.title_in_locale(:en)
    @title_ar = notification.title_in_locale(:ar)
    @view_in_app_en = I18n.t("view_in_app", locale: :en, default: "View in app")
    @view_in_app_ar = I18n.t("view_in_app", locale: :ar, default: "عرض في التطبيق")
    @footer_en = I18n.t("notification_email_footer", locale: :en, default: "You received this email because you have email notifications enabled in your account settings.")
    @footer_ar = I18n.t("notification_email_footer", locale: :ar, default: "تلقيت هذا البريد لأنك مفعل إشعارات البريد الإلكتروني في إعدادات حسابك.")
    # Subject in English (inbox preview)
    mail(to: @recipient.email, subject: @title_en)
  end

  private

  def build_notification_link_url(notification)
    return notification.link_path if notification.link_path.to_s.start_with?("http")
    "#{root_url.chomp('/')}#{notification.link_path}"
  end
end
