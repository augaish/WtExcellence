# One measured period of one service level: what the number actually was,
# where it came from, and whether the target was met. Attainment is counted
# from these, never from the promise.
class SlaMeasurement < ApplicationRecord
  belongs_to :service_level, class_name: "PpServiceLevel", foreign_key: "pp_service_level_id"
  belongs_to :recorded_by, class_name: "User", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :period_start, :period_end, :actual_value, presence: true
  validates :source_note, length: { maximum: 2000 }
  validate :period_must_be_ordered
  validate :level_must_be_measurable

  before_validation :judge

  scope :ordered, -> { order(period_start: :desc) }
  scope :reviewed, -> { where.not(reviewed_at: nil) }

  def reviewed?
    reviewed_at.present?
  end

  def review!(by:)
    update!(reviewed_by: by, reviewed_at: Time.current)
  end

  private

  # Met or breached follows the level's comparator, so a 99.95% availability
  # against "at least 99.9%" is met and a 5-hour response against "at most 4
  # hours" is a breach.
  def judge
    return if service_level.nil? || actual_value.nil? || service_level.target_value.nil?

    self.met = service_level.comparator == "at_most" ? actual_value <= service_level.target_value : actual_value >= service_level.target_value
  end

  def period_must_be_ordered
    return if period_start.blank? || period_end.blank? || period_end >= period_start

    errors.add(:period_end, I18n.t("sla.errors.period_order"))
  end

  def level_must_be_measurable
    return if service_level.nil? || service_level.measurable?

    errors.add(:base, I18n.t("sla.errors.not_measurable_level"))
  end
end
