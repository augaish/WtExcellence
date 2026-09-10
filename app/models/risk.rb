class Risk < ApplicationRecord
  include GovernanceCapaLinkable
  include GovernanceActivity

  has_many :evidence_attachments, as: :attachable, dependent: :destroy
  has_many :uploads, through: :evidence_attachments

  tracks_governance_activity entity: "risk",
    tracks: %i[status likelihood impact residual_score owner_id closure_reason treatment_strategy next_review_on accepted_at],
    summary: %i[title status inherent_score]

  belongs_to :company
  belongs_to :owner, class_name: "CompanyUser", optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :riskable, polymorphic: true, optional: true
  belongs_to :risk_workspace, optional: true
  belongs_to :closed_by, class_name: "User", optional: true
  belongs_to :control_owner, class_name: "CompanyUser", optional: true
  belongs_to :accepted_by, class_name: "User", optional: true

  # What is done about the risk. Accepting it is a decision with an owner and
  # an expiry, recorded separately below.
  TREATMENT_STRATEGIES = %w[avoid reduce transfer accept].freeze

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
  validates :treatment_strategy, inclusion: { in: TREATMENT_STRATEGIES }, allow_blank: true
  validates :cause, :event, :impact_statement, :treatment_plan, :control_rationale, :acceptance_rationale, length: { maximum: 5000 }
  # A residual score is an opinion until it says which controls justify it.
  validate :residual_needs_control_rationale

  # Closing a risk is a governance decision, so it must carry a justification.
  # Risks closed before this requirement existed keep a null reason and are only
  # asked for one when their closure is next changed.
  validates :closure_reason, presence: true, if: :closure_reason_required?

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :review_overdue, ->(on = Date.current) { where(next_review_on: ...on).where.not(status: "closed") }
  scope :accepted, -> { where.not(accepted_at: nil) }

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

  # Cause → event → impact, the way a risk should be stated so two readers
  # understand the same thing.
  def statement(locale = I18n.locale)
    return nil if cause.blank? && event.blank? && impact_statement.blank?

    I18n.t("risk_depth.statement", cause: cause.presence || "…", event: event.presence || "…", impact: impact_statement.presence || "…", locale: locale)
  end

  def treatment_label(locale = I18n.locale)
    treatment_strategy.present? ? I18n.t("risk_depth.treatments.#{treatment_strategy}", locale: locale) : nil
  end

  def review_overdue?(on = Date.current)
    next_review_on.present? && next_review_on < on && !closed?
  end

  # Accepted exposure: a named person, a reason, and an expiry after which the
  # acceptance no longer stands.
  def accepted?(on = Date.current)
    accepted_at.present? && (acceptance_expires_on.nil? || acceptance_expires_on >= on)
  end

  def acceptance_expired?(on = Date.current)
    accepted_at.present? && acceptance_expires_on.present? && acceptance_expires_on < on
  end

  # Above appetite and nobody has accepted it (or the acceptance has lapsed):
  # the exception a leader must see.
  def needs_acceptance?(on = Date.current)
    above_appetite? && !closed? && !accepted?(on)
  end

  def accept!(by:, rationale:, expires_on:)
    raise ArgumentError, I18n.t("risk_depth.errors.acceptance_reason_required") if rationale.to_s.strip.blank?
    raise ArgumentError, I18n.t("risk_depth.errors.acceptance_expiry_required") if expires_on.blank?

    update!(accepted_by: by, accepted_at: Time.current, acceptance_rationale: rationale.strip, acceptance_expires_on: expires_on,
      treatment_strategy: treatment_strategy.presence || "accept")
  end

  # Above the threshold the company has approved. No appetite set means nothing
  # is reported as exceeding it — silence is better than an invented threshold.
  def above_appetite?
    appetite = company&.risk_appetite_score
    return false if appetite.blank? || current_score.blank?

    current_score > appetite
  end

  private

  def residual_needs_control_rationale
    return if residual_likelihood.blank? && residual_impact.blank?
    return if control_rationale.to_s.strip.present?

    errors.add(:control_rationale, I18n.t("risk_depth.errors.control_rationale_required"))
  end

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
