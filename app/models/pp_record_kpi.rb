# One key performance indicator of a procedure: what is measured, the target,
# its unit, how and how often it is measured.
class PpRecordKpi < ApplicationRecord
  FREQUENCIES = %w[monthly quarterly semiannual annual].freeze

  belongs_to :pp_record, class_name: "PpRecord"

  validates :name_en, :name_ar, length: { maximum: 250 }
  validates :target, length: { maximum: 100 }
  validates :unit, length: { maximum: 50 }
  validates :measurement_method, length: { maximum: 500 }
  validates :frequency, inclusion: { in: FREQUENCIES }, allow_blank: true
  validate :must_have_a_name

  scope :ordered, -> { order(:sort_order, :created_at) }

  before_validation(on: :create) { self.sort_order = PpRecordKpi.where(pp_record_id: pp_record_id).maximum(:sort_order).to_i + 1 if sort_order.to_i.zero? }

  def name(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ name_ar, name_en ] : [ name_en, name_ar ]
    primary.presence || fallback.presence || ""
  end

  def frequency_label(locale = I18n.locale)
    frequency.present? ? I18n.t("kpis.frequencies.#{frequency}", locale: locale) : nil
  end

  private

  def must_have_a_name
    return if name_en.present? || name_ar.present?

    errors.add(:base, I18n.t("kpis.errors.name_required"))
  end
end
