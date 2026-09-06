class PpPackage < ApplicationRecord
  belongs_to :company
  has_many :pp_records, class_name: "PpRecord", foreign_key: "package_id", dependent: :nullify

  validates :name, presence: true, length: { maximum: 250 }
  validate :end_date_after_start_date

  scope :ordered, -> { order(created_at: :desc) }

  # Progress is reported against the package's OWN window, not a hard-coded
  # year: how many of its records have been completed so far.
  def records_count
    pp_records.size
  end

  def completed_count
    pp_records.count { |r| r.completed? }
  end

  def completion_percentage
    total = records_count
    return 0.0 if total.zero?

    (completed_count.to_f / total * 100).round(1)
  end

  def window_label
    return nil if start_date.blank? && end_date.blank?

    [ start_date, end_date ].compact.map { |d| d.strftime("%Y-%m-%d") }.join(" → ")
  end

  private

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank? || end_date >= start_date

    errors.add(:end_date, I18n.t("pp_records.errors.end_before_start"))
  end
end
