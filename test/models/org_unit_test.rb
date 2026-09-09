require "test_helper"

class OrgUnitTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Org Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    @ceo = @company.org_units.create!(name_en: "CEO", level: 1)
  end

  test "requires a name in at least one language" do
    unit = @company.org_units.new(level: 2)
    refute unit.valid?

    unit.name_ar = "إدارة الجودة"
    assert unit.valid?
  end

  test "a unit may report to a higher-ranked unit" do
    vp = @company.org_units.new(name_en: "VP", level: 2, parent: @ceo)
    assert vp.valid?, vp.errors.full_messages.join(", ")
  end

  # The key rule: a GM (level 4) may report to a CEO (1) or a VP (2), but a
  # higher-ranked unit can never report to a lower-ranked one.
  test "a unit cannot report to a lower or equal ranked unit" do
    manager = @company.org_units.create!(name_en: "Manager", level: 5, parent: @ceo)

    director = @company.org_units.new(name_en: "Director", level: 4, parent: manager)
    refute director.valid?
    assert_includes director.errors[:parent_id].join, "higher rank"

    peer = @company.org_units.new(name_en: "Another CEO", level: 1, parent: @ceo)
    refute peer.valid?
  end

  test "a GM can report to either the CEO or a VP in the same company" do
    vp = @company.org_units.create!(name_en: "VP", level: 2, parent: @ceo)

    gm_under_ceo = @company.org_units.new(name_en: "GM A", level: 4, parent: @ceo)
    gm_under_vp  = @company.org_units.new(name_en: "GM B", level: 4, parent: vp)

    assert gm_under_ceo.valid?, gm_under_ceo.errors.full_messages.join(", ")
    assert gm_under_vp.valid?, gm_under_vp.errors.full_messages.join(", ")
  end

  test "rejects a parent from another company" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 1, is_active: true)
    foreign = other.org_units.create!(name_en: "Foreign", level: 1)

    unit = @company.org_units.new(name_en: "Child", level: 2, parent: foreign)
    refute unit.valid?
  end

  test "rejects a unit that is its own parent" do
    @ceo.parent = @ceo
    refute @ceo.valid?
  end

  test "rejects a cycle in the reporting line" do
    vp = @company.org_units.create!(name_en: "VP", level: 2, parent: @ceo)
    @ceo.parent = vp
    refute @ceo.valid?
  end

  test "code is unique per company but reusable across companies" do
    @company.org_units.create!(name_en: "A", level: 2, code: "01")
    dup = @company.org_units.new(name_en: "B", level: 2, code: "01")
    refute dup.valid?

    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 1, is_active: true)
    assert other.org_units.new(name_en: "C", level: 1, code: "01").valid?
  end

  test "mandates round-trip as a clean list" do
    unit = @company.org_units.create!(name_en: "Quality", level: 2)
    unit.mandate_list = [ "Own the QMS", "  ", "Approve policies" ]
    unit.save!

    assert_equal [ "Own the QMS", "Approve policies" ], unit.reload.mandate_list
  end

  test "ancestors returns the chain from the root down" do
    vp = @company.org_units.create!(name_en: "VP", level: 2, parent: @ceo)
    gm = @company.org_units.create!(name_en: "GM", level: 3, parent: vp)

    assert_equal [ @ceo.id, vp.id ], gm.ancestors.map(&:id)
  end

  test "level must be within 1..9 and is shown as a number" do
    assert @company.org_units.new(name_en: "X", level: 9).valid?
    refute @company.org_units.new(name_en: "X", level: 10).valid?
    refute @company.org_units.new(name_en: "X", level: 0).valid?
    assert_equal "Level 3", @company.org_units.new(name_en: "X", level: 3).level_name(:en)
  end
end
