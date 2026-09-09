# frozen_string_literal: true

class Notification < ApplicationRecord
  KINDS = %w[
    capa_assigned capa_unassigned capa_action_assigned capa_action_unassigned capa_evidence_attached
    capa_evidence_attached_auditor tool_assigned tool_unassigned assignment_evaluated
    delegation_expiring
    record_task_assigned record_task_submitted record_approval_requested record_approval_rejected record_published
    authority_review_requested
  ].freeze

  belongs_to :recipient, class_name: "User"
  belongs_to :source, polymorphic: true, optional: true

  validates :kind, presence: true, inclusion: { in: KINDS }

  scope :for_user, ->(user) { where(recipient_id: user.id) }
  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: read_at.presence || Time.current)
  end

  # Returns the notification title in the given locale (for emails and display).
  def title_in_locale(locale)
    p = (payload || {}).stringify_keys
    capa_code = p["capa_friendly_code"].presence || p["capa_title"]

    I18n.with_locale(locale) do
      case kind
      when "capa_assigned", "capa_unassigned"
        I18n.t("user_notifications.#{kind}_title", actor_name: p["actor_name"], capa_code: capa_code)
      when "capa_action_assigned"
        I18n.t("user_notifications.capa_action_assigned_title", actor_name: p["actor_name"], capa_code: capa_code, action_title: p["capa_action_title"].presence || "")
      when "capa_action_unassigned"
        I18n.t("user_notifications.capa_action_unassigned_title", actor_name: p["actor_name"], capa_code: capa_code, action_title: p["capa_action_title"].presence || "")
      when "capa_evidence_attached", "capa_evidence_attached_auditor"
        key_prefix = kind == "capa_evidence_attached_auditor" ? "capa_evidence_attached_auditor" : "capa_evidence_attached"
        if p["document_count"].to_i > 1
          I18n.t("user_notifications.#{key_prefix}_count_title", actor_name: p["actor_name"], capa_code: capa_code, count: p["document_count"])
        else
          doc_name = p["document_name"].presence || I18n.t("user_notifications.document", default: "a document")
          I18n.t("user_notifications.#{key_prefix}_title", actor_name: p["actor_name"], capa_code: capa_code, document_name: doc_name)
        end
      when "tool_assigned", "tool_unassigned"
        I18n.t("user_notifications.#{kind}_title", actor_name: p["actor_name"], tool_name: p["tool_name"].presence || "Tool")
      when "assignment_evaluated"
        status =
          case p["evaluation_status"]
          when "approved"
            I18n.t("user_notifications.evaluation_approved", default: "approved")
          when "rejected"
            I18n.t("user_notifications.evaluation_rejected", default: "rejected")
          when "auditor_reviewed"
            I18n.t("user_notifications.evaluation_auditor_reviewed", default: "auditor reviewed")
          else
            p["evaluation_status"].to_s
          end
      
        I18n.t(
          "user_notifications.assignment_evaluated_title",
          actor_name: p["actor_name"],
          tool_name: p["tool_name"].presence || "Tool",
          status: status
        )      
      else
        title
      end
    end
  rescue I18n::MissingTranslationData, KeyError, ArgumentError
    title
  end
end
