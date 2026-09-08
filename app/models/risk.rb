class Risk < ApplicationRecord
  include GovernanceCapaLinkable
  include GovernanceActivity

  has_many :evidence_attachments, as: :attachable, dependent: :destroy
  has_many :uploads, through: :evidence_attachments

  tracks_governance_activity entity: "risk",
    tracks: %i[status likelihood impact residual_score owner_id closure_reason],
    summary: %i[title status inherent_score]

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
  validates :target_likelihood, :target_impact, inclusion: { in: 1..5 }, allow_nil: true

  # Closing a risk is a governance decision, so it must carry a justification.
  # Risks closed before this requirement existed keep a null reason and are only
  # asked for one when their closure is next changed.
  validates :closure_reason, presence: true, if: :closure_reason_required?

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  before_save :calculate_scores
  before_save :stamp_closure

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

  # What the company is carrying today. Residual only counts once there is a
  # residual assessment behind it; until then the inherent score is the honest
  # answer, because nothing has been shown to reduce it.
  def current_score
    residual_score.presence || inherent_score
  end

  # A target is an intention, not an achievement. It is never treated as the
  # current exposure, which is the confusion the review warned about.
  def target_met?
    target_score.present? && current_score.present? && current_score <= target_score
  end

  # Above the threshold the company has approved. No appetite set means nothing
  # is reported as exceeding it — silence is better than an invented threshold.
  def above_appetite?
    appetite = company&.risk_appetite_score
    return false if appetite.blank? || current_score.blank?

    current_score > appetite
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

    if target_likelihood.present? && target_impact.present?
      self.target_score = RiskScoringService.calculate(likelihood: target_likelihood, impact: target_impact)
    end
  end


end
