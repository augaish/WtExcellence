require "test_helper"

# The executive matrix. The rules tested here are the ones the source document
# states in prose and no spreadsheet can enforce.
class ExecutiveAuthorityTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "DoA Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA 2026",
      version_label: "v2")
    @category = @company.authority_categories.create!(name_en: "Contracting", name_ar: "التعاقد")
    @minister = @company.org_units.create!(name_en: "Minister", name_ar: "الوزير", level: 1)
    @deputy = @company.org_units.create!(name_en: "Deputy Minister", name_ar: "نائب الوزير", level: 2, parent: @minister)
  end

  def authority(**attributes)
    @company.authorities.create!({ matrix: @matrix, authority_category: @category,
      name_en: "Sign contracts" }.merge(attributes))
  end

  test "an authority must live in an executive matrix, not any record" do
    policy = @company.pp_records.create!(record_type: "policy", title_en: "A policy")
    wrong = @company.authorities.new(matrix: policy, name_en: "Sign contracts")

    assert_not wrong.valid?
    assert_predicate wrong.errors[:matrix], :present?
  end

  test "an authority always has somewhere to hang its holders" do
    assert_equal 1, authority.bands.count
    assert_not authority.bands.sole.bounded?
  end

  test "a band derives a readable label when none is written" do
    subject = authority
    band = subject.bands.sole

    assert_equal "All amounts", band.display_label
    band.update!(max_amount: 3_000_000)
    assert_equal "Up to 3,000,000", band.reload.display_label

    band.update!(min_amount: 1_000_000)
    assert_equal "Above 1,000,000 and up to 3,000,000", band.reload.display_label
  end

  test "one authority carries its thresholds instead of repeating the whole row" do
    subject = authority
    first = subject.bands.sole
    first.update!(max_amount: 3_000_000)
    second = subject.bands.create!(min_amount: 3_000_000, max_amount: 6_000_000)

    assert first.covers?(2_999_999)
    assert_not first.covers?(3_000_000), "bands are exclusive of their upper bound"
    assert second.covers?(3_000_000)
    assert_not second.covers?(6_000_000)
  end

  test "two bands cannot both claim the same amount" do
    subject = authority
    subject.bands.sole.update!(max_amount: 3_000_000)
    overlapping = subject.bands.new(min_amount: 2_000_000, max_amount: 5_000_000)

    assert_not overlapping.valid?
    assert_predicate overlapping.errors[:base], :present?
  end

  test "a band's upper bound must exceed its lower bound" do
    band = authority.bands.sole
    band.max_amount = 100
    band.min_amount = 500

    assert_not band.valid?
    assert_predicate band.errors[:max_amount], :present?
  end

  test "an authority nobody may finally authorize is reported" do
    subject = authority
    band = subject.bands.sole
    band.assignments.create!(level: "prepare", org_unit: @deputy)

    assert_equal [ band ], subject.reload.bands_without_single_authorizer

    band.assignments.create!(level: "authorize", org_unit: @minister)
    assert_empty subject.reload.bands_without_single_authorizer
  end

  test "two final authorizers in one band is reported" do
    subject = authority
    band = subject.bands.sole
    band.assignments.create!(level: "authorize", org_unit: @minister)
    band.assignments.create!(level: "authorize", org_unit: @deputy)

    assert_equal [ band ], subject.reload.bands_without_single_authorizer
  end

  test "one unit preparing, reviewing and authorizing is a breach" do
    subject = authority
    band = subject.bands.sole
    %w[prepare review authorize].each { |level| band.assignments.create!(level: level, org_unit: @deputy) }

    assert_includes subject.reload.segregation_breaches, @deputy.id
  end

  test "a holder may be an org unit, a dynamic role, or a written position" do
    band = authority.bands.sole

    unit = band.assignments.create!(level: "authorize", org_unit: @minister)
    role = band.assignments.create!(level: "review", dynamic_role: "owning_unit")
    written = band.assignments.create!(level: "inform", holder_title: "The concerned adviser")

    assert_equal "Minister", unit.holder_label
    assert_equal "The owning unit", role.holder_label
    assert_equal "The concerned adviser", written.holder_label
  end

  test "an assignment must name some holder" do
    nameless = authority.bands.sole.assignments.new(level: "authorize")

    assert_not nameless.valid?
    assert_predicate nameless.errors[:base], :present?
  end

  test "a dynamic role resolves against the org structure" do
    band = authority.bands.sole
    parent_role = band.assignments.create!(level: "authorize", dynamic_role: "parent_unit")
    owning_role = band.assignments.create!(level: "prepare", dynamic_role: "owning_unit")

    assert_equal @minister, parent_role.resolve(@deputy)
    assert_equal @deputy, owning_role.resolve(@deputy)
    assert_nil parent_role.resolve(@minister), "a top-level unit has no parent to resolve to"
  end

  test "an authority records the regulation it derives from" do
    policy = @company.pp_records.create!(record_type: "policy", title_en: "Contracting Policy")
    with_basis = authority(basis_record: policy)

    assert_equal "Contracting Policy", with_basis.basis_label
    assert_nil authority(name_en: "Another").basis_label
    assert_includes @company.authorities.without_basis.map(&:name_en), "Another"
  end

  test "an assignment cannot name another company's unit" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, credits: 1, is_active: true)
    foreign = other.org_units.create!(name_en: "Foreign", level: 1)
    assignment = authority.bands.sole.assignments.new(level: "authorize", org_unit: foreign)

    assert_not assignment.valid?
    assert_predicate assignment.errors[:org_unit], :present?
  end
end
