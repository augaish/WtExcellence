# frozen_string_literal: true

class Dashboard::NotificationsController < Dashboard::BaseController
  def index
    @pagy, @notifications = pagy(current_user.notifications.recent, items: 25)
    @has_unread_notifications = current_user.notifications.unread.exists?
  end

  # Marks only this notification as read, then redirects to its target. Does not touch other notifications.
  def read_and_go
    notification = current_user.notifications.find(params[:id])
    notification.mark_read! # only this one record
    path = notification.link_path.to_s.strip
    redirect_to path.start_with?("/") ? path : dashboard_notifications_path, allow_other_host: false
  end

  def mark_read
    notification = current_user.notifications.find(params[:id])
    notification.mark_read!
    redirect_to dashboard_notifications_path, notice: t("notifications_marked_read", default: "Notification marked as read.")
  end

  def mark_all_read
    current_user.notifications.unread.update_all(read_at: Time.current)
    redirect_to dashboard_notifications_path, notice: t("all_notifications_marked_read", default: "All notifications marked as read.")
  end
end
