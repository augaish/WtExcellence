require "test_helper"

class PpRecordTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Rec Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    @pkg_a = @company.pp_packages.create!(name: "Package A")
    @pkg_b = @company.pp_packages.create!(name: "Package B")
  end

  def build_record(**attrs)
    @company.pp_records.new({ record_type: "policy", title_en: "Data Policy" }.merge(attrs))
  end

  test "requires a title in at least one language" do
    record = build_record(title_en: nil)
    refute record.valid?

    record.title_ar = "سياسة البيانات"
    assert record.valid?
  end

  test "rejects an unknown record type" do
    refute build_record(record_type: "memo").valid?

    PpRecord::TYPES.each do |type|
      # Types that describe work inside one process need that process; the rest
      # stand alone.
      attributes = { record_type: type }
      attributes[:pp_process] = process_for_records if PpRecord::PROCESS_ENFORCED_TYPES.include?(type)

      assert build_record(**attributes).valid?, "#{type} should be valid"
    end
  end

  def process_for_records
    @process_for_records ||= @company.pp_processes.create!(name_en: "Host process", level: 1, category: "core")
  end

  test "code is unique per company" do
    build_record(code: "POL-01").save!
    refute build_record(code: "POL-01", title_en: "Other").valid?
  end

  test "review date cannot precede the effective date" do
    record = build_record(effective_date: Date.new(2026, 1, 10), review_date: Date.new(2026, 1, 1))
    refute record.valid?

    record.review_date = Date.new(2027, 1, 10)
    assert record.valid?
  end

  # ---- The single-package invariant -------------------------------------

  test "a new record is unpackaged" do
    record = build_record
    record.save!
    refute record.packaged?
    assert_nil record.package
  end

  test "assigning to a package sets it" do
    record = build_record
    record.save!

    record.assign_to_package!(@pkg_a)

    assert_equal @pkg_a.id, record.reload.package_id
    assert record.packaged?
  end

  # This is the rule that stops one package silently stealing another's record.
  test "assigning a record already in another package raises PackageConflict" do
    record = build_record
    record.save!
    record.assign_to_package!(@pkg_a)

    error = assert_raises(PpRecord::PackageConflict) do
      record.assign_to_package!(@pkg_b)
    end

    assert_equal @pkg_a.id, error.current_package.id
    assert_equal @pkg_a.id, record.reload.package_id, "the record must not have moved"
  end

  test "an explicit re-assign moves the record" do
    record = build_record
    record.save!
    record.assign_to_package!(@pkg_a)

    record.assign_to_package!(@pkg_b, reassign: true)

    assert_equal @pkg_b.id, record.reload.package_id
  end

  test "re-assigning to the same package is a no-op, not a conflict" do
    record = build_record
    record.save!
    record.assign_to_package!(@pkg_a)

    assert_nothing_raised { record.assign_to_package!(@pkg_a) }
    assert_equal @pkg_a.id, record.reload.package_id
  end

  test "removing from a package leaves the record intact" do
    record = build_record
    record.save!
    record.assign_to_package!(@pkg_a)

    record.remove_from_package!

    refute record.reload.packaged?
    assert PpRecord.exists?(record.id)
  end

  test "a package from another company is rejected" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 1, is_active: true)
    foreign_package = other.pp_packages.create!(name: "Foreign")

    record = build_record(package: foreign_package)
    refute record.valid?
  end

  # ---- Review dates -----------------------------------------------------

  test "flags an overdue review" do
    record = build_record(review_date: Date.current - 1)
    assert record.review_overdue?
    refute record.review_due_soon?
  end

  test "flags a review due soon within the lead time" do
    record = build_record(review_date: Date.current + 10)
    assert record.review_due_soon?(30)
    refute record.review_overdue?
  end

  test "a distant review is neither due soon nor overdue" do
    record = build_record(review_date: Date.current + 200)
    refute record.review_due_soon?(30)
    refute record.review_overdue?
  end

  test "completed? follows the terminal lifecycle stages" do
    refute build_record(current_stage: "s2_prep").completed?
    assert build_record(current_stage: "s5_published").completed?
    assert build_record(current_stage: "s5_closed").completed?
  end
end
