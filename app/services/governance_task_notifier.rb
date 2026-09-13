# In-app notices for the scoped governance tasks: the person named as owner
# of a commitment or of a risk's control is told, and the person who assigned
# it is told when the work comes back for review.
class GovernanceTaskNotifier
  def self.assigned(membership:, record:, actor:)
    recipient = membership&.user
    return if recipient.nil? || recipient == actor

    create(recipient: recipient, record: record, kind: "governance_task_assigned", actor: actor,
      link_path: task_path(record))
  end

  def self.submitted(record:, actor:)
    recipient = reviewer_for(record)
    return if recipient.nil? || recipient == actor

    create(recipient: recipient, record: record, kind: "governance_task_submitted", actor: actor,
      link_path: record_path(record))
  end

  def self.task_path(record)
    routes = Rails.application.routes.url_helpers
    record.is_a?(Risk) ? routes.dashboard_control_task_path(record) : routes.dashboard_commitment_task_path(record)
  end

  def self.record_path(record)
    routes = Rails.application.routes.url_helpers
    record.is_a?(Risk) ? routes.dashboard_risk_management_path(record) : routes.dashboard_customer_commitment_path(record)
  end

  # A commitment's owner is the person doing the work, so its creator reviews
  # it. A risk's owner is distinct from its control owner and reviews the
  # control; failing that, the creator does.
  def self.reviewer_for(record)
    return record.created_by unless record.is_a?(Risk)

    record.owner&.user || record.created_by
  end

  def self.create(recipient:, record:, kind:, actor:, link_path:)
    Notification.create!(
      recipient: recipient, source: record, kind: kind, link_path: link_path,
      title: I18n.t("user_notifications.#{kind}_title", title: record.title, actor_name: actor&.name.to_s,
        locale: recipient.try(:locale).presence || I18n.default_locale),
      payload: { record_type: record.class.name, record_id: record.id, title: record.title, actor_name: actor&.name }
    )
  rescue => e
    Rails.logger.warn "Governance task notification failed: #{e.class}: #{e.message}"
    nil
  end
end
