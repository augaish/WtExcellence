require "test_helper"

class PpPackageTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Pkg Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    @package = @company.pp_packages.create!(name: "Q1 Review")
  end

  def add_record(stage: nil)
    @company.pp_records.create!(
      record_type: "policy", title_en: "Doc #{SecureRandom.hex(3)}",
      package: @package, current_stage: stage
    )
  end

  test "requires a name" do
    refute @company.pp_packages.new.valid?
  end

  test "end date cannot precede the start date" do
    package = @company.pp_packages.new(name: "Bad window",
      start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 1, 1))
    refute package.valid?

    package.end_date = Date.new(2026, 12, 1)
    assert package.valid?
  end

  test "progress is zero with no records" do
    assert_equal 0, @package.records_count
    assert_equal 0.0, @package.completion_percentage
  end

  # Progress is measured against the package's OWN membership, not a calendar year.
  test "progress counts completed records" do
    add_record(stage: "s5_published")
    add_record(stage: "s2_prep")
    add_record(stage: nil)
    @package.reload

    assert_equal 3, @package.records_count
    assert_equal 1, @package.completed_count
    assert_in_delta 33.3, @package.completion_percentage, 0.1
  end

  test "deleting a package unpackages its records rather than deleting them" do
    record = add_record
    @package.destroy

    assert PpRecord.exists?(record.id)
    assert_nil record.reload.package_id
  end

  test "window label shows the configured dates" do
    @package.update!(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 3, 31))
    assert_equal "2026-01-01 → 2026-03-31", @package.window_label
  end

  test "window label is absent when no dates are set" do
    assert_nil @package.window_label
  end
end
