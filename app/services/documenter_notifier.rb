# In-app notices for the Documenter: a task handed to you, a task handed back,
# an approval asked of your unit, a rejection to deal with, a document
# published for everyone. In-app only, as the product owner chose for now.
class DocumenterNotifier
  KINDS = %w[
    record_task_assigned record_task_submitted record_approval_requested
    record_approval_rejected record_published
  ].freeze

  def self.notify(recipient:, record:, kind:, actor: nil, unit: nil)
    Notification.create!(
      recipient: recipient,
      source: record,
      kind: kind,
      title: I18n.t("user_notifications.#{kind}_title", locale: recipient.try(:locale).presence || I18n.default_locale,
        title: record.display_title, actor_name: actor&.name.to_s, unit: unit.to_s, stage: PpStage.label(record.stage_key)),
      link_path: Rails.application.routes.url_helpers.dashboard_pp_record_path(record),
      payload: { record_id: record.id, record_title: record.display_title, actor_name: actor&.name, unit: unit, stage_key: record.stage_key }
    )
  rescue => e
    Rails.logger.warn "Documenter notification failed: #{e.class}: #{e.message}"
    nil
  end

  # Publication is for everyone in the company.
  def self.notify_published(record)
    record.company.users.find_each { |user| notify(recipient: user, record: record, kind: "record_published") }
  end
end
