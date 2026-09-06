class OrgLevelDefinition < ApplicationRecord
  MAX_LEVEL = 6

  belongs_to :company

  validates :level, presence: true,
    numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_LEVEL }
  validates :level, uniqueness: { scope: :company_id }
  validates :name_en, length: { maximum: 100 }
  validates :name_ar, length: { maximum: 100 }
  validate :must_have_a_name

  scope :ordered, -> { order(:level) }

  def display_name(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ name_ar, name_en ] : [ name_en, name_ar ]
    primary.presence || fallback.presence || "#{I18n.t('org_structure.level')} #{level}"
  end

  private

  def must_have_a_name
    return if name_en.to_s.strip.present? || name_ar.to_s.strip.present?

    errors.add(:base, I18n.t("org_structure.errors.level_name_required"))
  end
end
