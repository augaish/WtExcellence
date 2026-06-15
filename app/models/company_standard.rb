class CompanyStandard < ApplicationRecord
  # Validations
  validates :company_id, presence: true
  validates :standard_id, presence: true
  validates :status, presence: true, inclusion: { in: %w[active inactive archived] }
  validates :active_version_id, presence: true
  validates :company_id, uniqueness: { scope: :standard_id }

  # Associations
  belongs_to :company
  belongs_to :standard
  belongs_to :active_version, class_name: "StandardVersion", foreign_key: "active_version_id"
  belongs_to :assigned_by_user, class_name: "User", foreign_key: "assigned_by", optional: true

  has_many :company_standard_version_history, dependent: :destroy
  has_many :company_clause_instances, dependent: :destroy

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :inactive, -> { where(status: "inactive") }
  scope :archived, -> { where(status: "archived") }

  # Instance methods
  def active?
    status == "active"
  end

  def inactive?
    status == "inactive"
  end

  def archived?
    status == "archived"
  end

  # Record version change in history
  def change_version(new_version_id, changed_by_user_id, reason = nil)
    CompanyStandardVersionHistory.create!(
      company_standard: self,
      from_version_id: active_version_id,
      to_version_id: new_version_id,
      changed_by: changed_by_user_id,
      reason: reason
    )

    update!(active_version_id: new_version_id)
  end

  # Compliance cache ----------------------------------------------------------

  # Returns the cached compliance percentage, computing and persisting it on a miss.
  def compliance_percentage
    return cached_compliance_percentage.to_f if cached_compliance_percentage.present?
    refresh_compliance_cache!
    cached_compliance_percentage.to_f
  end

  def total_scored_points
    refresh_compliance_cache! if cached_total_scored_points.nil?
    cached_total_scored_points.to_f
  end

  def total_allocated_points
    refresh_compliance_cache! if cached_total_allocated_points.nil?
    cached_total_allocated_points.to_f
  end

  # Recompute compliance from scratch and persist it. Walks every terminal clause
  # of the standard, reads each ClauseScoreCache for this company, sums points.
  # Tools are no longer in the formula — they are only the input mechanism.
  # Safe to call from the score propagator after a clause score changes.
  def refresh_compliance_cache!
    result = ClauseScoreCalculator.calculate_compliance_for_company(standard, company)
    if result.nil?
      update_columns(
        cached_total_scored_points: 0,
        cached_total_allocated_points: 0,
        cached_compliance_percentage: 0,
        cached_compliance_at: Time.current
      )
      return
    end

    update_columns(
      cached_total_scored_points: result[:total_scored_points],
      cached_total_allocated_points: result[:total_allocated_points],
      cached_compliance_percentage: result[:compliance_percentage],
      cached_compliance_at: Time.current
    )
  end
end
