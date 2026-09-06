class OrgGroup < ApplicationRecord
  belongs_to :company
  has_many :org_units, dependent: :nullify

  validates :color, presence: true, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }
  validates :name_en, length: { maximum: 150 }
  validates :name_ar, length: { maximum: 150 }
  validate :must_have_a_name

  scope :ordered, -> { order(:sort_order, :created_at) }

  def display_name(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ name_ar, name_en ] : [ name_en, name_ar ]
    primary.presence || fallback.presence || ""
  end

  private

  def must_have_a_name
    return if name_en.to_s.strip.present? || name_ar.to_s.strip.present?

    errors.add(:base, I18n.t("org_structure.errors.group_name_required"))
  end
end
