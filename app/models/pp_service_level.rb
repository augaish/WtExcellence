# One measurable commitment of a service level agreement.
#
# An SLA usually carries several — availability, response, resolution — each
# with its own target and its own way of being measured, so they are rows rather
# than columns on the agreement.
class PpServiceLevel < ApplicationRecord
  belongs_to :pp_record, class_name: "PpRecord"

  METRICS = %w[availability response_time resolution_time delivery_frequency accuracy other].freeze

  # Units that make sense per metric, so a page cannot offer "hours" for a
  # percentage target.
  UNITS_FOR_METRIC = {
    "availability" => %w[percent],
    "response_time" => %w[minutes hours days],
    "resolution_time" => %w[minutes hours days],
    "delivery_frequency" => %w[days weeks months],
    "accuracy" => %w[percent],
    "other" => %w[percent minutes hours days weeks months count]
  }.freeze

  validates :metric, inclusion: { in: METRICS }
  validates :service_name, length: { maximum: 250 }
  validates :coverage, length: { maximum: 250 }
  validates :target_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :unit_must_suit_the_metric
  validate :percentage_targets_stay_within_range

  scope :ordered, -> { order(:sort_order, :created_at) }

  def metric_label(locale = I18n.locale)
    I18n.t("sla.metrics.#{metric}", locale: locale)
  end

  def unit_label(locale = I18n.locale)
    return "" if target_unit.blank?

    I18n.t("sla.units.#{target_unit}", locale: locale, default: target_unit)
  end

  # "99.9 %" or "4 hours" — the target as a reader would say it.
  def target_label(locale = I18n.locale)
    return "" if target_value.blank?

    value = target_value.to_f
    formatted = (value % 1).zero? ? value.to_i.to_s : value.to_s
    [ formatted, unit_label(locale) ].compact_blank.join(" ")
  end

  # A commitment nobody can measure is a statement of intent, and the document
  # should not present it as a service level.
  def measurable?
    target_value.present? && measurement_method.present?
  end

  private

  def unit_must_suit_the_metric
    return if target_unit.blank? || !METRICS.include?(metric)
    return if UNITS_FOR_METRIC.fetch(metric, []).include?(target_unit)

    errors.add(:target_unit, I18n.t("sla.errors.unit_mismatch"))
  end

  def percentage_targets_stay_within_range
    return unless target_unit == "percent" && target_value.present?
    return if target_value <= 100

    errors.add(:target_value, I18n.t("sla.errors.percent_range"))
  end
end
