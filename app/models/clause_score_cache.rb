class ClauseScoreCache < ApplicationRecord
  skip_activity_trail
  belongs_to :clause
  belongs_to :company

  validates :clause_id, uniqueness: { scope: :company_id }

  # Find or initialize cache for a clause and company
  def self.for_clause_and_company(clause, company)
    find_or_initialize_by(clause_id: clause.id, company_id: company.id)
  end

  # Check if cache is valid (exists and was recently updated)
  def cached?
    cached_at.present? && cached_score.present?
  end

  # Update cache with score data
  def update_cache(score:, percentage:, evaluated_count:, business_rule_violation: nil)
    update(
      cached_score: score,
      cached_percentage: percentage,
      cached_evaluated_count: evaluated_count,
      business_rule_violation: business_rule_violation,
      cached_at: Time.current
    )
  end

  # Clear the cache
  def clear!
    update(
      cached_score: nil,
      cached_percentage: nil,
      cached_evaluated_count: nil,
      business_rule_violation: nil,
      cached_at: nil
    )
  end
end
