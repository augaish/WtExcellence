# One field of a form record: what the person filling the form writes here,
# and how. A table field lists its columns; a choice field lists its options.
class PpFormField < ApplicationRecord
  TYPES = %w[text textarea number date checkbox choice table signature].freeze

  belongs_to :pp_record, class_name: "PpRecord"

  validates :field_type, inclusion: { in: TYPES }
  validates :label_en, :label_ar, length: { maximum: 250 }
  validates :hint, length: { maximum: 500 }
  validate :must_have_a_label

  scope :ordered, -> { order(:position, :created_at) }

  before_validation :assign_position, on: :create

  def label(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ label_ar, label_en ] : [ label_en, label_ar ]
    primary.presence || fallback.presence || ""
  end

  def type_label(locale = I18n.locale)
    I18n.t("form_fields.types.#{field_type}", locale: locale)
  end

  # "Yes | No | Not applicable" as written in the editor.
  def option_list
    options.to_s.split("|").map(&:strip).compact_blank
  end

  def column_list
    columns.to_s.split("|").map(&:strip).compact_blank
  end

  def table?
    field_type == "table"
  end

  private

  def assign_position
    return if position_changed? && position.to_i.positive?

    self.position = PpFormField.where(pp_record_id: pp_record_id).maximum(:position).to_i + 1
  end

  def must_have_a_label
    return if label_en.present? || label_ar.present?

    errors.add(:base, I18n.t("form_fields.errors.label_required"))
  end
end
