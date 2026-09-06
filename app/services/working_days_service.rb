# Counts working days between two moments for a company, skipping that
# company's configured weekend and any holiday ranges.
#
# Used to decide whether a record has been sitting in its stage longer than the
# stage's target. Both endpoints come from system timestamps, never from a
# typed date, so the count reflects what actually happened.
class WorkingDaysService
  DEFAULT_WEEKEND = [ 5, 6 ].freeze # Friday, Saturday (Ruby wday)

  def self.between(company, from, to = Time.current)
    new(company).between(from, to)
  end

  def self.elapsed_since(company, from)
    new(company).between(from, Time.current)
  end

  def initialize(company)
    @company = company
  end

  # Whole working days elapsed from `from` to `to`. The start day is not
  # counted (a record that arrived today has been sitting 0 days); each
  # subsequent working day counts 1. Returns 0 for nil or reversed input.
  def between(from, to = Time.current)
    return 0 if from.blank? || to.blank?

    start_date = to_date(from)
    end_date = to_date(to)
    return 0 if end_date <= start_date

    count = 0
    cursor = start_date + 1
    while cursor <= end_date
      count += 1 if working_day?(cursor)
      cursor += 1
    end
    count
  end

  def working_day?(date)
    return false if weekend_days.include?(date.wday)

    !holiday?(date)
  end

  def weekend_days
    @weekend_days ||= begin
      configured = @company&.weekend_days
      list = Array(configured).map { |d| d.to_i }.select { |d| d.between?(0, 6) }
      list.presence || DEFAULT_WEEKEND
    end
  end

  def holiday?(date)
    holiday_ranges.any? { |range| range.cover?(date) }
  end

  private

  def holiday_ranges
    @holiday_ranges ||= begin
      return [] unless @company.respond_to?(:company_holidays)

      @company.company_holidays.map { |h| (h.start_date..h.end_date) }
    rescue StandardError
      []
    end
  end

  def to_date(value)
    value.respond_to?(:to_date) ? value.to_date : Date.parse(value.to_s)
  end
end
