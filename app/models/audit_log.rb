class AuditLog < ApplicationRecord
  belongs_to :actor_user, class_name: "User", optional: true
  belongs_to :company

  validates :action, presence: true
  validates :company_id, presence: true

  scope :by_actor, ->(user) { where(actor_user_id: user.id) }
  scope :by_company, ->(company) { where(company_id: company.id) }
  scope :by_action, ->(action) { where(action: action) }
  scope :by_entity, ->(entity_type, entity_id) { where(entity_type: entity_type, entity_id: entity_id) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_capa, ->(capa) { where(entity_type: "capa", entity_id: capa.id) }
  scope :for_capa_with_actions, ->(capa) do
    capa_action_ids = CapaAction.where(capa_id: capa.id).select(:id)
    where(
      "(entity_type = 'capa' AND entity_id = ?) OR (entity_type = 'capa_action' AND entity_id IN (?)) OR (entity_type = 'clause' AND action IN (?, ?) AND payload_json->>'capa_id' = ?)",
      capa.id,
      capa_action_ids,
      "LINK_CLAUSE_TO_CAPA",
      "UNLINK_CLAUSE_FROM_CAPA",
      capa.id.to_s
    )
  end

  def formatted_date
    I18n.l(created_at, format: :medium)
  end

  def formatted_time
    I18n.l(created_at, format: :time)
  end

  def formatted_datetime
    I18n.l(created_at, format: :long)
  end

  def description
    case entity_type
    when "capa", "capa_action"
      CapaAuditLogPresenter.new(self).description
    when "clause"
      # Delegate to presenter for CAPA-related clause actions
      if [ "LINK_CLAUSE_TO_CAPA", "UNLINK_CLAUSE_FROM_CAPA" ].include?(action)
        CapaAuditLogPresenter.new(self).description
      else
        # Fallback for other clause actions
        action.humanize
      end
    when "tool_clause_subcheckpoint_assignment", "assessment"
      assignment_description
    when "tool"
      tool_description
    when "company"
      company_description
    when "user"
      user_description
    else
      # Fallback for other entity types
      action.humanize
    end
  end

  private

  def assignment_description
    payload_data = payload_json || {}
    base = "audit_log.assignment"

    case action
    when "UPDATE_ASSIGNMENT_CONTENT"
      if payload_data["summary_length"].present?
        count = payload_data["summary_length"].to_i
        char_count = I18n.t("#{base}.char_count", count: count)
        I18n.t("#{base}.UPDATE_ASSIGNMENT_CONTENT_with_chars", char_count: char_count)
      else
        I18n.t("#{base}.UPDATE_ASSIGNMENT_CONTENT")
      end
    when "EVALUATE_ASSIGNMENT"
      eval_status = payload_data["evaluation_status"]
      score = payload_data["percentage_score"]
      role_key = payload_data["evaluator_role"].to_s.presence
      role = role_key ? I18n.t("audit_log.evaluator_roles.#{role_key}", default: role_key.humanize) : nil
      score_value = score.present? ? score.to_f.round(1) : nil

      if eval_status == "approved"
        if score_value && role
          I18n.t("#{base}.EVALUATE_ASSIGNMENT_approved", score: score_value, role: role)
        elsif score_value
          I18n.t("#{base}.EVALUATE_ASSIGNMENT_approved_no_role", score: score_value)
        elsif role
          I18n.t("#{base}.EVALUATE_ASSIGNMENT_approved_no_score", role: role)
        else
          I18n.t("#{base}.EVALUATE_ASSIGNMENT_approved_simple")
        end
      elsif eval_status == "rejected"
        if score_value && role
          I18n.t("#{base}.EVALUATE_ASSIGNMENT_rejected", score: score_value, role: role)
        elsif score_value
          I18n.t("#{base}.EVALUATE_ASSIGNMENT_rejected_no_role", score: score_value)
        elsif role
          I18n.t("#{base}.EVALUATE_ASSIGNMENT_rejected_no_score", role: role)
        else
          I18n.t("#{base}.EVALUATE_ASSIGNMENT_rejected_simple")
        end
      elsif eval_status == "auditor_reviewed"
        I18n.t("#{base}.EVALUATE_ASSIGNMENT_auditor_reviewed")
      end
    when "LINK_DOCUMENTS_TO_ASSIGNMENT"
      doc_count = (payload_data["document_count"] || 0).to_i
      doc_count_str = I18n.t("#{base}.doc_count", count: doc_count)
      names = payload_data["document_names"]
      if names.present? && names.length <= 3
        I18n.t("#{base}.LINK_DOCUMENTS_TO_ASSIGNMENT_with_names", doc_count: doc_count_str, names: names.join(", "))
      elsif names.present?
        more_count = doc_count - 2
        I18n.t("#{base}.LINK_DOCUMENTS_TO_ASSIGNMENT_with_names_more", doc_count: doc_count_str, names: names.first(2).join(", "), more_count: more_count)
      else
        I18n.t("#{base}.LINK_DOCUMENTS_TO_ASSIGNMENT", doc_count: doc_count_str)
      end
    when "UNLINK_DOCUMENT_FROM_ASSIGNMENT"
      if payload_data["upload_name"].present?
        I18n.t("#{base}.UNLINK_DOCUMENT_FROM_ASSIGNMENT_with_name", name: payload_data["upload_name"])
      else
        I18n.t("#{base}.UNLINK_DOCUMENT_FROM_ASSIGNMENT")
      end
    when "ASSESSMENT_SAVE_DRAFT"
      summaries = payload_data["summaries"]
      if summaries.is_a?(Hash) && summaries.any?
        parts = summaries.map do |checkpoint, attrs|
          entries = attrs.map { |attr, val| "#{attr}: \"#{val}\"" }.join(", ")
          "#{checkpoint} — #{entries}"
        end
        I18n.t("audit_log_assessment.save_draft_content", clause_code: payload_data["clause_code"], content: parts.join("; "))
      else
        I18n.t("audit_log_assessment.save_draft", clause_code: payload_data["clause_code"])
      end
    when "ASSESSMENT_SUBMIT_FOR_REVIEW"
      I18n.t("audit_log_assessment.submit_for_review", clause_code: payload_data["clause_code"])
    when "ASSESSMENT_APPROVED"
      if payload_data["feedback"].present?
        I18n.t("audit_log_assessment.approved_with_feedback", clause_code: payload_data["clause_code"], feedback: payload_data["feedback"].truncate(100))
      else
        I18n.t("audit_log_assessment.approved", clause_code: payload_data["clause_code"])
      end
    when "ASSESSMENT_REJECTED"
      if payload_data["feedback"].present?
        I18n.t("audit_log_assessment.rejected_with_feedback", clause_code: payload_data["clause_code"], feedback: payload_data["feedback"].truncate(100))
      else
        I18n.t("audit_log_assessment.rejected", clause_code: payload_data["clause_code"])
      end
    when "ASSESSMENT_REOPENED"
      if payload_data["feedback"].present?
        I18n.t("audit_log_assessment.reopened_with_feedback", clause_code: payload_data["clause_code"], feedback: payload_data["feedback"].truncate(100))
      else
        I18n.t("audit_log_assessment.reopened", clause_code: payload_data["clause_code"])
      end
    when "ASSESSMENT_COMMENT"
      if payload_data["feedback"].present?
        I18n.t("audit_log_assessment.comment_with_feedback", clause_code: payload_data["clause_code"], feedback: payload_data["feedback"].truncate(100))
      else
        I18n.t("audit_log_assessment.comment", clause_code: payload_data["clause_code"])
      end
    when "ASSIGN_AUDITOR_TO_ASSESSMENT"
      I18n.t("audit_log_assessment.auditor_assigned", auditor_name: payload_data["auditor_name"], clause_code: payload_data["clause_code"])
    else
      action.humanize
    end
  end

  def tool_description
    base = "audit_log.tool"
    payload_data = payload_json || {}

    case action
    when "CREATE_TOOL"
      tool_name = payload_data["tool_name"] || I18n.t("#{base}.default_tool")
      I18n.t("#{base}.CREATE_TOOL", tool_name: tool_name)
    when "UPDATE_TOOL"
      tool_name = payload_data["tool_name"] || I18n.t("#{base}.default_tool")
      changes = payload_data["changes"] || {}
      change_keys = []

      change_keys << I18n.t("#{base}.change_name") if changes["name"]
      change_keys << I18n.t("#{base}.change_description") if changes["description"]
      change_keys << I18n.t("#{base}.change_business_rules") if changes["business_rules"]

      if change_keys.any?
        if change_keys.one?
          I18n.t("#{base}.UPDATE_TOOL_single", tool_name: tool_name, change: change_keys.first)
        else
          I18n.t("#{base}.UPDATE_TOOL_multiple", tool_name: tool_name, changes: change_keys.join(", "))
        end
      else
        I18n.t("#{base}.UPDATE_TOOL", tool_name: tool_name)
      end
    when "DELETE_TOOL"
      tool_name = payload_data["tool_name"] || I18n.t("#{base}.default_tool")
      I18n.t("#{base}.DELETE_TOOL", tool_name: tool_name)
    when "LINK_STANDARD_TO_TOOL"
      tool_name = payload_data["tool_name"] || I18n.t("#{base}.default_tool")
      standard_name = payload_data["standard_name"] || payload_data["standard_code"] || I18n.t("#{base}.default_standard")
      clauses_count = (payload_data["clauses_linked"] || 0).to_i
      clauses_str = I18n.t("#{base}.clauses_count", count: clauses_count)
      I18n.t("#{base}.LINK_STANDARD_TO_TOOL", tool_name: tool_name, standard_name: standard_name, clauses: clauses_str)
    when "UNLINK_STANDARD_FROM_TOOL"
      tool_name = payload_data["tool_name"] || I18n.t("#{base}.default_tool")
      standard_name = payload_data["standard_name"] || payload_data["standard_code"] || I18n.t("#{base}.default_standard")
      clauses_count = (payload_data["clauses_unlinked"] || 0).to_i
      clauses_str = I18n.t("#{base}.clauses_count", count: clauses_count)
      msg = I18n.t("#{base}.UNLINK_STANDARD_FROM_TOOL", tool_name: tool_name, standard_name: standard_name, clauses: clauses_str)
      if payload_data["standard_removed"]
        msg + " " + I18n.t("#{base}.standard_removed")
      else
        msg
      end
    when "ASSIGN_USER_TO_TOOL_SUBCHECKPOINT"
      tool_name = payload_data["tool_name"] || I18n.t("#{base}.default_tool")
      user_name = payload_data["user_name"] || I18n.t("#{base}.default_user")
      I18n.t("#{base}.ASSIGN_USER_TO_TOOL_SUBCHECKPOINT", user_name: user_name, tool_name: tool_name)
    when "ASSIGN_AUDITOR_TO_TOOL_SUBCHECKPOINT"
      tool_name = payload_data["tool_name"] || I18n.t("#{base}.default_tool")
      user_name = payload_data["user_name"] || I18n.t("#{base}.default_user")
      I18n.t("#{base}.ASSIGN_AUDITOR_TO_TOOL_SUBCHECKPOINT", user_name: user_name, tool_name: tool_name)
    when "UNASSIGN_USER_FROM_TOOL_SUBCHECKPOINT"
      tool_name = payload_data["tool_name"] || I18n.t("#{base}.default_tool")
      user_name = payload_data["user_name"] || I18n.t("#{base}.default_user")
      I18n.t("#{base}.UNASSIGN_USER_FROM_TOOL_SUBCHECKPOINT", user_name: user_name, tool_name: tool_name)
    else
      action.humanize
    end
  end

  def company_description
    base = "audit_log.company"
    payload_data = payload_json || {}

    case action
    when "CREATE_COMPANY"
      company_name = payload_data["company_name"] || I18n.t("#{base}.default_company")
      I18n.t("#{base}.CREATE_COMPANY", company_name: company_name)
    when "DELETE_COMPANY"
      company_name = payload_data["company_name"] || I18n.t("#{base}.default_company")
      I18n.t("#{base}.DELETE_COMPANY", company_name: company_name)
    when "UPDATE_COMPANY_LICENSE_SEATS"
      company_name = payload_data["company_name"] || I18n.t("#{base}.default_company")
      old_seats = payload_data["old_license_seats"]
      new_seats = payload_data["new_license_seats"]
      I18n.t("#{base}.UPDATE_COMPANY_LICENSE_SEATS", company_name: company_name, old_seats: old_seats, new_seats: new_seats)
    else
      action.humanize
    end
  end

  def user_description
    base = "audit_log.user"
    payload_data = payload_json || {}

    case action
    when "ACTIVATE_USER"
      user_name = payload_data["user_name"] || I18n.t("#{base}.default_user")
      I18n.t("#{base}.ACTIVATE_USER", user_name: user_name)
    when "DEACTIVATE_USER"
      user_name = payload_data["user_name"] || I18n.t("#{base}.default_user")
      I18n.t("#{base}.DEACTIVATE_USER", user_name: user_name)
    when "UPDATE_USER_PERMISSIONS"
      user_name = payload_data["user_name"] || I18n.t("#{base}.default_user")
      previous_permissions = payload_data["previous_permissions"] || []
      new_permissions = payload_data["new_permissions"] || []
      added = new_permissions - previous_permissions
      removed = previous_permissions - new_permissions

      changes = []
      changes << I18n.t("#{base}.permissions_added", list: added.join(", ")) if added.any?
      changes << I18n.t("#{base}.permissions_removed", list: removed.join(", ")) if removed.any?

      if changes.any?
        I18n.t("#{base}.UPDATE_USER_PERMISSIONS_with_changes", user_name: user_name, changes: changes.join("; "))
      else
        I18n.t("#{base}.UPDATE_USER_PERMISSIONS", user_name: user_name)
      end
    when "CREATE_USER_INVITATION"
      user_name = payload_data["user_name"] || I18n.t("#{base}.default_user")
      role = payload_data["role"] || I18n.t("#{base}.default_role")
      company_name = payload_data["company_name"]
      if company_name.present?
        I18n.t("#{base}.CREATE_USER_INVITATION_with_company", user_name: user_name, role: role, company_name: company_name)
      else
        I18n.t("#{base}.CREATE_USER_INVITATION", user_name: user_name, role: role)
      end
    when "UPDATE_USER_NAME"
      user_name = payload_data["new_name"] || I18n.t("#{base}.default_user")
      old_name = payload_data["old_name"]
      if old_name.present?
        I18n.t("#{base}.UPDATE_USER_NAME_from", old_name: old_name, user_name: user_name)
      else
        I18n.t("#{base}.UPDATE_USER_NAME", user_name: user_name)
      end
    when "ACCEPT_USER_INVITATION"
      user_name = payload_data["user_name"] || I18n.t("#{base}.default_user")
      I18n.t("#{base}.ACCEPT_USER_INVITATION", user_name: user_name)
    when "USER_LOGIN"
      user_name = payload_data["user_name"] || I18n.t("#{base}.default_user")
      I18n.t("#{base}.USER_LOGIN", user_name: user_name)
    else
      action.humanize
    end
  end
end
