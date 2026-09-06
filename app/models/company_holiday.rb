# A named non-working range excluded from working-day counts.
class CompanyHoliday < ApplicationRecord
  belongs_to :company

  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_after_start

  scope :ordered, -> { order(:start_date) }

  def range
    (start_date..end_date)
  end

  private

  def end_after_start
    return if start_date.blank? || end_date.blank? || end_date >= start_date

    errors.add(:end_date, I18n.t("documenter.errors.end_before_start"))
  end
end
