require "test_helper"

class WorkingDaysServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "WD Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
  end

  # 2026-07-19 is a Sunday. Default weekend is Friday + Saturday.
  SUNDAY = Date.new(2026, 7, 19)

  test "counts weekdays and skips the default Friday-Saturday weekend" do
    # Sunday -> the following Sunday is 7 calendar days, minus Fri + Sat.
    assert_equal 5, WorkingDaysService.between(@company, SUNDAY, SUNDAY + 7)
  end

  test "the arrival day itself does not count" do
    assert_equal 0, WorkingDaysService.between(@company, SUNDAY, SUNDAY)
    assert_equal 1, WorkingDaysService.between(@company, SUNDAY, SUNDAY + 1)
  end

  test "a weekend day adds nothing" do
    friday = Date.new(2026, 7, 24)
    saturday = friday + 1
    assert_equal 0, WorkingDaysService.between(@company, friday - 1, saturday)
  end

  test "the weekend is configurable" do
    @company.update!(weekend_days: [ 0, 6 ]) # Sunday + Saturday

    # From Sunday over a week: Sundays and Saturdays are off instead.
    assert_equal 5, WorkingDaysService.between(@company, SUNDAY, SUNDAY + 7)
    refute WorkingDaysService.new(@company).working_day?(SUNDAY)
    assert WorkingDaysService.new(@company).working_day?(Date.new(2026, 7, 24)) # Friday now works
  end

  test "holiday ranges are excluded" do
    @company.company_holidays.create!(name: "Eid", start_date: SUNDAY + 1, end_date: SUNDAY + 2)

    # Two working days removed from the same week.
    assert_equal 3, WorkingDaysService.between(@company, SUNDAY, SUNDAY + 7)
  end

  test "a holiday falling on a weekend does not double-count" do
    friday = Date.new(2026, 7, 24)
    @company.company_holidays.create!(name: "Overlap", start_date: friday, end_date: friday)

    assert_equal 5, WorkingDaysService.between(@company, SUNDAY, SUNDAY + 7)
  end

  test "reversed or blank input counts zero" do
    assert_equal 0, WorkingDaysService.between(@company, SUNDAY + 5, SUNDAY)
    assert_equal 0, WorkingDaysService.between(@company, nil, SUNDAY)
    assert_equal 0, WorkingDaysService.between(@company, SUNDAY, nil)
  end

  test "falls back to the default weekend when misconfigured" do
    @company.update_column(:weekend_days, [])
    assert_equal WorkingDaysService::DEFAULT_WEEKEND, WorkingDaysService.new(@company).weekend_days
  end
end
