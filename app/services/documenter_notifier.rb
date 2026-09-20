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

  # A record moved: the people who act at the new stage are told, and the
  # owner is told whenever someone else moved it. A return carries its reason.
  def self.notify_stage_change(record, from:, to:, direction:, reason:, actor:)
    return if PpStage.terminal?(to)

    path = Rails.application.routes.url_helpers.dashboard_documenter_record_path(record)
    kind = direction == "backward" ? "record_returned" : "record_stage_entered"
    recipients = actors_at(record, to) + [ record.owner_user ]
    Notify.people(recipients, kind: kind, source: record, link_path: path, actor: actor,
      title: record.display_title, stage: PpStage.label(to), from_stage: (from ? PpStage.label(from) : ""), reason: reason.to_s)
  rescue => e
    Rails.logger.warn "Stage-change notification failed: #{e.class}: #{e.message}"
  end

  # Who acts at a stage: the verifier, the owning unit's head, or the P&P
  # managers. Approval stages tell their approvers through the approval itself.
  def self.actors_at(record, stage)
    case PpStage.actor_of(stage)
    when :verifier then [ record.verifier_user ]
    when :unit_head then [ record.owning_unit_head ]
    when :pp_manager, :publisher
      ids = record.company.company_users.where(pp_manager: true).pluck(:user_id) +
        record.company.company_users.where(role: CompanyUser::ROLES[:company_admin]).pluck(:user_id)
      User.where(id: ids.uniq).to_a
    else []
    end.compact
  end

  # Publication is for everyone in the company.
  def self.notify_published(record)
    record.company.users.find_each { |user| notify(recipient: user, record: record, kind: "record_published") }
  end
end
