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

  COMPARATORS = %w[at_least at_most].freeze
  PERIODS = %w[monthly quarterly annual].freeze

  # "At least" for availability and accuracy; "at most" for times. The row
  # says which, so a measurement can be judged without guessing.
  DEFAULT_COMPARATOR = {
    "availability" => "at_least", "accuracy" => "at_least",
    "response_time" => "at_most", "resolution_time" => "at_most", "delivery_frequency" => "at_most", "other" => "at_least"
  }.freeze

  belongs_to :accountable_org_unit, class_name: "OrgUnit", optional: true
  has_many :measurements, -> { ordered }, class_name: "SlaMeasurement", foreign_key: "pp_service_level_id", dependent: :destroy

  validates :comparator, inclusion: { in: COMPARATORS }, allow_blank: true
  validates :measurement_period, inclusion: { in: PERIODS }, allow_blank: true
  validates :measurement_source, length: { maximum: 250 }
  validates :exclusions, length: { maximum: 2000 }
  validate :effective_dates_ordered
  before_validation { self.comparator = DEFAULT_COMPARATOR[metric] if comparator.blank? && METRICS.include?(metric.to_s) }

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

  def comparator_label(locale = I18n.locale)
    comparator.present? ? I18n.t("sla.comparators.#{comparator}", locale: locale) : ""
  end

  def period_label(locale = I18n.locale)
    measurement_period.present? ? I18n.t("sla.periods.#{measurement_period}", locale: locale) : ""
  end

  # Attainment over the reviewed periods: met ÷ measured. Nil until something
  # has been measured, so an unmeasured level never reads as 100%.
  def attainment_percent
    counted = measurements.reviewed
    return nil if counted.none?

    (counted.where(met: true).count * 100.0 / counted.count).round(1)
  end

  def breaches
    measurements.reviewed.where(met: false).count
  end

  private

  def effective_dates_ordered
    return if effective_from.blank? || effective_to.blank? || effective_to >= effective_from

    errors.add(:effective_to, I18n.t("sla.errors.period_order"))
  end

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
