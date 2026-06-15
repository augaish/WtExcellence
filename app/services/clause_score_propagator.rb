class ClauseScorePropagator
  def self.propagate_from_terminal_clause(terminal_clause, company)
    return unless terminal_clause.leaf?
    return if terminal_clause.tool_clause.blank?
    return unless company.present? # CRITICAL: Ensure company is present

    # Note: we do NOT short-circuit on an existing cache here because we propagate on every
    # evaluation (unevaluated subcheckpoints count as 0%), so the cache must always be refreshed.

    tool = terminal_clause.tool_clause.tool
    calculator = ClauseScoreCalculator.new(terminal_clause.tool_clause)
    # CRITICAL: Always pass company to ensure calculations are company-specific
    result = calculator.calculate_score(company)

    # Propagate on any evaluation (unevaluated subcheckpoints are treated as 0% by the calculator).
    # Only skip if nothing has been evaluated yet.
    return if result[:evaluated_count] == 0

    validator = BusinessRuleValidator.new(tool, terminal_clause, result, company)
    violation_message = validator.violation_message

    if violation_message.present?
      ActiveRecord::Base.transaction do
        cache_record = ClauseScoreCache.find_or_initialize_by(
          clause_id: terminal_clause.id,
          company_id: company.id
        )
        cache_record.update!(
          cached_score: result[:score],
          cached_percentage: result[:percentage],
          cached_evaluated_count: result[:evaluated_count],
          business_rule_violation: violation_message,
          cached_at: Time.current
        )
      end
      return
    end

    ActiveRecord::Base.transaction do
      cache_record = ClauseScoreCache.find_or_initialize_by(
        clause_id: terminal_clause.id,
        company_id: company.id
      )
      cache_record.update!(
        cached_score: result[:score],
        cached_percentage: result[:percentage],
        cached_evaluated_count: result[:evaluated_count],
        business_rule_violation: nil,
        cached_at: Time.current
      )
    end

    propagate_upwards(terminal_clause, company, tool)
    refresh_standard_cache(terminal_clause, company)
  end

  # Refresh the cached_compliance_percentage on the matching company_standard
  # after clause scores change. Safe to call outside a transaction — upsert-style.
  def self.refresh_standard_cache(clause, company)
    return unless clause.present? && company.present?
    standard = clause.standard_version&.standard
    return unless standard

    company_standard = CompanyStandard.find_by(standard_id: standard.id, company_id: company.id)
    company_standard&.refresh_compliance_cache!
  end

  def self.propagate_upwards(clause, company, tool)
    return unless clause&.parent.present?
    return unless company.present? # CRITICAL: Ensure company is present

    parent = clause.parent

    ActiveRecord::Base.transaction do
      parent.lock!
      parent.reload

      # tool_clauses.clause_id is unique at the DB level — at most one tool per
      # terminal — so the only condition needed is "has a tool linked at all".
      children_with_tool = parent.children.select { |child| child.tool_clause.present? }

      return if children_with_tool.empty?

      # CRITICAL: Always filter caches by company_id to ensure we only check this company's scores
      locked_caches = children_with_tool.map do |child|
        ClauseScoreCache.where(clause_id: child.id, company_id: company.id).lock.first
      end

      # Propagate as soon as at least one child has been evaluated.
      # Children without a cache are treated as 0 score (handled by aggregate_scores_from_children).
      any_evaluated = locked_caches.any? { |cache| cache&.cached? && cache.business_rule_violation.blank? }
      return unless any_evaluated

      aggregated = aggregate_scores_from_children(children_with_tool, company, locked_caches)

      cache_record = ClauseScoreCache.find_or_initialize_by(
        clause_id: parent.id,
        company_id: company.id
      )
      cache_record.update!(
        cached_score: aggregated[:score],
        cached_percentage: aggregated[:percentage],
        cached_evaluated_count: aggregated[:evaluated_count],
        business_rule_violation: nil,
        cached_at: Time.current
      )
    end

    propagate_upwards(parent, company, tool)
  end

  def self.invalidate_cache(clause, company)
    return unless clause.present? && company.present?

    ActiveRecord::Base.transaction do
      clause.lock! if clause.persisted?

      cache = ClauseScoreCache.where(clause_id: clause.id, company_id: company.id).lock.first
      if cache
        cache.update!(
          cached_score: nil,
          cached_percentage: nil,
          cached_evaluated_count: nil,
          business_rule_violation: nil,
          cached_at: nil
        )
      end
    end

    invalidate_cache(clause.parent, company) if clause.parent.present?
  end

  # Invalidate clause score caches for all companies assigned to the standard when tool-clause
  # relationships or business rules change (e.g. tool updated by superadmin, clauses linked/unlinked).
  # This ensures company standard score (compliance) is recalculated on next read instead of showing stale cache.
  #
  # standard - Standard whose assigned companies should be invalidated
  # root_clauses - Array of root (top-level) Clause records whose trees should be invalidated
  def self.invalidate_cache_for_tool_clause_changes(standard, root_clauses)
    return if standard.blank? || root_clauses.blank?

    company_ids = standard.company_standards.where(status: "active").pluck(:company_id).uniq
    return if company_ids.empty?

    root_clauses = Array(root_clauses).compact
    return if root_clauses.empty?

    company_ids.each do |company_id|
      company = Company.find_by(id: company_id)
      next unless company

      root_clauses.each do |root_clause|
        terminal_clauses_under(root_clause).each do |terminal_clause|
          invalidate_cache(terminal_clause, company)
        end
      end
    end

    # Clear the company_standard compliance cache — next read will recompute.
    CompanyStandard.where(standard_id: standard.id, company_id: company_ids)
                   .update_all(cached_compliance_percentage: nil, cached_compliance_at: nil)
  end

  def self.terminal_clauses_under(clause)
    return [] unless clause.present?
    if clause.leaf?
      [clause]
    else
      clause.children.flat_map { |child| terminal_clauses_under(child) }
    end
  end

  private

  def self.aggregate_scores_from_children(children, company, locked_caches = nil)
    total_scored = 0
    total_allocated = 0
    total_evaluated_count = 0

    children.each_with_index do |child, index|
      cache = locked_caches ? locked_caches[index] : ClauseScoreCache.find_by(clause_id: child.id, company_id: company.id)

      # Always include the child's allocated points in the denominator so that
      # unevaluated siblings correctly dilute the parent score (treated as 0).
      total_allocated += child.calculated_points || 0

      if cache&.cached? && cache.business_rule_violation.blank?
        total_scored += cache.cached_score || 0
        total_evaluated_count += cache.cached_evaluated_count || 0
      end
      # If no valid cache: score contribution is 0 (already the default)
    end

    percentage = total_allocated > 0 ? ((total_scored / total_allocated) * 100).round(2) : 0

    {
      score: total_scored.round(2),
      percentage: percentage,
      evaluated_count: total_evaluated_count
    }
  end
end
