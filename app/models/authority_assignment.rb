# One cell of the executive matrix: a holder, at one AuthorityLevel, for one
# band of one authority.
#
# A holder is an org unit where one can be named, or a dynamic role where the
# source document says "الوكيل المعني" — the concerned deputy. Naming the rule
# rather than the post is what makes such a cell resolvable at audit time.
class AuthorityAssignment < ApplicationRecord
  belongs_to :authority_band
  belongs_to :org_unit, optional: true

  has_one :authority, through: :authority_band

  validates :level, presence: true, inclusion: { in: AuthorityLevel::KEYS }
  validates :dynamic_role, inclusion: { in: DynamicRole::KEYS }, allow_blank: true
  validates :holder_title, length: { maximum: 250 }
  validates :condition, length: { maximum: 300 }
  validate :must_name_a_holder
  validate :unit_must_be_same_company

  scope :ordered, -> { order(:sort_order, :created_at) }
  scope :at_level, ->(level) { where(level: level) }
  scope :dynamic, -> { where.not(dynamic_role: nil) }

  def level_label(locale = I18n.locale)
    AuthorityLevel.label(level, locale)
  end

  def holder_label(locale = I18n.locale)
    return org_unit.display_name(locale) if org_unit
    return DynamicRole.label(dynamic_role, locale) if dynamic_role.present?

    holder_title.to_s
  end

  # Identifies the holder across rows, so one unit named in several cells is
  # recognised as a single holder when checking segregation of duties.
  def holder_key
    org_unit_id.presence || dynamic_role.presence || holder_title.to_s.strip.downcase.presence
  end

  # A dynamic holder is only as good as the org structure it resolves against.
  def resolve(subject_unit)
    return org_unit if org_unit
    return DynamicRole.resolve(dynamic_role, subject_unit) if dynamic_role.present?

    nil
  end

  private

  def must_name_a_holder
    return if org_unit_id.present? || dynamic_role.present? || holder_title.present?

    errors.add(:base, I18n.t("doa.errors.holder_required"))
  end

  def unit_must_be_same_company
    return if org_unit.nil? || authority_band.nil?

    authority = authority_band.authority
    return if authority.nil? || org_unit.company_id == authority.company_id

    errors.add(:org_unit, I18n.t("doa.errors.other_company"))
  end
end
