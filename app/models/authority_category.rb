# A category of the executive matrix (فئات الصلاحيات). Seventeen in the source
# document, but each company defines its own.
class AuthorityCategory < ApplicationRecord
  belongs_to :company

  has_many :authorities, dependent: :nullify

  validates :name_en, length: { maximum: 250 }
  validates :name_ar, length: { maximum: 250 }
  validate :must_have_a_name

  scope :ordered, -> { order(:sort_order, :name_en, :name_ar) }

  def display_name(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ name_ar, name_en ] : [ name_en, name_ar ]
    primary.presence || fallback.presence || code.to_s
  end

  private

  def must_have_a_name
    return if name_en.present? || name_ar.present?

    errors.add(:base, I18n.t("doa.errors.category_name_required"))
  end
end
