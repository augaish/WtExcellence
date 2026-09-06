require "test_helper"

class HierarchicalCodeServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Code Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
  end

  test "numbers root org units sequentially" do
    assert_equal "01", HierarchicalCodeService.next_org_unit_code(company: @company)

    @company.org_units.create!(name_en: "A", level: 1, code: "01")
    assert_equal "02", HierarchicalCodeService.next_org_unit_code(company: @company)
  end

  test "nests child codes under the parent code" do
    parent = @company.org_units.create!(name_en: "A", level: 1, code: "01")

    assert_equal "01-01", HierarchicalCodeService.next_org_unit_code(company: @company, parent: parent)

    @company.org_units.create!(name_en: "B", level: 2, code: "01-01", parent: parent)
    assert_equal "01-02", HierarchicalCodeService.next_org_unit_code(company: @company, parent: parent)
  end

  test "process root codes carry the P- prefix" do
    assert_equal "P-01", HierarchicalCodeService.next_process_code(company: @company)

    @company.pp_processes.create!(name_en: "A", level: 1, code: "P-01")
    assert_equal "P-02", HierarchicalCodeService.next_process_code(company: @company)
  end

  test "skips codes already taken by a manual entry" do
    @company.org_units.create!(name_en: "A", level: 1, code: "01")
    @company.org_units.create!(name_en: "B", level: 1, code: "02")

    assert_equal "03", HierarchicalCodeService.next_org_unit_code(company: @company)
  end
end
