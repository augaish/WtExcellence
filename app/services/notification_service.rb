# frozen_string_literal: true

class NotificationService
  # Notify a user they were assigned to a CAPA.
  # @param recipient [User]
  # @param capa [Capa]
  # @param actor [User] who performed the assignment
  def self.notify_capa_assigned(recipient:, capa:, actor:)
    return if recipient.blank? || capa.blank? || actor.blank?

    title = I18n.t(
      "user_notifications.capa_assigned_title",
      actor_name: actor.name,
      capa_code: capa.friendly_code.presence || capa.title
    )
    link_path = Rails.application.routes.url_helpers.dashboard_capa_management_show_path(capa.id)

    notification = Notification.create!(
      recipient: recipient,
      kind: "capa_assigned",
      title: title,
      link_path: link_path,
      source: capa,
      payload: {
        actor_name: actor.name,
        actor_id: actor.id,
        capa_id: capa.id,
        capa_title: capa.title,
        capa_friendly_code: capa.friendly_code
      }
    )
    send_notification_email_if_enabled(notification)
  end

  # Notify a user they were assigned to a CAPA action (corrective/preventive action item).
  # @param recipient [User]
  # @param capa [Capa]
  # @param capa_action [CapaAction]
  # @param actor [User] who performed the assignment
  def self.notify_capa_action_assigned(recipient:, capa:, capa_action:, actor:)
    return if recipient.blank? || capa.blank? || capa_action.blank? || actor.blank?

    title = I18n.t(
      "user_notifications.capa_action_assigned_title",
      actor_name: actor.name,
      capa_code: capa.friendly_code.presence || capa.title,
      action_title: capa_action.title
    )
    link_path = Rails.application.routes.url_helpers.dashboard_capa_management_show_path(capa.id)

    notification = Notification.create!(
      recipient: recipient,
      kind: "capa_action_assigned",
      title: title,
      link_path: link_path,
      source: capa,
      payload: {
        actor_name: actor.name,
        actor_id: actor.id,
        capa_id: capa.id,
        capa_title: capa.title,
        capa_friendly_code: capa.friendly_code,
        capa_action_id: capa_action.id,
        capa_action_title: capa_action.title
      }
    )
    send_notification_email_if_enabled(notification)
  end

  # The assignee submitted the action for review: tell whoever manages the
  # CAPA — its creator, and the people assigned to the CAPA itself.
  def self.notify_capa_action_submitted(capa:, capa_action:, actor:)
    reviewers = capa_reviewers(capa) - [ actor ]
    reviewers.each do |recipient|
      create_action_notification(recipient: recipient, capa: capa, capa_action: capa_action, actor: actor, kind: "capa_action_submitted")
    end
  end

  # The reviewer accepted or sent it back: tell the assignees.
  def self.notify_capa_action_reviewed(capa:, capa_action:, actor:, outcome:)
    kind = outcome == "done" ? "capa_action_accepted" : "capa_action_changes_requested"
    (capa_action.company_users.includes(:user).map(&:user) - [ actor ]).each do |recipient|
      create_action_notification(recipient: recipient, capa: capa, capa_action: capa_action, actor: actor, kind: kind)
    end
  end

  def self.capa_reviewers(capa)
    people = capa.capa_assignments.includes(company_user: :user).map { |a| a.company_user&.user }
    people << capa.created_by if capa.created_by
    people.compact.uniq
  end

  def self.create_action_notification(recipient:, capa:, capa_action:, actor:, kind:)
    notification = Notification.create!(
      recipient: recipient, kind: kind, source: capa,
      title: I18n.t("user_notifications.#{kind}_title", actor_name: actor.name,
        capa_code: capa.friendly_code.presence || capa.title, action_title: capa_action.title,
        locale: recipient.try(:locale).presence || I18n.default_locale),
      link_path: Rails.application.routes.url_helpers.dashboard_capa_action_show_path(capa.id, capa_action.id),
      payload: { actor_name: actor.name, actor_id: actor.id, capa_id: capa.id, capa_action_id: capa_action.id, capa_action_title: capa_action.title }
    )
    send_notification_email_if_enabled(notification)
  rescue => e
    Rails.logger.warn "CAPA action notification failed: #{e.class}: #{e.message}"
    nil
  end

  # Notify a user they were unassigned from a CAPA action (corrective/preventive action item).
  # @param recipient [User]
  # @param capa [Capa]
  # @param capa_action [CapaAction]
  # @param actor [User] who performed the unassignment
  def self.notify_capa_action_unassigned(recipient:, capa:, capa_action:, actor:)
    return if recipient.blank? || capa.blank? || capa_action.blank? || actor.blank?

    title = I18n.t(
      "user_notifications.capa_action_unassigned_title",
      actor_name: actor.name,
      capa_code: capa.friendly_code.presence || capa.title,
      action_title: capa_action.title
    )
    link_path = Rails.application.routes.url_helpers.dashboard_capa_management_show_path(capa.id)

    notification = Notification.create!(
      recipient: recipient,
      kind: "capa_action_unassigned",
      title: title,
      link_path: link_path,
      source: capa,
      payload: {
        actor_name: actor.name,
        actor_id: actor.id,
        capa_id: capa.id,
        capa_title: capa.title,
        capa_friendly_code: capa.friendly_code,
        capa_action_id: capa_action.id,
        capa_action_title: capa_action.title
      }
    )
    send_notification_email_if_enabled(notification)
  end

  # Notify a user they were unassigned from a CAPA.
  # @param recipient [User]
  # @param capa [Capa]
  # @param actor [User] who performed the unassignment
  def self.notify_capa_unassigned(recipient:, capa:, actor:)
    return if recipient.blank? || capa.blank? || actor.blank?

    title = I18n.t(
      "user_notifications.capa_unassigned_title",
      actor_name: actor.name,
      capa_code: capa.friendly_code.presence || capa.title
    )
    link_path = Rails.application.routes.url_helpers.dashboard_capa_management_show_path(capa.id)

    notification = Notification.create!(
      recipient: recipient,
      kind: "capa_unassigned",
      title: title,
      link_path: link_path,
      source: capa,
      payload: {
        actor_name: actor.name,
        actor_id: actor.id,
        capa_id: capa.id,
        capa_title: capa.title,
        capa_friendly_code: capa.friendly_code
      }
    )
    send_notification_email_if_enabled(notification)
  end

  # Notify all users assigned to the CAPA that evidence was attached.
  # Skips the actor (who attached the document).
  # @param capa [Capa]
  # @param actor [User] who attached the document
  # @param document_name [String] display name of the document (optional if document_count given)
  # @param document_count [Integer] if > 1, title uses "N documents" instead of document_name
  def self.notify_capa_evidence_attached(capa:, actor:, document_name: nil, document_count: nil)
    return if capa.blank? || actor.blank?
    return if document_name.blank? && document_count.to_i < 1

    recipients = capa.users.where.not(id: actor.id)
    return if recipients.empty?

    if document_count.to_i > 1
      title = I18n.t(
        "user_notifications.capa_evidence_attached_count_title",
        actor_name: actor.name,
        capa_code: capa.friendly_code.presence || capa.title,
        count: document_count
      )
    else
      title = I18n.t(
        "user_notifications.capa_evidence_attached_title",
        actor_name: actor.name,
        capa_code: capa.friendly_code.presence || capa.title,
        document_name: document_name.presence || I18n.t("user_notifications.document", default: "a document")
      )
    end

    link_path = Rails.application.routes.url_helpers.dashboard_capa_management_show_path(capa.id)

    recipients.find_each do |recipient|
      notification = Notification.create!(
        recipient: recipient,
        kind: "capa_evidence_attached",
        title: title,
        link_path: link_path,
        source: capa,
        payload: {
          actor_name: actor.name,
          actor_id: actor.id,
          capa_id: capa.id,
          capa_title: capa.title,
          capa_friendly_code: capa.friendly_code,
          document_name: document_name,
          document_count: document_count
        }
      )
      send_notification_email_if_enabled(notification)
    end
  end

  # Notify company auditors when evidence is attached to a CAPA or CAPA action (so they can review).
  # @param capa [Capa]
  # @param actor [User] who attached the document
  # @param capa_action [CapaAction] optional; when present, link goes to the action page
  # @param document_name [String]
  # @param document_count [Integer] optional
  def self.notify_auditors_capa_evidence_attached(capa:, actor:, document_name: nil, document_count: nil, capa_action: nil)
    return if capa.blank? || actor.blank?
    return if document_name.blank? && document_count.to_i < 1
    return unless capa.company_id.present?

    auditor_user_ids = CompanyUser.where(company_id: capa.company_id, role: "company_auditor").pluck(:user_id)
    recipients = User.where(id: auditor_user_ids).where.not(id: actor.id)
    return if recipients.empty?

    capa_code = capa.friendly_code.presence || capa.title
    if document_count.to_i > 1
      title = I18n.t(
        "user_notifications.capa_evidence_attached_auditor_count_title",
        default: "Evidence added to CAPA %{capa_code}: %{count} documents",
        capa_code: capa_code,
        count: document_count
      )
    else
      title = I18n.t(
        "user_notifications.capa_evidence_attached_auditor_title",
        default: "Evidence added to CAPA %{capa_code}: %{document_name}",
        capa_code: capa_code,
        document_name: document_name.presence || I18n.t("user_notifications.document", default: "a document")
      )
    end

    link_path = if capa_action.present?
      Rails.application.routes.url_helpers.dashboard_capa_action_show_path(capa.id, capa_action.id)
    else
      Rails.application.routes.url_helpers.dashboard_capa_management_show_path(capa.id)
    end

    recipients.find_each do |recipient|
      notification = Notification.create!(
        recipient: recipient,
        kind: "capa_evidence_attached_auditor",
        title: title,
        link_path: link_path,
        source: capa,
        payload: {
          actor_name: actor.name,
          actor_id: actor.id,
          capa_id: capa.id,
          capa_action_id: capa_action&.id,
          capa_title: capa.title,
          capa_friendly_code: capa.friendly_code,
          document_name: document_name,
          document_count: document_count
        }
      )
      send_notification_email_if_enabled(notification)
    end
  end

  # Notify a user they were assigned to a tool clause attribute (subcheckpoint).
  # @param recipient [User] the assigned user
  # @param assignment [AssessmentUser]
  # @param actor [User] company admin who assigned
  def self.notify_tool_assigned(recipient:, assignment:, actor:)
    return if recipient.blank? || assignment.blank? || actor.blank?

    tool = assignment.tool_clause&.tool
    tool_name = tool&.name || "Tool"
    title = I18n.t(
      "user_notifications.tool_assigned_title",
      actor_name: actor.name,
      tool_name: tool_name
    )
    clause = assignment.assessment&.tool_clause&.clause
    link_path = clause ? Rails.application.routes.url_helpers.clause_assessment_path(clause) : "/"

    notification = Notification.create!(
      recipient: recipient,
      kind: "tool_assigned",
      title: title,
      link_path: link_path,
      source: assignment,
      payload: {
        actor_name: actor.name,
        actor_id: actor.id,
        tool_id: tool&.id,
        tool_name: tool_name,
        assessment_id: assignment.assessment_id
      }
    )
    send_notification_email_if_enabled(notification)
  end

  # Notify a user they were unassigned from a tool clause attribute.
  # @param recipient [User] the unassigned user
  # @param tool [Tool]
  # @param actor [User] company admin who unassigned
  def self.notify_tool_unassigned(recipient:, tool:, actor:)
    return if recipient.blank? || actor.blank?

    tool_name = tool&.name || "Tool"
    title = I18n.t(
      "user_notifications.tool_unassigned_title",
      actor_name: actor.name,
      tool_name: tool_name
    )
    link_path = tool.present? ? Rails.application.routes.url_helpers.tool_path(tool) : nil

    notification = Notification.create!(
      recipient: recipient,
      kind: "tool_unassigned",
      title: title,
      link_path: link_path,
      source: tool,
      payload: {
        actor_name: actor.name,
        actor_id: actor.id,
        tool_id: tool&.id,
        tool_name: tool_name
      }
    )
    send_notification_email_if_enabled(notification)
  end

  # Notify users linked to the assessment + company admin about an evaluation.
  # @param assessment [Assessment] the assessment that was evaluated
  # @param actor [User] who performed the evaluation
  # @param evaluation_status [String] e.g. "approved", "rejected"
  # @param evaluator_role [String] e.g. "quality_manager", "auditor"
  def self.notify_assignment_evaluated(assessment:, actor:, evaluation_status:, evaluator_role:)
    return if assessment.blank? || actor.blank?

    company = assessment.company
    return unless company

    linked_user_ids = assessment.assessment_users.pluck(:user_id).uniq
    company_admin_ids = CompanyUser.where(company_id: company.id, role: "company_admin").pluck(:user_id).uniq

    recipient_ids = (linked_user_ids + company_admin_ids).uniq - [ actor.id ]
    return if recipient_ids.empty?

    tool_name = assessment.tool_clause&.tool&.name || "Tool"
    status_label = case evaluation_status
    when "rejected" then I18n.t("user_notifications.evaluation_rejected", default: "rejected")
    when "auditor_reviewed" then I18n.t("user_notifications.evaluation_auditor_reviewed", default: "auditor reviewed")
    else I18n.t("user_notifications.evaluation_approved", default: "approved")
    end

    title = I18n.t(
      "user_notifications.assignment_evaluated_title",
      actor_name: actor.name,
      tool_name: tool_name,
      status: status_label
    )
    clause = assessment.tool_clause&.clause
    link_path = clause ? Rails.application.routes.url_helpers.clause_assessment_path(clause) : "/"

    User.where(id: recipient_ids).find_each do |recipient|
      notification = Notification.create!(
        recipient: recipient,
        kind: "assignment_evaluated",
        title: title,
        link_path: link_path,
        source: assessment,
        payload: {
          actor_name: actor.name,
          actor_id: actor.id,
          assessment_id: assessment.id,
          tool_name: tool_name,
          evaluation_status: evaluation_status,
          evaluator_role: evaluator_role
        }
      )
      send_notification_email_if_enabled(notification)
    end
  end

  # Email is sent by Notification itself after commit (see Notification#deliver_email).
  def self.send_notification_email_if_enabled(_notification)
    nil
  end
end
