# One cell of an authority matrix: a holder, at one AuthorityLevel, for one
# decision.
#
# `condition` holds what the source documents smuggle into asterisked footnotes
# ("بحسب نوع الطلب", "في حال كان بحث ابتكاري"). A qualifier on an authority is a
# business rule, so it is stored as data rather than as typography.
class PpAuthorityAssignment < ApplicationRecord
  belongs_to :pp_process_authority, class_name: "PpProcessAuthority"
  belongs_to :org_unit, optional: true

  validates :level, presence: true, inclusion: { in: AuthorityLevel::KEYS }
  validates :holder_title, length: { maximum: 250 }
  validates :condition, length: { maximum: 300 }
  validate :must_name_a_holder

  scope :ordered, -> { order(:sort_order, :created_at) }
  scope :at_level, ->(level) { where(level: level) }

  def level_label(locale = I18n.locale)
    AuthorityLevel.label(level, locale)
  end

  # Identifies the holder across rows, so the same person named as a job title
  # in two places is recognised as one holder when checking segregation.
  def holder_key
    org_unit_id.presence || holder_title.to_s.strip.downcase.presence
  end

  def holder_label(locale = I18n.locale)
    holder_title.presence || org_unit&.display_name(locale) || ""
  end

  private

  def must_name_a_holder
    return if holder_title.present? || org_unit_id.present?

    errors.add(:holder_title, I18n.t("process_authorities.errors.holder_required"))
  end
end
