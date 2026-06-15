class CapaAuditLogPresenter
  def initialize(audit_log)
    @audit_log = audit_log
  end

  def description
    generate_description
  end

  def formatted_date
    @audit_log.created_at.strftime("%B %d, %Y")
  end

  def formatted_time
    @audit_log.created_at.strftime("%I:%M %p")
  end

  def formatted_datetime
    @audit_log.created_at.strftime("%B %d, %Y at %I:%M %p")
  end

  # Delegate other methods to the audit_log
  def method_missing(method, *args, &block)
    @audit_log.public_send(method, *args, &block)
  end

  def respond_to_missing?(method, include_private = false)
    @audit_log.respond_to?(method, include_private) || super
  end

  private

  def generate_description
    payload_data = @audit_log.payload_json || {}

    case @audit_log.action
    when 'CREATE_CAPA'
      title = payload_data['title'] || I18n.t("capa_management")
      I18n.t("capa_management_activity.create_capa", title: title)
    when 'UPDATE_CAPA'
      build_update_description(payload_data)
    when 'DELETE_CAPA'
      title = payload_data['title'] || I18n.t("capa_management")
      I18n.t("capa_management_activity.delete_capa", title: title)
    when 'UPDATE_CAPA_STATUS'
      old_status = format_status(payload_data['old_status'])
      new_status = format_status(payload_data['new_status'])
      I18n.t("capa_management_activity.status_changed", old: old_status, new: new_status)
    when 'ARCHIVE_CAPA'
      title = payload_data['title'] || I18n.t("capa_management")
      I18n.t("capa_management_activity.archive_capa", title: title)
    when 'UNARCHIVE_CAPA'
      title = payload_data['title'] || I18n.t("capa_management")
      I18n.t("capa_management_activity.unarchive_capa", title: title)
    when 'CREATE_CAPA_ACTION'
      action_type_label = format_action_type(payload_data['action_type'])
      action_title = payload_data['action_title'] || I18n.t("capa_management_activity.na")
      I18n.t("capa_management_activity.action_created", type: action_type_label, title: action_title)
    when 'UPDATE_CAPA_ACTION'
      action_type_label = format_action_type(payload_data['action_type'])
      action_title = payload_data['action_title'] || I18n.t("capa_management_activity.na")
      I18n.t("capa_management_activity.action_updated", type: action_type_label, title: action_title)
    when 'DELETE_CAPA_ACTION'
      action_type_label = format_action_type(payload_data['action_type'])
      action_title = payload_data['action_title'] || I18n.t("capa_management_activity.na")
      I18n.t("capa_management_activity.action_deleted", type: action_type_label, title: action_title)
    when 'LINK_CLAUSE_TO_CAPA'
      clause_display = build_clause_display(payload_data)
      I18n.t("capa_management_activity.clause_linked", clause: clause_display)
    when 'UNLINK_CLAUSE_FROM_CAPA'
      clause_display = build_clause_display(payload_data)
      I18n.t("capa_management_activity.clause_unlinked", clause: clause_display)
    when 'LINK_DOCUMENT_TO_CAPA'
      filename = payload_data['display_name'] || payload_data['filename'] || I18n.t("capa_management_activity.na")
      I18n.t("capa_management_activity.document_linked", filename: filename)
    when 'UNLINK_DOCUMENT_FROM_CAPA'
      filename = payload_data['display_name'] || payload_data['filename'] || I18n.t("capa_management_activity.na")
      I18n.t("capa_management_activity.document_unlinked", filename: filename)
    when 'GENERATE_CAPA_ACTIONS'
      count = payload_data['actions_count'] || 0
      I18n.t("capa_management_activity.actions_generated", count: count)
    when 'GENERATE_CAPA_QUESTIONNAIRE'
      manual = payload_data['manual']
      if manual
        I18n.t("capa_management_activity.questionnaire_created_manual")
      else
        I18n.t("capa_management_activity.questionnaire_generated_ai")
      end
    when 'UPDATE_CAPA_QUESTIONNAIRE'
      step = payload_data['step']
      updated_fields = payload_data['updated_fields'] || []
      if step == 'regenerate_root_cause'
        I18n.t("capa_management_activity.root_cause_regenerated")
      elsif updated_fields.include?('root_cause')
        question_answer_fields = ['question_1', 'question_2', 'question_3', 'question_4', 'question_5',
                                  'answer_1', 'answer_2', 'answer_3', 'answer_4', 'answer_5']
        has_question_answer_changes = updated_fields.any? { |field| question_answer_fields.include?(field) }
        if has_question_answer_changes
          I18n.t("capa_management_activity.questionnaire_edited")
        else
          I18n.t("capa_management_activity.root_cause_edited")
        end
      else
        I18n.t("capa_management_activity.questionnaire_edited")
      end
    when 'ASSIGN_USER_TO_CAPA'
      user_name = payload_data['user_name'] || I18n.t("capa_management_activity.na")
      I18n.t("capa_management_activity.assign_user", user: user_name)
    when 'UNASSIGN_USER_FROM_CAPA'
      user_name = payload_data['user_name'] || I18n.t("capa_management_activity.na")
      I18n.t("capa_management_activity.unassign_user", user: user_name)
    when 'ASSIGN_USER_TO_CAPA_ACTION'
      user_name = payload_data['user_name'] || I18n.t("capa_management_activity.na")
      action_title = payload_data['action_title'] || I18n.t("capa_management_activity.na")
      I18n.t("capa_management_activity.assign_user_to_action", user: user_name, action_title: action_title)
    when 'UNASSIGN_USER_FROM_CAPA_ACTION'
      user_name = payload_data['user_name'] || I18n.t("capa_management_activity.na")
      action_title = payload_data['action_title'] || I18n.t("capa_management_activity.na")
      I18n.t("capa_management_activity.unassign_user_from_action", user: user_name, action_title: action_title)
    else
      @audit_log.action.humanize
    end
  end

  def build_update_description(payload_data)
    changes = payload_data['changes'] || {}
    change_descriptions = []

    if changes['status']
      old_status = format_status(changes['status'][0])
      new_status = format_status(changes['status'][1])
      change_descriptions << I18n.t("capa_management_activity.status_changed", old: old_status, new: new_status)
    end

    change_descriptions << I18n.t("capa_management_activity.title_updated") if changes['title']
    change_descriptions << I18n.t("capa_management_activity.description_updated") if changes['description']

    if changes['priority']
      old_priority = format_priority(changes['priority'][0])
      new_priority = format_priority(changes['priority'][1])
      change_descriptions << I18n.t("capa_management_activity.priority_changed", old: old_priority, new: new_priority)
    end

    if changes['due_date']
      if changes['due_date'][0].nil?
        change_descriptions << I18n.t("capa_management_activity.due_date_set", new: format_date(changes['due_date'][1]))
      elsif changes['due_date'][1].nil?
        change_descriptions << I18n.t("capa_management_activity.due_date_removed")
      else
        change_descriptions << I18n.t(
          "capa_management_activity.due_date_changed",
          old: format_date(changes['due_date'][0]),
          new: format_date(changes['due_date'][1])
        )
      end
    end

    change_descriptions << I18n.t("capa_management_activity.standard_updated") if changes['standard_id']

    if changes['source']
      old_source = format_source(changes['source'][0])
      new_source = format_source(changes['source'][1])
      change_descriptions << I18n.t("capa_management_activity.source_changed", old: old_source, new: new_source)
    end

    if changes['archived']
      if changes['archived'][1] == true
        change_descriptions << I18n.t("capa_management_activity.archive_capa", title: payload_data['title'] || I18n.t("capa_management"))
      else
        change_descriptions << I18n.t("capa_management_activity.unarchive_capa", title: payload_data['title'] || I18n.t("capa_management"))
      end
    end

    if change_descriptions.any?
      if change_descriptions.one?
        I18n.t("capa_management_activity.update_capa_single", change: change_descriptions.first)
      else
        I18n.t("capa_management_activity.update_capa_multiple", changes: change_descriptions.join(', '))
      end
    else
      I18n.t("capa_management_activity.update_capa")
    end
  end

  def format_status(status)
    return I18n.t("capa_management_activity.na") if status.nil?
    key = status.to_s
    I18n.t("capa_management_ui.statuses.#{key}", default: status.to_s.humanize)
  end

  def format_priority(priority)
    return I18n.t("capa_management_activity.na") if priority.nil?
    key = priority.to_s
    I18n.t("capa_management_ui.header.priority_labels.#{key}", default: priority.to_s.humanize)
  end

  def format_date(date)
    return I18n.t("capa_management_activity.na") if date.nil?
    date.is_a?(Date) ? date.strftime("%d. %b. %Y") : Date.parse(date.to_s).strftime("%d. %b. %Y")
  rescue
    date.to_s
  end

  def format_source(source)
    return I18n.t("capa_management_activity.na") if source.nil?

    key = source.to_s
    I18n.t("capa_sources.#{key}", default: key.humanize)
  end

  def format_action_type(action_type)
    key = action_type.to_s
    if key == 'corrective'
      I18n.t("capa_actions.types.corrective", default: key.humanize)
    elsif key == 'preventive'
      I18n.t("capa_actions.types.preventive", default: key.humanize)
    else
      key.humanize
    end
  end

  def build_clause_display(payload_data)
    clause_title = payload_data['clause_title'] || payload_data['clause_code'] || I18n.t("capa_management_activity.na")
    clause_code = payload_data['clause_code']
    clause_code.present? ? "#{clause_code} #{clause_title}".strip : clause_title
  end
end

