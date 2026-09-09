require "test_helper"

class PpProcessTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Proc Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    @l1 = @company.pp_processes.create!(name_en: "Governance", level: 1, category: "management")
  end

  test "requires a name in at least one language" do
    process = @company.pp_processes.new(level: 1, category: "core")
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

    assert_equal "management", l2.category
    assert_equal "management", l2.effective_category
  end

  test "a level 2 process always takes its parent's band" do
    l2 = @company.pp_processes.create!(name_en: "Ops", level: 2, parent: @l1, category: "core")

    assert_equal "management", l2.effective_category
  end

  test "a level 1 process must belong to a Level 0 band" do
    refute @company.pp_processes.new(name_en: "Loose", level: 1).valid?
  end

  test "numbers run within the band for level 1 and within the parent for level 2" do
    assert_equal 1, @l1.number
    second = @company.pp_processes.create!(name_en: "Audit", level: 1, category: "management")
    core = @company.pp_processes.create!(name_en: "Design", level: 1, category: "core")
    assert_equal 2, second.number
    assert_equal 1, core.number

    child = @company.pp_processes.create!(name_en: "Plan", level: 2, parent: second)
    child2 = @company.pp_processes.create!(name_en: "Execute", level: 2, parent: second)
    assert_equal [ 1, 2 ], [ child.number, child2.number ]
  end

  test "the architecture number reads band, level 1 and level 2" do
    second = @company.pp_processes.create!(name_en: "Audit", level: 1, category: "management")
    child = @company.pp_processes.create!(name_en: "Plan", level: 2, parent: second)
    core = @company.pp_processes.create!(name_en: "Design", level: 1, category: "core")

    assert_equal "1.2", second.architecture_number
    assert_equal "1.2.1", child.architecture_number
    assert_equal "2.1", core.architecture_number
  end

  test "a blank code becomes the architecture number; a typed code stays" do
    auto = @company.pp_processes.create!(name_en: "Audit", level: 1, category: "management")
    typed = @company.pp_processes.create!(name_en: "Risk", level: 1, category: "management", code: "RISK")

    assert_equal "1.2", auto.code
    assert_equal "RISK", typed.code
  end

  test "rejects unknown enum values" do
    refute @company.pp_processes.new(name_en: "X", level: 1, category: "bogus").valid?
    refute @company.pp_processes.new(name_en: "X", level: 1, category: "core", frequency: "fortnightly").valid?
    refute @company.pp_processes.new(name_en: "X", level: 1, category: "core", automation_status: "magic").valid?
  end

  test "rejects a cycle in the process tree" do
    l2 = @company.pp_processes.create!(name_en: "Child", level: 2, parent: @l1)
    @l1.parent = l2
    refute @l1.valid?
  end

  test "code is unique per company" do
    @company.pp_processes.create!(name_en: "A", level: 1, category: "core", code: "P-01")
    refute @company.pp_processes.new(name_en: "B", level: 1, category: "core", code: "P-01").valid?
  end

  test "nothing sits below level 2: procedures live in Records" do
    l2 = @company.pp_processes.create!(name_en: "L2", level: 2, parent: @l1)

    refute @company.pp_processes.new(name_en: "L3", level: 3, parent: l2).valid?
  end
end
