module AiInsightsHelper
  def format_ai_activity_description(activity)
    payload = activity.payload_json || {}
    
    # Check if this is root cause regeneration
    if activity.action == "UPDATE_CAPA_QUESTIONNAIRE" && payload['step'] == "regenerate_root_cause"
      return I18n.t("capa_management_activity.root_cause_regenerated_ai")
    end
    
    case activity.action
    when 'GENERATE_CAPA_ACTIONS'
      count = payload['actions_count'] || 0
      I18n.t("capa_management_activity.actions_generated", count: count)
    when 'GENERATE_CAPA_QUESTIONNAIRE'
      I18n.t("capa_management_activity.questionnaire_generated_ai")
    when 'SUGGEST_CAPA_CLAUSES'
      count = payload['suggestions_count'] || 0
      I18n.t("capa_management_activity.clause_suggested", count: count)
    else
      activity.action.humanize
    end
  end

  def ai_activity_credits_used(activity)
    return 0 unless activity

    payload = activity.payload_json || {}
    if activity.action == "UPDATE_CAPA_QUESTIONNAIRE" && payload['step'] == "regenerate_root_cause"
      0
    else
      payload['credits_used'] || CreditService.get_cost(activity.action)
    end
  end
end

