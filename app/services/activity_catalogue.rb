# Which module each logged entity belongs to, so the Activity page can be
# filtered by module and each entry can name its record type. An entity type
# not listed here still shows, under "Other".
class ActivityCatalogue
  MODULES = {
    "organization" => %w[org_unit org_group org_level_definition company_holiday],
    "quality" => %w[standard standard_version clause company_standard company_clause_instance assessment assessment_score
                    assessment_user assignment_evaluation tool tool_clause tool_checkpoint tool_subcheckpoint checklist_item
                    company_checklist_item_instance evidence_attachment],
    "capa" => %w[capa capa_action capa_action_assignment capa_assignment capa_clause questionnaire comment],
    "pp" => %w[pp_process pp_record pp_record_clause pp_process_step pp_process_authority pp_authority_assignment
               pp_record_link pp_record_participant pp_record_reference pp_record_term pp_service_level sla_measurement
               pp_package pp_diagram pp_diagram_element pp_diagram_flow pp_clause_comment pp_stage_approval
               pp_stage_assignee pp_stage_task pp_stage_transition glossary_term],
    "authorities" => %w[authority authority_category authority_band authority_assignment authority_delegation
                        authority_matrix_review authority_review_comment],
    "governance" => %w[risk risk_workspace vendor vendor_assessment customer_commitment],
    "library" => %w[upload folder],
    "account" => %w[user company_user company company_module ai_instruction]
  }.freeze

  VERBS = %w[CREATE UPDATE DELETE].freeze

  def self.module_for(entity_type)
    MODULES.find { |_, types| types.include?(entity_type.to_s) }&.first || "other"
  end

  def self.entity_types_for(module_key)
    MODULES.fetch(module_key.to_s, [])
  end

  # "CREATE_PP_RECORD" -> ["create", "pp_record"]; other actions have no verb.
  def self.split_action(action)
    verb, rest = action.to_s.split("_", 2)
    return [ nil, nil ] unless VERBS.include?(verb) && rest.present?

    [ verb.downcase, rest.downcase ]
  end
end
