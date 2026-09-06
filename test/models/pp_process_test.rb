require "test_helper"

class PpProcessTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Proc Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    @l1 = @company.pp_processes.create!(name_en: "Governance", level: 1, category: "management")
  end

  test "requires a name in at least one language" do
    process = @company.pp_processes.new(level: 1)
    refute process.valid?

    process.name_ar = "الحوكمة"
    assert process.valid?
  end

  test "a root process must be level 1" do
    refute @company.pp_processes.new(name_en: "Orphan", level: 2).valid?
  end

  test "a child must be exactly one level below its parent" do
    good = @company.pp_processes.new(name_en: "Policy Mgmt", level: 2, parent: @l1)
    assert good.valid?, good.errors.full_messages.join(", ")

    skipped = @company.pp_processes.new(name_en: "Too deep", level: 3, parent: @l1)
    refute skipped.valid?
  end

  test "category is inherited from the parent when blank" do
    l2 = @company.pp_processes.create!(name_en: "Policy Mgmt", level: 2, parent: @l1)

    assert_nil l2.category
    assert_equal "management", l2.effective_category
  end

  test "an explicit category overrides the inherited one" do
    l2 = @company.pp_processes.create!(name_en: "Ops", level: 2, parent: @l1, category: "core")

    assert_equal "core", l2.effective_category
  end

  test "rejects unknown enum values" do
    refute @company.pp_processes.new(name_en: "X", level: 1, category: "bogus").valid?
    refute @company.pp_processes.new(name_en: "X", level: 1, frequency: "fortnightly").valid?
    refute @company.pp_processes.new(name_en: "X", level: 1, automation_status: "magic").valid?
  end

  test "rejects a cycle in the process tree" do
    l2 = @company.pp_processes.create!(name_en: "Child", level: 2, parent: @l1)
    @l1.parent = l2
    refute @l1.valid?
  end

  test "code is unique per company" do
    @company.pp_processes.create!(name_en: "A", level: 1, code: "P-01")
    refute @company.pp_processes.new(name_en: "B", level: 1, code: "P-01").valid?
  end

  test "levels deeper than three are rejected" do
    l2 = @company.pp_processes.create!(name_en: "L2", level: 2, parent: @l1)
    l3 = @company.pp_processes.create!(name_en: "L3", level: 3, parent: l2)

    assert l3.valid?
    refute @company.pp_processes.new(name_en: "L4", level: 4, parent: l3).valid?
  end
end
