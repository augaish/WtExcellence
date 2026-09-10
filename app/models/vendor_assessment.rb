# One dated assessment of a vendor: five criteria scored 1 to 5, the rating
# those scores give, the assessor's rationale, the evidence behind it, and a
# reviewer's sign-off. The vendor's rating follows the latest signed-off
# assessment; an unsigned one is a draft opinion.
class VendorAssessment < ApplicationRecord
  CRITERIA = %w[data_sensitivity service_dependency financial_stability compliance continuity].freeze
  SCALE = (1..5).freeze

  belongs_to :vendor
  belongs_to :company
  belongs_to :assessed_by, class_name: "User", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  has_many :evidence_attachments, as: :attachable, dependent: :destroy
  has_many :uploads, through: :evidence_attachments

  validates :assessed_on, presence: true
  validates :rating, inclusion: { in: Vendor.risk_levels.keys - [ "unassessed" ] }
  validates :rationale, presence: true, length: { maximum: 5000 }
  validate :every_criterion_scored

  before_validation :assign_version, on: :create
  before_validation :derive_rating

  scope :ordered, -> { order(version: :desc) }
  scope :signed_off, -> { where.not(reviewed_at: nil) }

  def score(criterion)
    scores[criterion.to_s].to_i
  end

  def average
    values = CRITERIA.map { |c| score(c) }.reject(&:zero?)
    return 0 if values.empty?

    (values.sum.to_f / values.size).round(2)
  end

  def signed_off?
    reviewed_at.present?
  end

  # The reviewer's sign-off is what makes the rating the vendor's.
  def sign_off!(by:, note: nil)
    transaction do
      update!(reviewed_by: by, reviewed_at: Time.current, review_note: note.presence)
      vendor.update!(risk_level: rating, rating_source: "assessed", rating_override_reason: nil,
        next_review_on: next_review_on || vendor.next_review_on)
    end
  end

  # 1–5 averaged: up to 2.4 low, up to 3.4 medium, up to 4.4 high, above critical.
  def self.rating_for(average)
    case average
    when 0...2.5 then "low"
    when 2.5...3.5 then "medium"
    when 3.5...4.5 then "high"
    else "critical"
    end
  end

  private

  def assign_version
    self.version = (vendor&.assessments&.maximum(:version) || 0) + 1 if version.blank? || version == 1
  end

  def derive_rating
    self.rating = self.class.rating_for(average) if CRITERIA.all? { |c| SCALE.cover?(score(c)) }
  end

  def every_criterion_scored
    CRITERIA.each do |criterion|
      next if SCALE.cover?(score(criterion))

      errors.add(:base, I18n.t("vendor_assessment.errors.score_required", criterion: I18n.t("vendor_assessment.criteria.#{criterion}")))
    end
  end
end
