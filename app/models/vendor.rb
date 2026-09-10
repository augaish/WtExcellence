class Vendor < ApplicationRecord
  include GovernanceCapaLinkable
  include GovernanceActivity

  has_many :evidence_attachments, as: :attachable, dependent: :destroy
  has_many :uploads, through: :evidence_attachments

  tracks_governance_activity entity: "vendor",
    tracks: %i[name risk_level owner_id contact_email criticality approval_status rating_source],
    summary: %i[name risk_level]

  belongs_to :company
  belongs_to :owner, class_name: "CompanyUser", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  enum :risk_level, {
    unassessed: "unassessed",
    low: "low",
    medium: "medium",
    high: "high",
    critical: "critical"
  }, default: "unassessed"

  # How much the business depends on the supplier: chosen by the owner, not
  # derived, because it is a fact about the business and not about the supplier.
  CRITICALITIES = %w[low medium high critical].freeze

  # Whether procurement may use the supplier. A low risk rating never means
  # approved; approval is its own decision, recorded with who took it.
  APPROVAL_STATUSES = %w[not_approved conditionally_approved approved suspended].freeze

  RATING_SOURCES = %w[manual assessed].freeze

  has_many :assessments, -> { ordered }, class_name: "VendorAssessment", dependent: :destroy
  belongs_to :approved_by, class_name: "User", optional: true

  validates :name, presence: true
  validates :criticality, inclusion: { in: CRITICALITIES }, allow_blank: true
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
  validates :rating_source, inclusion: { in: RATING_SOURCES }
  validates :rating_override_reason, length: { maximum: 2000 }
  validates :approval_note, length: { maximum: 2000 }
  validate :manual_rating_needs_a_reason

  scope :review_overdue, ->(on = Date.current) { where(next_review_on: ...on) }

  def latest_assessment
    assessments.signed_off.first
  end

  def assessed?
    rating_source == "assessed" && latest_assessment.present?
  end

  def review_overdue?(on = Date.current)
    next_review_on.present? && next_review_on < on
  end

  def approved?
    approval_status.in?(%w[approved conditionally_approved])
  end

  def criticality_label(locale = I18n.locale)
    criticality.present? ? I18n.t("vendor_assessment.criticalities.#{criticality}", locale: locale) : nil
  end

  def approval_label(locale = I18n.locale)
    I18n.t("vendor_assessment.approval_statuses.#{approval_status}", locale: locale)
  end

  def record_approval!(status, by:, note: nil)
    update!(approval_status: status, approval_note: note.presence, approved_by: by, approved_at: Time.current)
  end

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  private

  # A rating typed by hand, rather than produced by a signed-off assessment,
  # must say why. The assessment path clears the reason itself.
  def manual_rating_needs_a_reason
    return unless risk_level_changed? && risk_level != "unassessed"
    return if rating_source == "assessed"
    return if rating_override_reason.to_s.strip.present?

    errors.add(:rating_override_reason, I18n.t("vendor_assessment.errors.override_reason_required"))
  end
end
