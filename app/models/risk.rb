class Risk < ApplicationRecord
  include GovernanceCapaLinkable

  belongs_to :company
  belongs_to :owner, class_name: "CompanyUser", optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :riskable, polymorphic: true, optional: true
  belongs_to :risk_workspace, optional: true
  belongs_to :closed_by, class_name: "User", optional: true

  enum :status, {
    identified: "identified",
    assessing: "assessing",
    mitigating: "mitigating",
    monitoring: "monitoring",
    closed: "closed"
  }, default: "identified"

  validates :title, presence: true
  validates :likelihood, :impact, presence: true, inclusion: { in: 1..5 }
  validates :residual_likelihood, :residual_impact, inclusion: { in: 1..5 }, allow_nil: true

  # Closing a risk is a governance decision, so it must carry a justification.
  # Risks closed before this requirement existed keep a null reason and are only
  # asked for one when their closure is next changed.
  validates :closure_reason, presence: true, if: :closure_reason_required?

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  before_save :calculate_scores
  before_save :stamp_closure
  after_create :log_creation
  after_update :log_update

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def risk_level(score)
    case score
    when 1..4 then "low"
    when 5..10 then "medium"
    when 11..15 then "high"
    else "critical"
    end
  end

  def inherent_level
    risk_level(inherent_score)
  end

  def residual_level
    residual_score.present? ? risk_level(residual_score) : nil
  end

  private

  # Only a closure being made or changed now needs a reason; a risk closed
  # before the column existed is left alone until someone touches its status.
  def closure_reason_required?
    closed? && (new_record? || status_changed? || closure_reason_changed?)
  end

  # Records who closed the risk and when, and clears both if it is reopened.
  def stamp_closure
    return unless status_changed?

    if closed?
      self.closed_at = Time.current
      self.closed_by ||= Thread.current[:current_user]
    else
      self.closed_at = nil
      self.closed_by = nil
      self.closure_reason = nil
    end
  end

  def calculate_scores
    self.inherent_score = RiskScoringService.calculate(likelihood: likelihood, impact: impact)

    if residual_likelihood.present? && residual_impact.present?
      self.residual_score = RiskScoringService.calculate(likelihood: residual_likelihood, impact: residual_impact)
    end
  end

  def log_creation
    performed_by = Thread.current[:current_user]
    return unless performed_by

    AuditLogService.log_action(
      actor_user: performed_by,
      company: company,
      action: "CREATE_RISK",
      entity_type: "risk",
      entity_id: id,
      payload: { title: title, status: status, inherent_score: inherent_score }
    )
  end

  def log_update
    performed_by = Thread.current[:current_user]
    return unless performed_by

    changes_to_track = {}
    changes_to_track["status"] = saved_change_to_status if saved_change_to_status?
    changes_to_track["likelihood"] = saved_change_to_likelihood if saved_change_to_likelihood?
    changes_to_track["impact"] = saved_change_to_impact if saved_change_to_impact?
    changes_to_track["residual_score"] = saved_change_to_residual_score if saved_change_to_residual_score?
    changes_to_track["owner_id"] = saved_change_to_owner_id if saved_change_to_owner_id?

    return if changes_to_track.empty?

    AuditLogService.log_action(
      actor_user: performed_by,
      company: company,
      action: "UPDATE_RISK",
      entity_type: "risk",
      entity_id: id,
      payload: { changes: changes_to_track }
    )
  end
end
