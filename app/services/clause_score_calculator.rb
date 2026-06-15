class ClauseScoreCalculator
  def initialize(tool_clause)
    @tool_clause = tool_clause
    @clause = tool_clause.clause
  end

  # Calculate the score for a terminal clause using weighted-sum + cap formula.
  #
  # Formula:
  #   weighted_sum = SUM(attribute_score[i] * weight[i])
  #   cap_value    = MIN(attribute_score[j]) for all j where is_cap = true
  #   overall      = MIN(weighted_sum, cap_value)
  #   final_score  = allocated_points * (overall / 100)
  #
  # Weight fallback: if ALL weights are null, equal weighting (1/N) is used.
  # Unscored attributes contribute 0 to the weighted sum.
  def calculate_score(company = nil)
    allocated_points = @clause.calculated_points || 0
    tool = @tool_clause.tool
    subcheckpoints = tool.all_subcheckpoints
    total_subcheckpoints = subcheckpoints.count

    if subcheckpoints.empty?
      return {
        score: 0, percentage: 0, weighted_sum: 0,
        allocated_points: allocated_points,
        evaluated_count: 0, total_count: 0,
        details: "No scoring attributes configured",
        cap_applied: false, cap_value: nil, cap_attribute: nil,
        business_rule_violation: nil
      }
    end

    # Load scores from AssessmentScore via the Assessment for this clause + company.
    # Only approved assessments with scores contribute to the calculation.
    scores = {}
    if company.present?
      assessment = Assessment.find_by(tool_clause_id: @tool_clause.id, company_id: company.id)
      if assessment && assessment.status == "approved"
        scores = assessment.assessment_scores.index_by(&:tool_subcheckpoint_id)
      end
    end

    # Get effective weights (handles null → equal fallback)
    weights = tool.effective_weights
    cap_ids = tool.cap_subcheckpoint_ids

    # Build per-attribute scores
    weighted_sum = 0.0
    cap_values = []
    evaluated_count = 0

    subcheckpoints.each do |sub|
      score_record = scores[sub.id]
      score_value = extract_score(score_record, sub)

      if score_record&.percentage_score.present? || (sub.scoring_type == "Number" && score_record&.score.present?)
        evaluated_count += 1
      end

      w = weights[sub.id] || 0.0
      weighted_sum += score_value * w

      if cap_ids.include?(sub.id)
        cap_values << score_value
      end
    end

    # Apply cap
    cap_applied = false
    cap_attribute = nil
    cap_value = nil

    if cap_values.any?
      min_cap = cap_values.min
      if weighted_sum > min_cap
        cap_applied = true
        cap_value = min_cap
        cap_sub = subcheckpoints.select { |s| cap_ids.include?(s.id) }
                                .min_by { |s| extract_score(scores[s.id], s) }
        cap_attribute = cap_sub&.name
      end
    end

    overall_percentage = cap_applied ? [ weighted_sum, cap_value ].min : weighted_sum
    final_score = allocated_points * (overall_percentage / 100.0)

    violation_msg = if cap_applied
      "Score capped by #{cap_attribute} attribute at #{cap_value.round(1)}%"
    end

    details = "#{evaluated_count}/#{total_subcheckpoints} attributes scored"

    result = {
      score: final_score.round(2),
      percentage: overall_percentage.round(2),
      weighted_sum: weighted_sum.round(2),
      allocated_points: allocated_points,
      evaluated_count: evaluated_count,
      total_count: total_subcheckpoints,
      details: details,
      cap_applied: cap_applied,
      cap_value: cap_value&.round(2),
      cap_attribute: cap_attribute,
      business_rule_violation: violation_msg
    }

    # Validate existing business rules if company is present
    if company.present?
      validator = BusinessRuleValidator.new(tool, @clause, result, company)
      if (violation = validator.violation_message)
        result[:business_rule_violation] = violation
      end
    end

    result
  end

  # Calculate score for ANY clause (parent or terminal) for a given tool.
  #
  # `context` (optional) is a preloaded bundle built by `build_standard_context`
  # that lets the recursion read clause/tool-clause/cache/subcheckpoint-count
  # data from in-memory maps instead of issuing one query per clause. Callers
  # outside the standard-compliance path can omit it and the method falls back
  # to lazy lookups.
  def self.calculate_for_clause(clause, tool, company = nil, context: nil)
    return nil unless clause.present? && tool.present?

    is_leaf = clause_leaf?(clause, context)

    if company.present?
      cache = lookup_cache(clause, company, context)
      if cache&.cached?
        if is_leaf
          allocated_points = clause.calculated_points || 0
          real_total_count = subcheckpoint_count_for(clause, tool, context, cache)
        else
          # For non-leaf, allocated_points and total_count must be summed from terminal
          # descendants linked to this tool.
          allocated_points = 0
          real_total_count = 0
          terminals_under(clause, context).each do |tc|
            tc_tool_clause = lookup_tool_clause(tc, tool, context)
            next unless tc_tool_clause
            allocated_points += tc.calculated_points || 0
            real_total_count += subcheckpoint_count_for(tc, tool, context, cache)
          end
        end
        return {
          clause_id: clause.id, clause_code: clause.code,
          allocated_points: allocated_points,
          score: cache.cached_score, percentage: cache.cached_percentage || 0,
          evaluated_count: cache.cached_evaluated_count || 0,
          total_count: real_total_count, is_terminal: is_leaf,
          details: "Cached score", business_rule_violation: cache.business_rule_violation
        }
      end
    end

    if is_leaf
      tool_clause = lookup_tool_clause(clause, tool, context)
      return nil unless tool_clause

      calculator = new(tool_clause)
      result = calculator.calculate_score(company)

      return {
        clause_id: clause.id, clause_code: clause.code,
        allocated_points: result[:allocated_points],
        score: result[:score], percentage: result[:percentage],
        evaluated_count: result[:evaluated_count], total_count: result[:total_count],
        is_terminal: true, details: result[:details],
        business_rule_violation: result[:business_rule_violation]
      }
    end

    terminal_clauses = terminals_under(clause, context)
    total_scored = 0
    total_allocated = 0
    evaluated_count = 0
    total_count = 0

    terminal_clauses.each do |terminal_clause|
      tool_clause = lookup_tool_clause(terminal_clause, tool, context)
      next unless tool_clause

      total_allocated += terminal_clause.calculated_points || 0
      total_count += subcheckpoint_count_for(terminal_clause, tool, context, nil)

      if company.present?
        cache = lookup_cache(terminal_clause, company, context)
        if cache&.cached?
          if cache.business_rule_violation.blank?
            total_scored += cache.cached_score || 0
            evaluated_count += cache.cached_evaluated_count || 0
          end
          next
        end
      end

      calculator = new(tool_clause)
      result = calculator.calculate_score(company)
      if result[:business_rule_violation].blank?
        total_scored += result[:score]
        evaluated_count += result[:evaluated_count]
      end
    end

    percentage = total_allocated > 0 ? ((total_scored / total_allocated) * 100).round(2) : 0

    {
      clause_id: clause.id, clause_code: clause.code,
      allocated_points: total_allocated,
      score: total_scored.round(2), percentage: percentage,
      evaluated_count: evaluated_count, total_count: total_count,
      is_terminal: false, terminal_count: terminal_clauses.count,
      details: "#{evaluated_count}/#{total_count} subcheckpoints evaluated across #{terminal_clauses.count} terminal clauses"
    }
  end

  def self.calculate_for_top_level_clause(top_level_clause, tool, company = nil)
    calculate_for_clause(top_level_clause, tool, company)
  end

  # Preloads per-(version, tool, company) lookups so the recursion avoids N+1.
  def self.build_standard_context(version, tool, company)
    all_clauses = Clause.where(standard_version_id: version.id).order(:sort_order).to_a
    clause_ids = all_clauses.map(&:id)

    {
      all_clauses: all_clauses,
      children_by_parent_id: all_clauses.group_by(&:parent_id),
      tool_clauses_by_clause_id: ToolClause.where(tool_id: tool.id, clause_id: clause_ids).index_by(&:clause_id),
      caches_by_clause_id: company ? ClauseScoreCache.where(clause_id: clause_ids, company_id: company.id).index_by(&:clause_id) : {},
      subcheckpoint_count: tool.all_subcheckpoints.size
    }
  end

  # Aggregate compliance for a company on a standard without iterating per-tool.
  # Walks every terminal clause, reads its ClauseScoreCache for the company,
  # sums points. Tools are only the input mechanism for individual clause scores;
  # they are irrelevant to this aggregation.
  #
  # Returns:
  #   total_scored_points    — Σ cached_score across terminals (skipping rule violations)
  #   total_allocated_points — Σ allocated_points across terminals (always counts)
  #   compliance_percentage  — total_scored / total_allocated × 100
  def self.calculate_compliance_for_company(standard, company)
    return nil unless standard.present? && company.present?
    version = standard.latest_version
    return nil unless version

    all_clauses = Clause.where(standard_version_id: version.id).to_a
    return zero_compliance_result(standard, company) if all_clauses.empty?

    parent_ids = all_clauses.map(&:parent_id).compact.to_set
    terminals = all_clauses.reject { |c| parent_ids.include?(c.id) }
    return zero_compliance_result(standard, company) if terminals.empty?

    # Only terminals with a linked tool can ever be assessed; clauses without
    # one would otherwise inflate the denominator and depress compliance.
    assessable_clause_ids = ToolClause.where(clause_id: terminals.map(&:id)).pluck(:clause_id).to_set
    terminals = terminals.select { |t| assessable_clause_ids.include?(t.id) }
    return zero_compliance_result(standard, company) if terminals.empty?

    caches = ClauseScoreCache.where(
      clause_id: terminals.map(&:id),
      company_id: company.id
    ).index_by(&:clause_id)

    total_scored = 0.0
    total_allocated = 0.0
    evaluated_count = 0

    terminals.each do |terminal|
      total_allocated += terminal.allocated_points.to_f
      cache = caches[terminal.id]
      next unless cache&.cached?
      next if cache.business_rule_violation.present?
      total_scored += cache.cached_score.to_f
      evaluated_count += 1
    end

    percentage = total_allocated > 0 ? ((total_scored / total_allocated) * 100).round(2) : 0

    {
      standard_id: standard.id,
      company_id: company.id,
      total_scored_points: total_scored.round(2),
      total_allocated_points: total_allocated.round(2),
      compliance_percentage: percentage,
      evaluated_terminal_count: evaluated_count,
      total_terminal_count: terminals.size
    }
  end

  def self.zero_compliance_result(standard, company)
    {
      standard_id: standard.id,
      company_id: company.id,
      total_scored_points: 0.0,
      total_allocated_points: 0.0,
      compliance_percentage: 0,
      evaluated_terminal_count: 0,
      total_terminal_count: 0
    }
  end

  def self.calculate_standard_compliance(standard, tool, company = nil)
    version = standard.latest_version
    return nil unless version

    context = build_standard_context(version, tool, company)
    root_clauses = context[:children_by_parent_id][nil] || []
    total_scored = 0
    total_allocated = 0
    clause_results = []

    root_clauses.each do |root_clause|
      result = calculate_for_clause(root_clause, tool, company, context: context)
      next unless result
      total_scored += result[:score]
      total_allocated += result[:allocated_points]
      clause_results << result
    end

    overall_percentage = total_allocated > 0 ? ((total_scored / total_allocated) * 100).round(2) : 0

    {
      standard_id: standard.id, standard_name: standard.display_name,
      tool_id: tool.id, tool_name: tool.name,
      total_allocated_points: total_allocated,
      total_scored_points: total_scored.round(2),
      compliance_percentage: overall_percentage,
      clause_results: clause_results, company_id: company&.id
    }
  end

  private

  # Extract the normalized 0-100 score from an AssessmentScore based on scoring type
  def extract_score(score_record, subcheckpoint)
    return 0.0 unless score_record

    case subcheckpoint.scoring_type
    when "Percentage"
      score_record.percentage_score&.to_f || 0.0
    when "Number"
      min = subcheckpoint.min_score&.to_f || 0.0
      max = subcheckpoint.max_score&.to_f || 100.0
      raw = score_record.score&.to_f || 0.0
      range = max - min
      range > 0 ? ((raw - min) / range * 100.0) : 0.0
    when "Multiple Choice"
      score_record.percentage_score&.to_f || 0.0
    else
      0.0
    end
  end

  def self.get_all_terminal_clauses(clause)
    if clause.leaf?
      [ clause ]
    else
      clause.children.flat_map { |child| get_all_terminal_clauses(child) }
    end
  end

  # Helpers that read from `context` when available, else fall back to the
  # per-clause lookups the original code used.

  def self.clause_leaf?(clause, context)
    return clause.leaf? unless context
    (context[:children_by_parent_id][clause.id] || []).empty?
  end

  def self.terminals_under(clause, context)
    return get_all_terminal_clauses(clause) unless context
    children = context[:children_by_parent_id][clause.id] || []
    return [clause] if children.empty?
    children.flat_map { |child| terminals_under(child, context) }
  end

  def self.lookup_tool_clause(clause, tool, context)
    if context
      context[:tool_clauses_by_clause_id][clause.id]
    else
      ToolClause.find_by(clause_id: clause.id, tool_id: tool.id)
    end
  end

  def self.lookup_cache(clause, company, context)
    if context
      context[:caches_by_clause_id][clause.id]
    else
      ClauseScoreCache.find_by(clause_id: clause.id, company_id: company.id)
    end
  end

  def self.subcheckpoint_count_for(_clause, tool, context, cache_fallback)
    return context[:subcheckpoint_count] if context
    count = tool.checkpoints.includes(:subcheckpoints).flat_map(&:subcheckpoints).count
    count.zero? ? (cache_fallback&.cached_evaluated_count || 0) : count
  end
end
