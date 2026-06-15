class BusinessRuleValidator
  def initialize(tool, terminal_clause, score_result, company = nil)
    @tool = tool
    @terminal_clause = terminal_clause
    @score_result = score_result
    @company = company
    @tool_clause = ToolClause.find_by(clause_id: terminal_clause.id, tool_id: tool.id)
  end

  def valid?
    violation_message.nil?
  end

  def violation_message
    return nil unless @tool.business_rules.present?

    rules = @tool.business_rules["rules"] || []
    return nil if rules.empty?

    rules.each do |rule|
      violation = validate_rule_with_message(rule)
      return violation if violation.present?
    end

    nil
  end

  private

  def validate_rule_with_message(rule)
    case rule["type"]
    when "average_cannot_exceed_attribute"
      validate_average_cannot_exceed_attribute(rule)
    else
      nil
    end
  end

  def validate_average_cannot_exceed_attribute(rule)
    return nil unless rule["target_subcheckpoint_id"].present?
    return nil unless @tool_clause

    target_subcheckpoint_id = rule["target_subcheckpoint_id"].to_i
    target_subcheckpoint = ToolSubcheckpoint.find_by(id: target_subcheckpoint_id)
    return nil unless target_subcheckpoint

    # Find the assessment for this clause + company
    assessment = Assessment.find_by(tool_clause_id: @tool_clause.id, company_id: @company&.id)
    return nil unless assessment && %w[approved auditor_approved].include?(assessment.status)

    # Find the score for the target subcheckpoint
    score_record = assessment.assessment_scores.find_by(tool_subcheckpoint_id: target_subcheckpoint_id)
    return nil unless score_record&.percentage_score.present?

    target_percentage = score_record.percentage_score
    average_percentage = @score_result[:percentage]

    if average_percentage > target_percentage
      target_checkpoint = target_subcheckpoint.tool_checkpoint
      "Average score (#{average_percentage.round(1)}%) cannot exceed #{target_checkpoint.name} - #{target_subcheckpoint.name} (#{target_percentage.round(1)}%)"
    else
      nil
    end
  end
end
