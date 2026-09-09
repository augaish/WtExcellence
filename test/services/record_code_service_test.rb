require "test_helper"

class RecordCodeServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Code #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    @hr = @company.org_units.create!(name_en: "Human Resources", level: 1, code: "HR")
  end

  test "policies number per type and unit" do
    first = @company.pp_records.create!(record_type: "policy", title_en: "A", owner_org_unit: @hr)
    second = @company.pp_records.create!(record_type: "policy", title_en: "B", owner_org_unit: @hr)
    form = @company.pp_records.create!(record_type: "form", title_en: "C", owner_org_unit: @hr)

    assert_equal "POL-HR-001-V1", first.code
    assert_equal "POL-HR-002-V1", second.code
    assert_equal "FRM-HR-001-V1", form.code
  end

  test "a unit without a code contributes the initials of its name" do
    unit = @company.org_units.create!(name_en: "General Services Management", level: 1)
    record = @company.pp_records.create!(record_type: "service", title_en: "Cleaning", owner_org_unit: unit)

    assert_equal "SEV-GSM-001-V1", record.code
  end

  test "no owning unit falls back to GEN" do
    record = @company.pp_records.create!(record_type: "glossary", title_en: "CAPA")
    assert_equal "GLO-GEN-001-V1", record.code
  end

  test "a procedure takes its level-2 process number plus its own sequence" do
    l1 = @company.pp_processes.create!(name_en: "Human capital", level: 1, category: "support")
    l2 = @company.pp_processes.create!(name_en: "Recruiting", level: 2, parent: l1)
    first = @company.pp_records.create!(record_type: "procedure", title_en: "Hire", owner_org_unit: @hr, pp_process: l2)
    second = @company.pp_records.create!(record_type: "procedure", title_en: "Onboard", owner_org_unit: @hr, pp_process: l2)

    assert_equal "PROC-HR-3.1.1.1-V1", first.code
    assert_equal "PROC-HR-3.1.1.2-V1", second.code
  end

  test "a typed code is kept and the version tail moves on a new version" do
    record = @company.pp_records.create!(record_type: "policy", title_en: "A", owner_org_unit: @hr, code: "CUSTOM-9")
    assert_equal "CUSTOM-9", record.code
    assert_equal "CUSTOM-9-V2", RecordCodeService.next_version_code(record.code, 2)
    assert_equal "POL-HR-001-V3", RecordCodeService.next_version_code("POL-HR-001-V2", 3)
  end
end
